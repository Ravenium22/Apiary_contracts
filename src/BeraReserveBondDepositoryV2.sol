// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IBeraReserveTreasuryV2 } from "./interfaces/IBeraReserveTreasuryV2.sol";
import { IBeraReserveToken } from "./interfaces/IBeraReserveToken.sol";
import { IBeraReserveBondingCalculator } from "./interfaces/IBeraReserveBondingCalculator.sol";
import { IBeraReserveUniswapV2TwapOracle } from "./interfaces/IBeraReserveUniswapV2TwapOracle.sol";
/**
 * @title BeraReserveBondDepositoryV2
 * @author 0xm00k
 * @notice Enables BRR bond purchases using USDC or BRR/Honey LP tokens,
 *  priced from the TWAP UNISWAP V2 Oracle with a manual discount. BRR tokens are vested over 5 days.
 *  Forked from Olympus DAO with simplified pricing.
 */

contract BeraReserveBondDepositoryV2 is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Terms {
        uint256 vestingTerm; // in blocks
        uint256 maxPayout; // in thousandths of a %. i.e. 500 = 0.5% //not more than 1%
        uint256 fee; // as % of bond payout, in hundredths. ( 500 = 5% = 0.05 for every 1 paid)
        uint256 discountRate; // in basis points (100 = 1%)
        uint256 maxDebt;
    }

    struct Bond {
        uint256 amountBonded;
        uint256 payout; // BRR remaining to be paid
        uint256 vesting; // Blocks left to vest
        uint256 lastBlock; // Last interaction
        uint256 pricePaid; // In HONEY 1e18, for front end viewing
    }

    enum PARAMETER {
        VESTING,
        PAYOUT,
        FEE,
        DISCOUNT_RATE,
        MAX_DEBT
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant BPS = 10_000; // Basis points (10_000 = 100%)
    uint256 public constant MINIMUM_PAYOUT = 10_000_000;
    uint256 private constant PRECISION = 1e18;

    address public immutable principle; // USDC/LP token
    bool public immutable isLiquidityBond;
    address public immutable bondCalculator; // address of the bonding calculator
    address public immutable treasury; // Treasury address
    address public immutable BRR; // BRR token address

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => Bond) public bondInfo; // stores bond information for depositors
    Terms public terms; // stores terms for new bonds
    address public dao; // receives profit share from bond
    uint256 public totalDebt; // total amount of bonds issued
    IBeraReserveUniswapV2TwapOracle public twap;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error InvalidAmount();
    error InvalidDiscountRate();
    error AlreadyInitialized();
    error InvalidVestingTerm();
    error InvalidMaxPayout();
    error InvalidFee();
    error InvalidMaxPrice();
    error SlippageLimitExceeded();
    error BondTooSmall();
    error BondTooLarge();
    error BondSoldOut();
    error NO_REDEEMABLE_BOND();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DaoUpdated(address indexed dao);
    event TwapUpdated(address indexed _twap);
    event BondTermsUpdated(PARAMETER indexed parameter, uint256 indexed input);
    event TokensClawedBack(address indexed token, uint256 indexed amount);
    event BondTermsInitialized(
        uint256 indexed vestingTerm,
        uint256 indexed maxPayout,
        uint256 indexed fee,
        uint256 discountRate,
        uint256 maxDebt
    );
    event BondCreated(uint256 indexed deposit, uint256 indexed payout, uint256 indexed expires, uint256 pricePaid);
    event BondRedeemed(address indexed recipient, uint256 indexed payout, uint256 indexed remaining);

    constructor(
        address _brr,
        address _principle,
        address _treasury,
        address _DAO,
        address admin,
        address _bondCalculator,
        address _twap
    ) Ownable(admin) {
        if (_brr == address(0) || _principle == address(0) || _treasury == address(0) || _DAO == address(0) || _twap == address(0)) {
            revert ZeroAddress();
        }
        BRR = _brr;
        principle = _principle;
        treasury = _treasury;
        dao = _DAO;

        twap = IBeraReserveUniswapV2TwapOracle(_twap);

        bondCalculator = _bondCalculator;
        isLiquidityBond = (_bondCalculator != address(0));
    }

    /**
     * @notice Deposits an amount of `principle` token into the bond contract and issues a bond for the sender.
     * The bond will be subject to a vesting period and a fee is deducted before the payout.
     *
     * @dev This function performs several checks including slippage, max debt limit, and minimum payout constraints.
     * The bond information is stored for the sender and the treasury receives the deposit.
     *
     * Emits a {BondCreated} event on successful bond creation.
     *
     * @param amount The amount of `principle` token to deposit (in the smallest unit).
     * @param maxPriceInHoney The maximum price the user is willing to pay for the bond (Price in Honey 18 decimals)
     *
     * @return payoutAfterFee The amount of payout after the fee deduction (in BRR).
     *
     * @custom:error InvalidAmount If the `amount` is zero.
     * @custom:error InvalidMaxPrice If the `maxPrice` is zero.
     * @custom:error BondSoldOut If the bond's total debt exceeds the maximum allowed debt.
     * @custom:error SlippageLimitExceeded If the discounted price exceeds the `maxPrice` limit.
     * @custom:error BondTooSmall If the payout is smaller than the minimum allowed payout.
     * @custom:error BondTooLarge If the payout exceeds the maximum allowed payout.
     */
    function deposit(uint256 amount, uint256 maxPriceInHoney) external whenNotPaused returns (uint256 payoutAfterFee) {
        if (amount == 0) revert InvalidAmount();
        if (maxPriceInHoney == 0) revert InvalidMaxPrice();

        (uint256 payOut, uint256 discountedPriceInHoney) = valueOf(principle, amount);

        if (totalDebt + payOut > terms.maxDebt) revert BondSoldOut();

        if (discountedPriceInHoney > maxPriceInHoney) revert SlippageLimitExceeded();

        if (payOut < MINIMUM_PAYOUT) revert BondTooSmall(); // must be > 0.01 BRR ( underflow protection )
        if (payOut > maxPayout()) revert BondTooLarge();

        IERC20(principle).safeTransferFrom(msg.sender, address(this), amount);

        //get Fee
        uint256 fee = payOut.mulDiv(terms.fee, BPS);

        payoutAfterFee = payOut - fee;

        IERC20(principle).approve(address(treasury), amount);

        IBeraReserveTreasuryV2(treasury).deposit(amount, principle, payOut);

        if (fee != 0) {
            // Transfer fee to DAO
            IERC20(BRR).safeTransfer(dao, fee);
        }

        totalDebt += payOut;

        // depositor info is stored
        bondInfo[msg.sender] = Bond({
            amountBonded: bondInfo[msg.sender].amountBonded + amount,
            payout: bondInfo[msg.sender].payout + payoutAfterFee,
            vesting: terms.vestingTerm,
            lastBlock: block.number,
            pricePaid: discountedPriceInHoney
        });

        emit BondCreated(amount, payoutAfterFee, block.number + terms.vestingTerm, discountedPriceInHoney);

        return payoutAfterFee;
    }

    /**
     * @notice Redeems the bond for the sender. If the bond is fully vested, the full payout is transferred to the user.
     * If the bond is not fully vested, a partial payout is made, and the bond's vesting period is updated accordingly.
     *
     * @dev This function checks the vesting status of the bond. If fully vested, the bond is redeemed in full, and
     * the bond information is deleted. If not fully vested, the function calculates the partial payout based on the
     * vesting percentage and updates the bond information for the sender.
     *
     * Emits a {BondRedeemed} event upon successful redemption.
     */
    function redeem() external whenNotPaused {
        Bond memory bond = bondInfo[msg.sender];

        if (bond.vesting == 0) revert NO_REDEEMABLE_BOND();

        uint256 percentVested = percentVestedFor(msg.sender);

        if (percentVested >= BPS) {
            // if fully vested
            delete bondInfo[msg.sender]; // delete user info
            emit BondRedeemed(msg.sender, bond.payout, 0); // emit bond data
            IERC20(BRR).safeTransfer(msg.sender, bond.payout); // pay user everything due
        } else {
            // if unfinished
            // calculate payout vested
            uint256 payout = bond.payout.mulDiv(percentVested, BPS);

            // store updated deposit info
            bondInfo[msg.sender].payout = bond.payout - payout;
            bondInfo[msg.sender].vesting = bond.vesting - (block.number - bond.lastBlock);
            bondInfo[msg.sender].lastBlock = block.number;

            emit BondRedeemed(msg.sender, payout, bondInfo[msg.sender].payout);
            IERC20(BRR).safeTransfer(msg.sender, payout); // pay user everything due
        }
    }

    /**
     * ADMIN FUNCTIONS
     */
    function initializeBondTerms(
        uint256 _vestingTerm,
        uint256 _maxPayout,
        uint256 _fee,
        uint256 _discountRate,
        uint256 _maxDebt
    ) external onlyOwner {
        if (terms.vestingTerm != 0) revert AlreadyInitialized();
        terms = Terms({ vestingTerm: _vestingTerm, maxPayout: _maxPayout, fee: _fee, discountRate: _discountRate, maxDebt: _maxDebt });

        emit BondTermsInitialized(_vestingTerm, _maxPayout, _fee, _discountRate, _maxDebt);
    }

    function setBondTerms(PARAMETER _parameter, uint256 _input) external onlyOwner {
        if (_parameter == PARAMETER.VESTING) {
            // 0 (can not more less than 36 hours)
            if (_input < 64_800) revert InvalidVestingTerm();
            terms.vestingTerm = _input;
        } else if (_parameter == PARAMETER.PAYOUT) {
            // 1 (can not be more than 1%)
            if (_input > 100) revert InvalidMaxPayout();
            terms.maxPayout = _input;
        } else if (_parameter == PARAMETER.FEE) {
            // 2
            if (_input > 10_000) revert InvalidFee();
            terms.fee = _input;
        } else if (_parameter == PARAMETER.DISCOUNT_RATE) {
            // 3
            if (_input > 10_000) revert InvalidDiscountRate();
            terms.discountRate = _input;
        } else if (_parameter == PARAMETER.MAX_DEBT) {
            // 4
            terms.maxDebt = _input;
        }

        emit BondTermsUpdated(_parameter, _input);
    }

    function setDAO(address _dao) external onlyOwner {
        if (_dao == address(0)) revert ZeroAddress();
        dao = _dao;

        emit DaoUpdated(dao);
    }

    function updateTwap(address _twap) external onlyOwner {
        if (_twap == address(0)) revert ZeroAddress();

        twap = IBeraReserveUniswapV2TwapOracle(_twap);

        emit TwapUpdated(_twap);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function clawBackTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        if (_amount == 0) revert InvalidAmount();

        uint256 balance = IERC20(_token).balanceOf(address(this));

        if (balance < _amount) revert InvalidAmount();

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit TokensClawedBack(_token, _amount);
    }

    /**
     * HELPER FUNCTIONS
     */
    function getBondInfo(address _depositor) external view returns (Bond memory) {
        return bondInfo[_depositor];
    }

    /**
     * @param price is the current BRR price in BRR/HONEY pair
     * @return returns discounted price
     */
    function getBondPrice(uint256 price) public view returns (uint256) {
        return price.mulDiv(BPS - terms.discountRate, BPS);
    }

    /**
     * @notice Returns the value of a given `_amount` of `_token` in BRR terms, adjusted by the current bond price.
     * @param _token The address of the token to value.
     * @param _amount The amount of the token to value.
     * @return value_ The BRR-denominated value of the input token amount.
     */
    function valueOf(address _token, uint256 _amount) public returns (uint256 value_, uint256 discountedPriceInHoney) {
        //return price in-terms of honey (18 decimals)
        uint256 brrPrice = twap.consult(1e9);

        if (isLiquidityBond) {
            value_ = IBeraReserveBondingCalculator(bondCalculator).valuation(_token, _amount);
        } else {
            // convert amount to match BRR decimals
            value_ = _amount.mulDiv(10 ** IERC20Metadata(BRR).decimals(), 10 ** IERC20Metadata(_token).decimals());
        }

        discountedPriceInHoney = getBondPrice(brrPrice); //price in 18 decimals

        if (discountedPriceInHoney != 0) {
            value_ = value_.mulDiv(PRECISION, discountedPriceInHoney);
        }
    }

    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint
     */
    function percentVestedFor(address _depositor) public view returns (uint256 percentVested_) {
        Bond memory bond = bondInfo[_depositor];

        uint256 blocksSinceLast = block.number - bond.lastBlock;
        uint256 vesting = bond.vesting;

        if (vesting > 0) {
            percentVested_ = blocksSinceLast.mulDiv(BPS, vesting);
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of BRR available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor(address _depositor) external view returns (uint256 pendingPayout_) {
        uint256 percentVested = percentVestedFor(_depositor);
        uint256 payout = bondInfo[_depositor].payout;

        if (percentVested >= 10_000) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mulDiv(percentVested, 10_000);
        }
    }

    function maxPayout() public view returns (uint256) {
        uint256 totalAllocatedToTreasury = IBeraReserveToken(BRR).allocationLimits(treasury);

        return totalAllocatedToTreasury.mulDiv(terms.maxPayout, BPS);
    }
}
