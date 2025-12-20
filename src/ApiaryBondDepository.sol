// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IApiaryTreasury } from "./interfaces/IApiaryTreasury.sol";
import { IApiaryToken } from "./interfaces/IApiaryToken.sol";
import { IApiaryBondingCalculator } from "./interfaces/IApiaryBondingCalculator.sol";
import { IApiaryUniswapV2TwapOracle } from "./interfaces/IApiaryUniswapV2TwapOracle.sol";

/**
 * @title ApiaryBondDepository
 * @notice Enables APIARY bond purchases using iBGT or APIARY/HONEY LP tokens
 * @dev Bonds are priced using TWAP oracle with a manual discount rate
 *      Vesting occurs linearly over 5 days (configurable)
 *      Users can have multiple independent bonds, each with its own vesting schedule
 * 
 * Key Features:
 * - Primary principle: iBGT (Infrared BGT)
 * - Secondary principle: APIARY/HONEY LP from Kodiak
 * - TWAP-based pricing with discount
 * - Linear vesting over 5 days
 * - Multiple bonds per user with independent vesting
 * - Slippage protection
 * - Debt and payout limits
 * 
 * Security:
 * - ReentrancyGuard on deposit/redeem
 * - Pausable in emergency
 * - Ownable2Step for admin
 * - Slippage protection via maxPriceInHoney
 * - TWAP manipulation resistance (1 hour minimum)
 */
contract ApiaryBondDepository is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bond terms configuration
     * @param vestingTerm Duration of vesting in blocks (5 days default)
     * @param maxPayout Maximum payout as % of total allocation (in thousandths)
     * @param discountRate Discount from market price (in basis points)
     * @param maxDebt Maximum total debt allowed
     */
    struct Terms {
        uint256 vestingTerm;   // in blocks
        uint256 maxPayout;     // in thousandths of a %. i.e. 500 = 0.5%
        uint256 discountRate;  // in basis points (100 = 1%)
        uint256 maxDebt;       // maximum total debt allowed
    }

    /**
     * @notice Individual bond information
     * @param payout APIARY remaining to be paid
     * @param pricePaid Price paid per APIARY in HONEY (for UI display)
     * @param vestingStart Block when bond was created
     * @param vestingEnd Block when bond is fully vested
     * @param redeemed Whether the bond has been fully redeemed
     */
    struct Bond {
        uint256 payout;         // APIARY remaining to be paid
        uint256 pricePaid;      // Price paid per APIARY in HONEY (for records)
        uint48 vestingStart;    // Block when bond was created
        uint48 vestingEnd;      // Block when fully vested
        bool redeemed;          // Whether fully redeemed
    }

    /**
     * @notice Parameters that can be adjusted
     */
    enum PARAMETER {
        VESTING,        // 0
        PAYOUT,         // 1
        DISCOUNT_RATE,  // 2
        MAX_DEBT        // 3
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant BPS = 10_000;              // Basis points (10_000 = 100%)
    uint256 public constant MINIMUM_PAYOUT = 10_000_000; // 0.01 APIARY minimum
    uint256 private constant PRECISION = 1e18;
    
    // Berachain average block time: ~5 seconds
    // 5 days = 5 * 24 * 60 * 60 / 5 = 86,400 blocks
    uint256 public constant DEFAULT_VESTING_TERM = 86_400;
    
    // Minimum vesting term: 1 day = 17,280 blocks
    uint256 public constant MINIMUM_VESTING_TERM = 17_280;

    address public immutable principle;          // iBGT or LP token
    bool public immutable isLiquidityBond;       // true if LP bond
    address public immutable bondCalculator;     // LP valuation calculator
    address public immutable treasury;           // Treasury address
    address public immutable APIARY;             // APIARY token address

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping from user address to array of their bonds
    mapping(address => Bond[]) public userBonds;
    
    /// @notice Bond terms configuration
    Terms public terms;
    
    /// @notice Total outstanding debt (decreases on redemption)
    uint256 public totalDebt;
    
    /// @notice TWAP oracle for pricing
    IApiaryUniswapV2TwapOracle public twap;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_AMOUNT();
    error APIARY__INVALID_DISCOUNT_RATE();
    error APIARY__ALREADY_INITIALIZED();
    error APIARY__INVALID_VESTING_TERM();
    error APIARY__INVALID_MAX_PAYOUT();
    error APIARY__INVALID_MAX_PRICE();
    error APIARY__SLIPPAGE_LIMIT_EXCEEDED();
    error APIARY__BOND_TOO_SMALL();
    error APIARY__BOND_TOO_LARGE();
    error APIARY__BOND_SOLD_OUT();
    error APIARY__NO_REDEEMABLE_BOND();
    error APIARY__INVALID_BOND_INDEX();
    error APIARY__BOND_ALREADY_REDEEMED();
    error APIARY__NOTHING_TO_REDEEM();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TwapUpdated(address indexed twap);
    event BondTermsUpdated(PARAMETER indexed parameter, uint256 indexed input);
    event TokensClawedBack(address indexed token, uint256 indexed amount);
    event BondTermsInitialized(
        uint256 indexed vestingTerm,
        uint256 indexed maxPayout,
        uint256 discountRate,
        uint256 maxDebt
    );
    event BondCreated(
        address indexed user,
        uint256 indexed bondIndex,
        uint256 principleAmount,
        uint256 payout,
        uint256 vestingEnd,
        uint256 priceInHoney
    );
    event BondRedeemed(
        address indexed user,
        uint256 indexed bondIndex,
        uint256 payoutRedeemed,
        uint256 payoutRemaining
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the bond depository
     * @param _apiary APIARY token address
     * @param _principle Principle token (iBGT or APIARY/HONEY LP)
     * @param _treasury Treasury address
     * @param admin Admin address (owner)
     * @param _bondCalculator LP calculator (address(0) if not LP bond)
     * @param _twap TWAP oracle address
     */
    constructor(
        address _apiary,
        address _principle,
        address _treasury,
        address admin,
        address _bondCalculator,
        address _twap
    ) Ownable(admin) {
        if (
            _apiary == address(0) ||
            _principle == address(0) ||
            _treasury == address(0) ||
            _twap == address(0)
        ) {
            revert APIARY__ZERO_ADDRESS();
        }

        APIARY = _apiary;
        principle = _principle;
        treasury = _treasury;
        twap = IApiaryUniswapV2TwapOracle(_twap);
        bondCalculator = _bondCalculator;
        isLiquidityBond = (_bondCalculator != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            BOND FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit principle tokens to purchase a bond
     * @dev Creates a new independent bond for the user. Users can have multiple bonds.
     *      Each bond vests linearly over the vesting term.
     * 
     * Flow:
     * 1. Calculate payout based on principle amount and TWAP price
     * 2. Apply discount rate to get discounted price
     * 3. Check slippage, debt limits, payout limits
     * 4. Transfer principle to this contract, then to treasury
     * 5. Treasury mints APIARY to this contract
     * 6. Create new bond record for user
     * 
     * @param amount Amount of principle token to bond
     * @param maxPriceInHoney Maximum acceptable price in HONEY (18 decimals)
     * @return payout Amount of APIARY to be vested
     */
    function deposit(
        uint256 amount,
        uint256 maxPriceInHoney
    ) external whenNotPaused nonReentrant returns (uint256 payout) {
        if (amount == 0) revert APIARY__INVALID_AMOUNT();
        if (maxPriceInHoney == 0) revert APIARY__INVALID_MAX_PRICE();

        // Calculate bond value and discounted price
        (uint256 payOut, uint256 discountedPriceInHoney) = valueOf(principle, amount);

        // Check debt limit
        if (totalDebt + payOut > terms.maxDebt) {
            revert APIARY__BOND_SOLD_OUT();
        }

        // Slippage protection
        if (discountedPriceInHoney > maxPriceInHoney) {
            revert APIARY__SLIPPAGE_LIMIT_EXCEEDED();
        }

        // Check payout bounds
        if (payOut < MINIMUM_PAYOUT) revert APIARY__BOND_TOO_SMALL();
        if (payOut > maxPayout()) revert APIARY__BOND_TOO_LARGE();

        // Transfer principle tokens from user to this contract
        IERC20(principle).safeTransferFrom(msg.sender, address(this), amount);

        // Approve and deposit to treasury
        // Treasury mints `payOut` APIARY to this contract (bond depository)
        IERC20(principle).approve(treasury, amount);
        IApiaryTreasury(treasury).deposit(amount, principle, payOut);

        // Update total debt
        totalDebt += payOut;
        payout = payOut;

        // Create new bond for user (push to array)
        uint256 bondIndex = userBonds[msg.sender].length;
        userBonds[msg.sender].push(Bond({
            payout: payout,
            pricePaid: discountedPriceInHoney,
            vestingStart: uint48(block.number),
            vestingEnd: uint48(block.number + terms.vestingTerm),
            redeemed: false
        }));

        emit BondCreated(
            msg.sender,
            bondIndex,
            amount,
            payout,
            block.number + terms.vestingTerm,
            discountedPriceInHoney
        );

        return payout;
    }

    /**
     * @notice Redeem vested APIARY from a specific bond
     * @dev Users can redeem proportionally based on time vested
     *      If fully vested, entire payout is transferred
     *      If partially vested, proportional amount is transferred
     * @param bondIndex Index of the bond in the user's bonds array
     * @return payout Amount of APIARY redeemed
     */
    function redeem(uint256 bondIndex) external whenNotPaused nonReentrant returns (uint256 payout) {
        if (bondIndex >= userBonds[msg.sender].length) revert APIARY__INVALID_BOND_INDEX();
        
        Bond storage bond = userBonds[msg.sender][bondIndex];

        if (bond.payout == 0) revert APIARY__NO_REDEEMABLE_BOND();
        if (bond.redeemed) revert APIARY__BOND_ALREADY_REDEEMED();

        uint256 percentVested = _percentVestedFor(bond);

        if (percentVested >= BPS) {
            // Fully vested - pay everything
            payout = bond.payout;
            bond.payout = 0;
            bond.redeemed = true;
            totalDebt -= payout;
            
            emit BondRedeemed(msg.sender, bondIndex, payout, 0);
        } else {
            // Partially vested - pay proportionally
            payout = bond.payout.mulDiv(percentVested, BPS);
            bond.payout -= payout;
            totalDebt -= payout;
            
            emit BondRedeemed(msg.sender, bondIndex, payout, bond.payout);
        }

        IERC20(APIARY).safeTransfer(msg.sender, payout);
    }

    /**
     * @notice Redeem all vested APIARY from all bonds
     * @dev Convenience function to redeem from all active bonds at once
     *      Iterates through all bonds and redeems vested amounts
     * @return totalPayout Total amount of APIARY redeemed across all bonds
     */
    function redeemAll() external whenNotPaused nonReentrant returns (uint256 totalPayout) {
        Bond[] storage bonds = userBonds[msg.sender];
        uint256 length = bonds.length;

        for (uint256 i = 0; i < length; i++) {
            if (bonds[i].payout > 0 && !bonds[i].redeemed) {
                uint256 percentVested = _percentVestedFor(bonds[i]);

                if (percentVested > 0) {
                    uint256 payout;

                    if (percentVested >= BPS) {
                        // Fully vested
                        payout = bonds[i].payout;
                        bonds[i].payout = 0;
                        bonds[i].redeemed = true;
                    } else {
                        // Partially vested
                        payout = bonds[i].payout.mulDiv(percentVested, BPS);
                        bonds[i].payout -= payout;
                    }

                    totalPayout += payout;
                    totalDebt -= payout;

                    emit BondRedeemed(msg.sender, i, payout, bonds[i].payout);
                }
            }
        }

        if (totalPayout == 0) revert APIARY__NOTHING_TO_REDEEM();
        IERC20(APIARY).safeTransfer(msg.sender, totalPayout);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize bond terms (one-time only)
     * @param _vestingTerm Vesting duration in blocks
     * @param _maxPayout Maximum payout as % of allocation
     * @param _discountRate Discount from market price (bps)
     * @param _maxDebt Maximum total debt
     */
    function initializeBondTerms(
        uint256 _vestingTerm,
        uint256 _maxPayout,
        uint256 _discountRate,
        uint256 _maxDebt
    ) external onlyOwner {
        if (terms.vestingTerm != 0) revert APIARY__ALREADY_INITIALIZED();
        if (_vestingTerm < MINIMUM_VESTING_TERM) revert APIARY__INVALID_VESTING_TERM();
        if (_maxPayout > 1000) revert APIARY__INVALID_MAX_PAYOUT(); // Max 1%
        if (_discountRate > BPS) revert APIARY__INVALID_DISCOUNT_RATE();

        terms = Terms({
            vestingTerm: _vestingTerm,
            maxPayout: _maxPayout,
            discountRate: _discountRate,
            maxDebt: _maxDebt
        });

        emit BondTermsInitialized(_vestingTerm, _maxPayout, _discountRate, _maxDebt);
    }

    /**
     * @notice Adjust bond terms
     * @param _parameter Parameter to adjust
     * @param _input New value
     */
    function setBondTerms(PARAMETER _parameter, uint256 _input) external onlyOwner {
        if (_parameter == PARAMETER.VESTING) {
            if (_input < MINIMUM_VESTING_TERM) revert APIARY__INVALID_VESTING_TERM();
            terms.vestingTerm = _input;
        } else if (_parameter == PARAMETER.PAYOUT) {
            if (_input > 1000) revert APIARY__INVALID_MAX_PAYOUT();
            terms.maxPayout = _input;
        } else if (_parameter == PARAMETER.DISCOUNT_RATE) {
            if (_input > BPS) revert APIARY__INVALID_DISCOUNT_RATE();
            terms.discountRate = _input;
        } else if (_parameter == PARAMETER.MAX_DEBT) {
            terms.maxDebt = _input;
        }

        emit BondTermsUpdated(_parameter, _input);
    }

    /**
     * @notice Update TWAP oracle
     * @param _twap New TWAP oracle address
     */
    function updateTwap(address _twap) external onlyOwner {
        if (_twap == address(0)) revert APIARY__ZERO_ADDRESS();
        twap = IApiaryUniswapV2TwapOracle(_twap);
        emit TwapUpdated(_twap);
    }

    /**
     * @notice Pause the contract (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency token recovery
     * @param _token Token to recover
     * @param _amount Amount to recover
     */
    function clawBackTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert APIARY__ZERO_ADDRESS();
        if (_amount == 0) revert APIARY__INVALID_AMOUNT();

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) revert APIARY__INVALID_AMOUNT();

        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit TokensClawedBack(_token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the number of bonds a user has
     * @param _user User address
     * @return Number of bonds (including redeemed ones)
     */
    function getUserBondCount(address _user) external view returns (uint256) {
        return userBonds[_user].length;
    }

    /**
     * @notice Get a specific bond for a user
     * @param _user User address
     * @param _index Bond index
     * @return Bond struct with bond details
     */
    function getUserBond(address _user, uint256 _index) external view returns (Bond memory) {
        return userBonds[_user][_index];
    }

    /**
     * @notice Get all active (non-redeemed, non-zero payout) bonds for a user
     * @param _user User address
     * @return activeBonds Array of active bond structs
     * @return indices Array of indices corresponding to the active bonds
     */
    function getActiveBonds(address _user) external view returns (Bond[] memory activeBonds, uint256[] memory indices) {
        Bond[] memory allBonds = userBonds[_user];
        uint256 activeCount = 0;

        // Count active bonds
        for (uint256 i = 0; i < allBonds.length; i++) {
            if (allBonds[i].payout > 0 && !allBonds[i].redeemed) {
                activeCount++;
            }
        }

        // Build arrays
        activeBonds = new Bond[](activeCount);
        indices = new uint256[](activeCount);
        uint256 j = 0;

        for (uint256 i = 0; i < allBonds.length; i++) {
            if (allBonds[i].payout > 0 && !allBonds[i].redeemed) {
                activeBonds[j] = allBonds[i];
                indices[j] = i;
                j++;
            }
        }
    }

    /**
     * @notice Calculate discounted bond price
     * @param price Current market price in HONEY
     * @return Discounted price after applying discount rate
     */
    function getBondPrice(uint256 price) public view returns (uint256) {
        return price.mulDiv(BPS - terms.discountRate, BPS);
    }

    /**
     * @notice Calculate value of principle tokens in APIARY terms
     * @param _token Token address (should match principle)
     * @param _amount Amount of tokens
     * @return value_ APIARY payout amount
     * @return discountedPriceInHoney Discounted price in HONEY (18 decimals)
     */
    function valueOf(
        address _token,
        uint256 _amount
    ) public returns (uint256 value_, uint256 discountedPriceInHoney) {
        // Get APIARY price from TWAP oracle (in HONEY, 18 decimals)
        uint256 apiaryPrice = twap.consult(1e9); // 1 APIARY in HONEY

        if (isLiquidityBond) {
            // For LP bonds, use bonding calculator
            value_ = IApiaryBondingCalculator(bondCalculator).valuation(_token, _amount);
        } else {
            // For iBGT bonds, convert to APIARY decimals
            // Assuming iBGT has 18 decimals and APIARY has 9 decimals
            value_ = _amount.mulDiv(
                10 ** IERC20Metadata(APIARY).decimals(),
                10 ** IERC20Metadata(_token).decimals()
            );
        }

        // Apply discount to get bond price
        discountedPriceInHoney = getBondPrice(apiaryPrice);

        // Calculate payout: value / discounted_price
        if (discountedPriceInHoney != 0) {
            value_ = value_.mulDiv(PRECISION, discountedPriceInHoney);
        }
    }

    /**
     * @notice Calculate percent vested for a specific bond
     * @param _user User address
     * @param _bondIndex Bond index
     * @return percentVested_ Percent vested (in basis points, 10000 = 100%)
     */
    function percentVestedFor(address _user, uint256 _bondIndex) public view returns (uint256 percentVested_) {
        if (_bondIndex >= userBonds[_user].length) return 0;
        return _percentVestedFor(userBonds[_user][_bondIndex]);
    }

    /**
     * @notice Internal function to calculate percent vested for a bond
     * @param bond Bond struct
     * @return percentVested_ Percent vested (in basis points)
     */
    function _percentVestedFor(Bond memory bond) internal view returns (uint256 percentVested_) {
        if (bond.payout == 0 || bond.redeemed) return 0;

        if (block.number >= bond.vestingEnd) {
            return BPS; // 100% vested
        }

        uint256 vestingDuration = bond.vestingEnd - bond.vestingStart;
        uint256 elapsed = block.number - bond.vestingStart;

        percentVested_ = elapsed.mulDiv(BPS, vestingDuration);
    }

    /**
     * @notice Calculate total pending payout across all bonds for a user
     * @param _user User address
     * @return totalPending_ Total amount of APIARY ready to claim
     */
    function pendingPayoutFor(address _user) external view returns (uint256 totalPending_) {
        Bond[] memory bonds = userBonds[_user];

        for (uint256 i = 0; i < bonds.length; i++) {
            if (bonds[i].payout > 0 && !bonds[i].redeemed) {
                uint256 percentVested = _percentVestedFor(bonds[i]);
                totalPending_ += bonds[i].payout.mulDiv(percentVested, BPS);
            }
        }
    }

    /**
     * @notice Calculate pending payout for a specific bond
     * @param _user User address
     * @param _bondIndex Bond index
     * @return pendingPayout_ Amount of APIARY ready to claim from this bond
     */
    function pendingPayoutForBond(address _user, uint256 _bondIndex) external view returns (uint256 pendingPayout_) {
        if (_bondIndex >= userBonds[_user].length) return 0;
        
        Bond memory bond = userBonds[_user][_bondIndex];
        if (bond.payout == 0 || bond.redeemed) return 0;

        uint256 percentVested = _percentVestedFor(bond);
        pendingPayout_ = bond.payout.mulDiv(percentVested, BPS);
    }

    /**
     * @notice Calculate maximum payout per bond
     * @return Maximum payout based on treasury allocation
     */
    function maxPayout() public view returns (uint256) {
        uint256 totalAllocatedToTreasury = IApiaryToken(APIARY).allocationLimits(treasury);
        return totalAllocatedToTreasury.mulDiv(terms.maxPayout, BPS);
    }

    /**
     * @notice Get current bond price in HONEY
     * @return Current discounted bond price
     */
    function bondPriceInHoney() external returns (uint256) {
        uint256 apiaryPrice = twap.consult(1e9);
        return getBondPrice(apiaryPrice);
    }

    /**
     * @notice Get debt ratio (current debt / max debt)
     * @return Debt ratio in basis points
     */
    function debtRatio() external view returns (uint256) {
        if (terms.maxDebt == 0) return 0;
        return totalDebt.mulDiv(BPS, terms.maxDebt);
    }

    /**
     * @notice Get remaining debt capacity
     * @return Remaining amount that can be issued before hitting maxDebt
     */
    function remainingDebtCapacity() external view returns (uint256) {
        if (totalDebt >= terms.maxDebt) return 0;
        return terms.maxDebt - totalDebt;
    }
}
