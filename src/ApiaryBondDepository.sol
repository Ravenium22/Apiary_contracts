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
import { IAggregatorV3 } from "./interfaces/IAggregatorV3.sol";

/**
 * @title ApiaryBondDepository
 * @notice Enables APIARY bond purchases using iBGT or APIARY/HONEY LP tokens
 * @dev Bonds are priced using TWAP oracle with a manual discount rate
 *      iBGT bonds use a Chainlink-compatible iBGT/USD oracle for correct valuation
 *      Vesting occurs linearly over 7 days (configurable)
 *      Users can have multiple independent bonds, each with its own vesting schedule
 *
 * Key Features:
 * - Primary principle: iBGT (Infrared BGT) — priced via iBGT/USD oracle
 * - Secondary principle: APIARY/HONEY LP from Kodiak
 * - TWAP-based APIARY pricing with discount
 * - Linear vesting over 7 days
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
     * @param vestingTerm Duration of vesting in blocks (7 days default)
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
     * @notice Individual bond information (packed: 2 storage slots)
     * @param payout APIARY remaining to be paid (uint128 max ≈ 3.4e29, safe for 9-decimal tokens)
     * @param pricePaid Price paid per APIARY in HONEY (uint128 max ≈ 3.4e29, safe for 18-decimal prices)
     * @param vestingStart Block when bond was created
     * @param vestingEnd Block when bond is fully vested
     * @param redeemed Whether the bond has been fully redeemed
     */
    struct Bond {
        uint128 payout;         // APIARY remaining to be paid (slot 1)
        uint128 pricePaid;      // Price paid per APIARY in HONEY (slot 1)
        uint48 vestingStart;    // Block when bond was created (slot 2)
        uint48 vestingEnd;      // Block when fully vested (slot 2)
        bool redeemed;          // Whether fully redeemed (slot 2)
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
    
    // C-02 Fix: Maximum bonds per user to prevent DoS in redeemAll()
    uint256 public constant MAX_BONDS_PER_USER = 50;
    
    // M-09 Fix: Maximum discount rate (50% = 5000 bps)
    uint256 public constant MAX_DISCOUNT_RATE = 5000;
    
    // Berachain average block time: ~5 seconds
    // 7 days = 7 * 24 * 60 * 60 / 5 = 120,960 blocks
    uint256 public constant DEFAULT_VESTING_TERM = 120_960;
    
    // Minimum vesting term: 1 day = 17,280 blocks
    uint256 public constant MINIMUM_VESTING_TERM = 17_280;

    /*//////////////////////////////////////////////////////////////
                    DYNAMIC DISCOUNT TIER CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Debt ratio tiers for dynamic discount (in basis points)
    /// @dev Tier boundaries: 0-3%, 3-6%, 6-10%, >10%
    uint256 public constant DEBT_TIER_1_MAX = 300;   // 3%
    uint256 public constant DEBT_TIER_2_MAX = 600;   // 6%
    uint256 public constant DEBT_TIER_3_MAX = 1000;  // 10%

    /// @notice Discount rates for each tier (in basis points)
    /// @dev Tier 1 (0-3%): 8%, Tier 2 (3-6%): 5%, Tier 3 (6-10%): 3%, Tier 4 (>10%): PAUSED
    uint256 public constant TIER_1_DISCOUNT = 800;   // 8%
    uint256 public constant TIER_2_DISCOUNT = 500;   // 5%
    uint256 public constant TIER_3_DISCOUNT = 300;   // 3%

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
    
    /// @notice L-03 Fix: Blocks per day for vesting calculations (adjustable if block time changes)
    uint256 public blocksPerDay;

    /// @notice M-NEW-02 Fix: Reference price for deviation check (last known good price)
    uint256 public referencePrice;
    
    /// @notice M-NEW-02 Fix: Maximum allowed price deviation in basis points (default 2000 = 20%)
    uint256 public maxPriceDeviation;
    
    /// @notice M-NEW-02 Fix: Timestamp of last reference price update
    uint256 public referencePriceLastUpdate;

    /// @notice M-05 Fix: Last block number when debt was decayed
    uint256 public lastDecayBlock;

    /// @notice Whether dynamic debt-ratio based discounts are enabled
    /// @dev When false, uses static discountRate from terms. When true, calculates discount dynamically.
    bool public dynamicDiscountsEnabled;

    /// @notice CRITICAL-01 Fix: Last TWAP price used during deposit, cached for view queries
    uint256 public lastCachedApiaryPrice;

    /// @notice Chainlink-compatible iBGT/USD price feed (required for iBGT bonds)
    IAggregatorV3 public ibgtPriceFeed;

    /// @notice Cached decimals from iBGT price feed (avoids repeated external calls)
    uint8 public ibgtPriceFeedDecimals;

    /// @notice Maximum staleness of price feed data before revert (default: 1 hour)
    uint256 public priceFeedStalenessThreshold;

    /// @notice Last iBGT oracle price, cached for quoteValue() view function
    uint256 public lastCachedIbgtPrice;

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
    error APIARY__MAX_BONDS_EXCEEDED();
    /// @notice M-NEW-02 Fix: Price deviation too high
    error APIARY__PRICE_DEVIATION_TOO_HIGH();
    /// @notice iBGT price feed returned stale data
    error APIARY__STALE_PRICE_FEED();
    /// @notice iBGT price feed returned zero or negative price
    error APIARY__INVALID_IBGT_PRICE();
    /// @notice M-NEW-02 Fix: Invalid price deviation parameter
    error APIARY__INVALID_PRICE_DEVIATION();
    /// @notice Bonds paused due to debt ratio exceeding 10%
    error APIARY__BONDS_PAUSED_HIGH_DEBT();

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
    /// @notice L-03 Fix: Emitted when blocksPerDay is updated
    event BlocksPerDayUpdated(uint256 oldValue, uint256 newValue);
    /// @notice M-NEW-02 Fix: Emitted when reference price is updated
    event ReferencePriceUpdated(uint256 oldPrice, uint256 newPrice);
    /// @notice M-NEW-02 Fix: Emitted when max price deviation is updated
    event MaxPriceDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    /// @notice Emitted when dynamic discounts are toggled
    event DynamicDiscountsToggled(bool enabled);
    /// @notice Emitted when iBGT price feed is updated
    event IbgtPriceFeedUpdated(address indexed priceFeed);
    /// @notice Emitted when price feed staleness threshold is updated
    event PriceFeedStalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

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
     * @param _ibgtPriceFeed Chainlink iBGT/USD price feed (required for iBGT bonds, address(0) for LP bonds)
     */
    constructor(
        address _apiary,
        address _principle,
        address _treasury,
        address admin,
        address _bondCalculator,
        address _twap,
        address _ibgtPriceFeed
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

        // For iBGT bonds (non-LP), price feed is mandatory
        if (!isLiquidityBond) {
            if (_ibgtPriceFeed == address(0)) revert APIARY__ZERO_ADDRESS();
            ibgtPriceFeed = IAggregatorV3(_ibgtPriceFeed);
            ibgtPriceFeedDecimals = ibgtPriceFeed.decimals();
        } else if (_ibgtPriceFeed != address(0)) {
            // LP bonds can optionally have a price feed (ignored in pricing)
            ibgtPriceFeed = IAggregatorV3(_ibgtPriceFeed);
            ibgtPriceFeedDecimals = ibgtPriceFeed.decimals();
        }

        // Default staleness threshold: 1 hour
        priceFeedStalenessThreshold = 3600;

        // L-03 Fix: Initialize blocksPerDay (86400 seconds / 5 seconds per block = 17280)
        blocksPerDay = 17_280;

        // M-NEW-02 Fix: Initialize price deviation protection (20% max deviation)
        maxPriceDeviation = 2000; // 20% in basis points
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

        // M-05 Fix: Decay outstanding debt before processing new bond
        _decayDebt();

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
        // L-05 Fix: Descriptive revert when treasury allocation is exhausted
        uint256 _maxPayout = maxPayout();
        if (_maxPayout == 0) revert APIARY__BOND_SOLD_OUT();
        if (payOut > _maxPayout) revert APIARY__BOND_TOO_LARGE();

        // Transfer principle tokens from user to this contract
        IERC20(principle).safeTransferFrom(msg.sender, address(this), amount);

        // Approve and deposit to treasury
        // Treasury mints `payOut` APIARY to this contract (bond depository)
        // C-06 Fix: Use forceApprove for tokens that require zero allowance first
        IERC20(principle).forceApprove(treasury, amount);
        IApiaryTreasury(treasury).deposit(amount, principle, payOut);

        // Update total debt
        totalDebt += payOut;
        payout = payOut;

        // C-02 Fix: Check user hasn't exceeded max bonds before creating new one
        Bond[] storage bonds = userBonds[msg.sender];
        if (bonds.length >= MAX_BONDS_PER_USER) {
            revert APIARY__MAX_BONDS_EXCEEDED();
        }

        // Create new bond for user (push to array)
        uint256 bondIndex = bonds.length;
        bonds.push(Bond({
            payout: uint128(payout),
            pricePaid: uint128(discountedPriceInHoney),
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

            emit BondRedeemed(msg.sender, bondIndex, payout, 0);
        } else {
            // Partially vested - pay proportionally
            payout = uint256(bond.payout).mulDiv(percentVested, BPS);
            bond.payout -= uint128(payout);

            emit BondRedeemed(msg.sender, bondIndex, payout, bond.payout);
        }
        // MEDIUM-05 Fix: totalDebt reduction removed from redeem() to prevent
        // double-counting with _decayDebt(). Debt is now solely managed by linear decay.

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

        for (uint256 i = 0; i < length;) {
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
                        payout = uint256(bonds[i].payout).mulDiv(percentVested, BPS);
                        bonds[i].payout -= uint128(payout);
                    }

                    totalPayout += payout;
                    // MEDIUM-05 Fix: totalDebt reduction removed - handled by _decayDebt()

                    emit BondRedeemed(msg.sender, i, payout, bonds[i].payout);
                }
            }
            unchecked { ++i; }
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
        // M-09 Fix: Limit discount rate to 50% max
        if (_discountRate > MAX_DISCOUNT_RATE) revert APIARY__INVALID_DISCOUNT_RATE();

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
            // M-09 Fix: Limit discount rate to 50% max
            if (_input > MAX_DISCOUNT_RATE) revert APIARY__INVALID_DISCOUNT_RATE();
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
     * @notice Update iBGT/USD price feed
     * @param _priceFeed New Chainlink-compatible price feed address
     */
    function setIbgtPriceFeed(address _priceFeed) external onlyOwner {
        if (_priceFeed == address(0)) revert APIARY__ZERO_ADDRESS();
        ibgtPriceFeed = IAggregatorV3(_priceFeed);
        ibgtPriceFeedDecimals = ibgtPriceFeed.decimals();
        emit IbgtPriceFeedUpdated(_priceFeed);
    }

    /**
     * @notice Update staleness threshold for iBGT price feed
     * @param _threshold Maximum age in seconds (e.g. 3600 = 1 hour)
     */
    function setPriceFeedStalenessThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold == 0) revert APIARY__INVALID_AMOUNT();
        uint256 oldThreshold = priceFeedStalenessThreshold;
        priceFeedStalenessThreshold = _threshold;
        emit PriceFeedStalenessThresholdUpdated(oldThreshold, _threshold);
    }

    /**
     * @notice L-03 Fix: Update blocks per day for vesting calculations
     * @dev Adjust if Berachain block time changes from ~5 seconds
     * @param _blocksPerDay New blocks per day value
     */
    function setBlocksPerDay(uint256 _blocksPerDay) external onlyOwner {
        if (_blocksPerDay == 0) revert APIARY__INVALID_AMOUNT();
        uint256 oldValue = blocksPerDay;
        blocksPerDay = _blocksPerDay;
        emit BlocksPerDayUpdated(oldValue, _blocksPerDay);
    }

    /**
     * @notice L-03 Fix: Calculate vesting term in blocks based on days
     * @param _days Number of days for vesting
     * @return blocks Number of blocks for the vesting period
     */
    function calculateVestingBlocks(uint256 _days) external view returns (uint256 blocks) {
        return _days * blocksPerDay;
    }

    /**
     * @notice M-NEW-02 Fix: Set reference price for deviation checks
     * @dev Should be called after deployment and periodically updated
     * @param _referencePrice Reference price in HONEY (18 decimals)
     */
    function setReferencePrice(uint256 _referencePrice) external onlyOwner {
        if (_referencePrice == 0) revert APIARY__INVALID_AMOUNT();
        uint256 oldPrice = referencePrice;
        referencePrice = _referencePrice;
        referencePriceLastUpdate = block.timestamp;
        emit ReferencePriceUpdated(oldPrice, _referencePrice);
    }

    /**
     * @notice M-NEW-02 Fix: Update reference price from current TWAP
     * @dev Convenience function to sync reference price with current market
     */
    function syncReferencePrice() external onlyOwner {
        uint256 currentPrice = twap.consult(1e9);
        if (currentPrice == 0) revert APIARY__INVALID_AMOUNT();
        uint256 oldPrice = referencePrice;
        referencePrice = currentPrice;
        referencePriceLastUpdate = block.timestamp;
        emit ReferencePriceUpdated(oldPrice, currentPrice);
    }

    /**
     * @notice M-NEW-02 Fix: Set maximum allowed price deviation
     * @param _maxDeviation Maximum deviation in basis points (e.g., 2000 = 20%)
     */
    function setMaxPriceDeviation(uint256 _maxDeviation) external onlyOwner {
        // Cap at 50% max deviation, minimum 1%
        if (_maxDeviation > 5000 || _maxDeviation < 100) revert APIARY__INVALID_PRICE_DEVIATION();
        uint256 oldDeviation = maxPriceDeviation;
        maxPriceDeviation = _maxDeviation;
        emit MaxPriceDeviationUpdated(oldDeviation, _maxDeviation);
    }

    /**
     * @notice M-NEW-02 Fix: Disable price deviation check (emergency use)
     * @dev Sets maxPriceDeviation to 0, disabling the check
     */
    function disablePriceDeviationCheck() external onlyOwner {
        uint256 oldDeviation = maxPriceDeviation;
        maxPriceDeviation = 0;
        emit MaxPriceDeviationUpdated(oldDeviation, 0);
    }

    /**
     * @notice Enable or disable dynamic debt-ratio based discounts
     * @dev When enabled, discount rates are determined by debt ratio tiers:
     *      - 0-3% debt: 8% discount
     *      - 3-6% debt: 5% discount
     *      - 6-10% debt: 3% discount
     *      - >10% debt: bonds paused
     *      When disabled, uses the static discountRate from terms.
     * @param _enabled True to enable dynamic discounts, false to use static
     */
    function setDynamicDiscounts(bool _enabled) external onlyOwner {
        dynamicDiscountsEnabled = _enabled;
        emit DynamicDiscountsToggled(_enabled);
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

        // C-02 Fix: Protect APIARY reserved for bond holder redemptions
        if (_token == APIARY) {
            uint256 excess = balance > totalDebt ? balance - totalDebt : 0;
            if (_amount > excess) revert APIARY__INVALID_AMOUNT();
        }

        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit TokensClawedBack(_token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEBT DECAY (M-05 Fix)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice M-05 Fix: Decay totalDebt based on elapsed vesting time
     * @dev Prevents ghost debt from unredeemed bonds inflating debt ratio
     *      Called at the start of deposit() to ensure accurate debt tracking
     */
    function _decayDebt() internal {
        if (lastDecayBlock == 0) {
            lastDecayBlock = block.number;
            return;
        }
        uint256 elapsed = block.number - lastDecayBlock;
        if (elapsed > 0 && totalDebt > 0 && terms.vestingTerm > 0) {
            // MEDIUM-02 Fix: Cap elapsed at vestingTerm to prevent over-decay
            if (elapsed > terms.vestingTerm) {
                elapsed = terms.vestingTerm;
            }
            uint256 decay = (totalDebt * elapsed) / terms.vestingTerm;
            totalDebt = totalDebt > decay ? totalDebt - decay : 0;
            lastDecayBlock = block.number;
        }
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
        for (uint256 i = 0; i < allBonds.length;) {
            if (allBonds[i].payout > 0 && !allBonds[i].redeemed) {
                activeCount++;
            }
            unchecked { ++i; }
        }

        // Build arrays
        activeBonds = new Bond[](activeCount);
        indices = new uint256[](activeCount);
        uint256 j = 0;

        for (uint256 i = 0; i < allBonds.length;) {
            if (allBonds[i].payout > 0 && !allBonds[i].redeemed) {
                activeBonds[j] = allBonds[i];
                indices[j] = i;
                j++;
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Calculate discounted bond price
     * @dev If dynamicDiscountsEnabled, uses debt-ratio based tiered discounts:
     *      - 0-3% debt ratio: 8% discount
     *      - 3-6% debt ratio: 5% discount
     *      - 6-10% debt ratio: 3% discount
     *      - >10% debt ratio: bonds paused (reverts)
     * @param price Current market price in HONEY
     * @return Discounted price after applying discount rate
     */
    function getBondPrice(uint256 price) public view returns (uint256) {
        uint256 discountRate;

        if (dynamicDiscountsEnabled) {
            discountRate = _getDynamicDiscountRate();
        } else {
            discountRate = terms.discountRate;
        }

        return price.mulDiv(BPS - discountRate, BPS);
    }

    /**
     * @notice Get dynamic discount rate based on current debt ratio
     * @dev Tiered system:
     *      - Debt ratio 0-3%: 8% discount
     *      - Debt ratio 3-6%: 5% discount
     *      - Debt ratio 6-10%: 3% discount
     *      - Debt ratio >10%: Bonds paused (reverts)
     * @return discountRate The discount rate in basis points
     */
    function _getDynamicDiscountRate() internal view returns (uint256 discountRate) {
        uint256 currentDebtRatio = _calculateDebtRatio();

        if (currentDebtRatio <= DEBT_TIER_1_MAX) {
            // 0-3% debt ratio: 8% discount (most attractive)
            return TIER_1_DISCOUNT;
        } else if (currentDebtRatio <= DEBT_TIER_2_MAX) {
            // 3-6% debt ratio: 5% discount
            return TIER_2_DISCOUNT;
        } else if (currentDebtRatio <= DEBT_TIER_3_MAX) {
            // 6-10% debt ratio: 3% discount
            return TIER_3_DISCOUNT;
        } else {
            // >10% debt ratio: bonds paused
            revert APIARY__BONDS_PAUSED_HIGH_DEBT();
        }
    }

    /**
     * @notice Calculate current debt ratio
     * @dev Debt ratio = (totalDebt / treasuryReserves) * BPS
     *      Uses treasury's total reserves for iBGT as denominator
     * @return ratio Debt ratio in basis points
     */
    function _calculateDebtRatio() internal view returns (uint256 ratio) {
        // Get treasury's total iBGT reserves
        uint256 treasuryReserves = IApiaryTreasury(treasury).totalReserves(principle);

        if (treasuryReserves == 0) {
            // No reserves = infinite debt ratio = paused
            return type(uint256).max;
        }

        // Calculate ratio: (totalDebt / treasuryReserves) * BPS
        ratio = totalDebt.mulDiv(BPS, treasuryReserves);
    }

    /**
     * @notice Get current discount rate (static or dynamic based on settings)
     * @return rate Current effective discount rate in basis points
     */
    function getCurrentDiscountRate() external view returns (uint256 rate) {
        if (dynamicDiscountsEnabled) {
            // This may revert if debt ratio > 10%
            return _getDynamicDiscountRate();
        }
        return terms.discountRate;
    }

    /**
     * @notice Check if bonds are available (not paused due to high debt)
     * @return available True if bonds can be purchased
     * @return currentDebtRatio Current debt ratio in basis points
     * @return currentDiscount Current discount rate in basis points
     */
    function getBondAvailability() external view returns (
        bool available,
        uint256 currentDebtRatio,
        uint256 currentDiscount
    ) {
        currentDebtRatio = _calculateDebtRatio();

        if (!dynamicDiscountsEnabled) {
            return (true, currentDebtRatio, terms.discountRate);
        }

        if (currentDebtRatio > DEBT_TIER_3_MAX) {
            return (false, currentDebtRatio, 0);
        }

        if (currentDebtRatio <= DEBT_TIER_1_MAX) {
            currentDiscount = TIER_1_DISCOUNT;
        } else if (currentDebtRatio <= DEBT_TIER_2_MAX) {
            currentDiscount = TIER_2_DISCOUNT;
        } else {
            currentDiscount = TIER_3_DISCOUNT;
        }

        return (true, currentDebtRatio, currentDiscount);
    }

    /**
     * @notice Calculate value of principle tokens in APIARY terms
     * @dev CRITICAL-01 Fix: Changed from public to internal to prevent unguarded oracle state changes.
     *      External callers should use quoteValue() view function instead.
     * @param _token Token address (should match principle)
     * @param _amount Amount of tokens
     * @return value_ APIARY payout amount
     * @return discountedPriceInHoney Discounted price in HONEY (18 decimals)
     */
    function valueOf(
        address _token,
        uint256 _amount
    ) internal returns (uint256 value_, uint256 discountedPriceInHoney) {
        // Get APIARY price from TWAP oracle (in HONEY, 18 decimals)
        uint256 apiaryPrice = twap.consult(1e9); // 1 APIARY in HONEY

        // CRITICAL-01 Fix: Cache price for view queries (quoteValue)
        lastCachedApiaryPrice = apiaryPrice;

        // M-NEW-02 Fix: Check price deviation from reference if reference is set
        if (referencePrice > 0 && maxPriceDeviation > 0) {
            uint256 deviation;
            if (apiaryPrice > referencePrice) {
                deviation = ((apiaryPrice - referencePrice) * BPS) / referencePrice;
            } else {
                deviation = ((referencePrice - apiaryPrice) * BPS) / referencePrice;
            }
            if (deviation > maxPriceDeviation) {
                revert APIARY__PRICE_DEVIATION_TOO_HIGH();
            }
        }

        if (isLiquidityBond) {
            // For LP bonds, use bonding calculator (returns HONEY-equivalent value in 9-dec)
            value_ = IApiaryBondingCalculator(bondCalculator).valuation(_token, _amount);
        } else {
            // For iBGT bonds: price using iBGT/USD oracle (HONEY = $1 USD)
            (, int256 answer,, uint256 updatedAt,) = ibgtPriceFeed.latestRoundData();
            if (answer <= 0) revert APIARY__INVALID_IBGT_PRICE();
            if (block.timestamp - updatedAt > priceFeedStalenessThreshold) revert APIARY__STALE_PRICE_FEED();

            uint256 ibgtPrice = uint256(answer);
            lastCachedIbgtPrice = ibgtPrice;

            // Unit math (example: 10 iBGT at $3, 8-dec feed, APIARY 9-dec, iBGT 18-dec):
            //   Step 1: 10e18 * 3e8 / 1e8 = 30e18  (USD value in 18-dec)
            //   Step 2: 30e18 * 1e9 / 1e18 = 30e9   (USD value in 9-dec)
            // Generalizes to any feed/token decimals. Result: HONEY-equivalent value in 9-dec.
            value_ = _amount
                .mulDiv(ibgtPrice, 10 ** ibgtPriceFeedDecimals)
                .mulDiv(10 ** IERC20Metadata(APIARY).decimals(), 10 ** IERC20Metadata(_token).decimals());
        }

        // Apply discount to get bond price: HONEY per APIARY after discount (18-dec)
        discountedPriceInHoney = getBondPrice(apiaryPrice);

        // Convert HONEY-equivalent value (9-dec) to APIARY payout (9-dec):
        //   payout = value_[9-dec] * 1e18 / discountedPrice[18-dec]
        //   Example: 30e9 * 1e18 / 0.225e18 = 133.33e9 APIARY
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

        for (uint256 i = 0; i < bonds.length;) {
            if (bonds[i].payout > 0 && !bonds[i].redeemed) {
                uint256 percentVested = _percentVestedFor(bonds[i]);
                totalPending_ += uint256(bonds[i].payout).mulDiv(percentVested, BPS);
            }
            unchecked { ++i; }
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
        pendingPayout_ = uint256(bond.payout).mulDiv(percentVested, BPS);
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
     * @notice Get current bond price in HONEY (updates oracle state)
     * @dev MEDIUM-03 Fix: Restricted to onlyOwner since it modifies oracle state.
     *      For read-only price queries, use bondPriceInHoneyView() instead.
     * @return Current discounted bond price
     */
    function bondPriceInHoney() external onlyOwner returns (uint256) {
        uint256 apiaryPrice = twap.consult(1e9);
        return getBondPrice(apiaryPrice);
    }

    /**
     * @notice CRITICAL-01 Fix: Read-only estimate of bond value for UI display
     * @dev Uses the last cached TWAP price from the most recent deposit() call.
     *      This is an approximation — actual deposit price may differ slightly.
     * @param _token Token address (should match principle)
     * @param _amount Amount of tokens
     * @return estimatedPayout Estimated APIARY payout amount
     * @return estimatedPrice Estimated discounted price in HONEY
     */
    function quoteValue(
        address _token,
        uint256 _amount
    ) external view returns (uint256 estimatedPayout, uint256 estimatedPrice) {
        // Use last cached price from most recent deposit (no state change)
        uint256 cachedPrice = lastCachedApiaryPrice;
        if (cachedPrice == 0) return (0, 0);

        if (isLiquidityBond) {
            estimatedPayout = IApiaryBondingCalculator(bondCalculator).valuation(_token, _amount);
        } else {
            // Use cached iBGT price from last deposit for gas-free UI quotes
            uint256 cachedIbgtPrice = lastCachedIbgtPrice;
            if (cachedIbgtPrice == 0) return (0, 0);

            // Same unit math as valueOf(): HONEY-equivalent value in 9-dec
            estimatedPayout = _amount
                .mulDiv(cachedIbgtPrice, 10 ** ibgtPriceFeedDecimals)
                .mulDiv(10 ** IERC20Metadata(APIARY).decimals(), 10 ** IERC20Metadata(_token).decimals());
        }

        // Convert HONEY-equivalent value (9-dec) to APIARY payout (9-dec)
        estimatedPrice = getBondPrice(cachedPrice);

        if (estimatedPrice != 0) {
            estimatedPayout = estimatedPayout.mulDiv(PRECISION, estimatedPrice);
        }
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
