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
     * @param maxPayout Maximum single bond in bps of estimated treasury value (100 = 1%)
     * @param discountRate Discount from market price (in basis points)
     * @param maxDebt Maximum total debt allowed
     */
    struct Terms {
        uint256 vestingTerm;   // in blocks
        uint256 maxPayout;     // max single bond in bps of treasury value (100 = 1%)
        uint256 discountRate;  // in basis points (100 = 1%)
        uint256 maxDebt;       // maximum total debt allowed
    }

    /**
     * @notice Individual bond information (packed: 2 storage slots)
     * @param payout Total APIARY to be paid over full vesting (immutable after creation)
     * @param pricePaid Price paid per APIARY in HONEY (uint128 max ≈ 3.4e29, safe for 18-decimal prices)
     * @param claimed Total APIARY already claimed from this bond
     * @param vestingStart Block when bond was created
     * @param vestingEnd Block when bond is fully vested
     */
    struct Bond {
        uint128 payout;         // Total APIARY owed (slot 1)
        uint128 pricePaid;      // Price paid per APIARY in HONEY (slot 1)
        uint128 claimed;        // Total APIARY already claimed (slot 2: 128+48+48=224 bits)
        uint48 vestingStart;    // Block when bond was created (slot 2)
        uint48 vestingEnd;      // Block when fully vested (slot 2)
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
    
    // Berachain average block time: ~3 seconds
    // 7 days = 7 * 24 * 60 * 60 / 3 = 201,600 blocks
    uint256 public constant DEFAULT_VESTING_TERM = 201_600;

    // Minimum vesting term: 1 day = 28,800 blocks
    uint256 public constant MINIMUM_VESTING_TERM = 28_800;

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

    /// @notice AUDIT-MEDIUM-03 Fix: Actual unredeemed bond obligations (only decrements on redeem)
    /// @dev Unlike totalDebt which decays linearly, this tracks real outstanding payouts
    ///      and is used in clawBackTokens() to protect bond holder funds.
    uint256 public totalUnredeemedPayout;

    /// @notice Maximum daily issuance as basis points of total APIARY supply (default: 300 = 3%)
    /// @dev Per doc: "Maximum Daily Issuance: 3% of total $APIARY supply". Set to 0 to disable.
    uint256 public maxDailyIssuanceBps;

    /// @notice APIARY issued in the current day (resets when a new day starts)
    uint256 public dailyIssuanceAmount;

    /// @notice Block number when the daily issuance counter was last reset
    uint256 public dailyIssuanceResetBlock;

    /// @notice When true, bonds cannot be sold below treasury backing per token
    bool public backingFloorEnabled;

    /// @notice Buffer above backing price in bps (e.g., 500 = 5% above backing)
    /// @dev Bond price must be >= backingPerToken * (10000 + buffer) / 10000
    uint256 public backingFloorBufferBps;

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
    /// @notice Daily issuance cap exceeded (max 3% of total APIARY supply per day)
    error APIARY__DAILY_ISSUANCE_EXCEEDED();
    /// @notice Bond price is below treasury backing per token
    error APIARY__BELOW_BACKING_FLOOR();

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
    /// @notice Emitted when max daily issuance bps is updated
    event MaxDailyIssuanceBpsUpdated(uint256 oldBps, uint256 newBps);
    event BackingFloorUpdated(bool enabled, uint256 bufferBps);

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

        // L-03 Fix: Initialize blocksPerDay (86400 seconds / 3 seconds per block = 28800)
        blocksPerDay = 28_800;

        // Launch at 20% to avoid bond reverts with thin initial liquidity.
        // Owner should tighten via setMaxPriceDeviation() as V2 liquidity grows.
        maxPriceDeviation = 2000; // 20% in basis points

        // Daily issuance cap: 3% of total APIARY supply per day (per doc)
        maxDailyIssuanceBps = 300;
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
        // AUDIT-MEDIUM-06 Fix: Ensure bond terms have been initialized before accepting deposits
        if (terms.vestingTerm == 0) revert APIARY__INVALID_VESTING_TERM();
        if (amount == 0) revert APIARY__INVALID_AMOUNT();
        if (maxPriceInHoney == 0) revert APIARY__INVALID_MAX_PRICE();
        // FIX (Finding 5): Require referencePrice to be set before accepting deposits
        // Without referencePrice, the TWAP price deviation check is entirely bypassed,
        // leaving bond pricing vulnerable to TWAP oracle manipulation
        if (referencePrice == 0) revert APIARY__PRICE_DEVIATION_TOO_HIGH();

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

        // Backing floor check: prevent bonds below treasury backing per token
        if (backingFloorEnabled) {
            _checkBackingFloor(discountedPriceInHoney);
        }

        // Daily issuance cap: max 3% of total APIARY supply per day
        _checkAndUpdateDailyIssuance(payOut);

        // Transfer principle tokens from user to this contract
        IERC20(principle).safeTransferFrom(msg.sender, address(this), amount);

        // Approve and deposit to treasury
        // Treasury mints `payOut` APIARY to this contract (bond depository)
        // C-06 Fix: Use forceApprove for tokens that require zero allowance first
        IERC20(principle).forceApprove(treasury, amount);
        IApiaryTreasury(treasury).deposit(amount, principle, payOut);

        // Update total debt
        totalDebt += payOut;
        // AUDIT-MEDIUM-03 Fix: Track actual unredeemed obligations for clawBack protection
        totalUnredeemedPayout += payOut;
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
            claimed: 0,
            vestingStart: uint48(block.number),
            vestingEnd: uint48(block.number + terms.vestingTerm)
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
        if (bond.claimed >= bond.payout) revert APIARY__BOND_ALREADY_REDEEMED();

        uint256 percentVested = _percentVestedFor(bond);

        // CODEX-HIGH-01 Fix: Compute total vested since bond creation, then subtract
        // already-claimed amount. This prevents repeated partial redemptions from
        // accelerating vesting (previously percentVested was re-applied to remaining balance).
        uint256 totalVested = uint256(bond.payout).mulDiv(
            percentVested >= BPS ? BPS : percentVested, BPS
        );
        payout = totalVested - uint256(bond.claimed);

        if (payout == 0) revert APIARY__NO_REDEEMABLE_BOND();

        bond.claimed += uint128(payout);
        uint256 remaining = uint256(bond.payout) - uint256(bond.claimed);

        emit BondRedeemed(msg.sender, bondIndex, payout, remaining);

        // MEDIUM-05 Fix: totalDebt reduction removed from redeem() to prevent
        // double-counting with _decayDebt(). Debt is now solely managed by linear decay.

        // AUDIT-MEDIUM-03 Fix: Decrement actual unredeemed obligations on redeem
        totalUnredeemedPayout -= payout;

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
            if (bonds[i].payout > 0 && bonds[i].claimed < bonds[i].payout) {
                uint256 percentVested = _percentVestedFor(bonds[i]);

                if (percentVested > 0) {
                    // CODEX-HIGH-01 Fix: Compute incremental payout as totalVested - claimed
                    uint256 totalVested = uint256(bonds[i].payout).mulDiv(
                        percentVested >= BPS ? BPS : percentVested, BPS
                    );
                    uint256 payout = totalVested - uint256(bonds[i].claimed);

                    if (payout > 0) {
                        bonds[i].claimed += uint128(payout);
                        totalPayout += payout;

                        uint256 remaining = uint256(bonds[i].payout) - uint256(bonds[i].claimed);
                        emit BondRedeemed(msg.sender, i, payout, remaining);
                    }
                }
            }
            unchecked { ++i; }
        }

        if (totalPayout == 0) revert APIARY__NOTHING_TO_REDEEM();
        // AUDIT-MEDIUM-03 Fix: Decrement actual unredeemed obligations on redeemAll
        totalUnredeemedPayout -= totalPayout;
        IERC20(APIARY).safeTransfer(msg.sender, totalPayout);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize bond terms (one-time only)
     * @param _vestingTerm Vesting duration in blocks
     * @param _maxPayout Max single bond in bps of treasury value (100 = 1%)
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
        if (_maxPayout > 1000) revert APIARY__INVALID_MAX_PAYOUT(); // Max 10% of treasury value
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
            if (_input > 1000) revert APIARY__INVALID_MAX_PAYOUT(); // Max 10% of treasury value
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
     * @notice Enable/disable backing price floor and set buffer
     * @dev When enabled, bonds cannot be sold at a price below treasury backing per token.
     *      Buffer adds a safety margin (e.g., 500 = 5% above backing).
     * @param _enabled True to enable backing floor check
     * @param _bufferBps Buffer above backing in basis points (0-5000)
     */
    function setBackingFloor(bool _enabled, uint256 _bufferBps) external onlyOwner {
        if (_bufferBps > 5000) revert APIARY__INVALID_AMOUNT(); // Max 50% buffer
        backingFloorEnabled = _enabled;
        backingFloorBufferBps = _bufferBps;
        emit BackingFloorUpdated(_enabled, _bufferBps);
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
    /// @notice AUDIT-FIX-04: Refresh cached oracle prices without requiring a bond deposit.
    /// @dev Allows a keeper or owner to update lastCachedApiaryPrice and lastCachedIbgtPrice
    ///      so that maxPayout() and dynamic discount tiers use fresh data.
    function refreshCachedPrices() external {
        uint256 apiaryPrice = twap.consult(10 ** IERC20Metadata(APIARY).decimals());
        lastCachedApiaryPrice = apiaryPrice;
        if (address(ibgtPriceFeed) != address(0)) {
            (, int256 answer,, uint256 updatedAt,) = ibgtPriceFeed.latestRoundData();
            if (answer > 0 && block.timestamp - updatedAt <= priceFeedStalenessThreshold) {
                lastCachedIbgtPrice = uint256(answer);
            }
        }
    }

    /// @notice AUDIT-FIX-06: Grace period (in blocks) after vestingEnd before bonds can be written off
    /// @dev ~90 days at 5s blocks = 1,555,200 blocks
    uint256 public constant ABANDONED_BOND_GRACE_PERIOD = 1_555_200;

    /// @notice AUDIT-FIX-06: Write off fully-vested bonds that have been unclaimed past the grace period.
    /// @dev Decrements totalUnredeemedPayout so the locked APIARY can be recovered via clawBackTokens.
    /// @param _depositor The bond holder whose bonds are being written off
    /// @param _bondIndexes Array of bond indexes to write off
    function writeOffAbandonedBonds(address _depositor, uint256[] calldata _bondIndexes) external onlyOwner {
        Bond[] storage bonds = userBonds[_depositor];
        for (uint256 i; i < _bondIndexes.length; ++i) {
            Bond storage bond = bonds[_bondIndexes[i]];
            if (bond.payout == 0) revert APIARY__NO_REDEEMABLE_BOND();
            if (bond.claimed >= bond.payout) revert APIARY__BOND_ALREADY_REDEEMED();
            if (bond.vestingEnd + ABANDONED_BOND_GRACE_PERIOD >= block.number) {
                revert APIARY__INVALID_BOND_INDEX(); // Not yet eligible for write-off
            }
            uint256 unclaimed = uint256(bond.payout) - uint256(bond.claimed);
            bond.claimed = bond.payout; // Mark as fully claimed
            totalUnredeemedPayout -= unclaimed;
        }
    }

    function clawBackTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert APIARY__ZERO_ADDRESS();
        if (_amount == 0) revert APIARY__INVALID_AMOUNT();

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) revert APIARY__INVALID_AMOUNT();

        // C-02 Fix + AUDIT-MEDIUM-03 Fix: Protect APIARY reserved for bond holder redemptions
        // Uses totalUnredeemedPayout (actual obligations) instead of totalDebt (which decays linearly)
        if (_token == APIARY) {
            uint256 excess = balance > totalUnredeemedPayout ? balance - totalUnredeemedPayout : 0;
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
                    DAILY ISSUANCE CAP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check and update daily issuance counter
     * @dev Resets counter when a new day starts (blocksPerDay blocks since last reset).
     *      Reverts if adding newPayout would exceed maxDailyIssuanceBps of total supply.
     *      FIX (Finding 7): Carry forward issuance from the tail of the previous bucket
     *      to prevent 2x daily cap bypass across bucket boundaries.
     * @param newPayout The APIARY payout to be issued
     */
    function _checkAndUpdateDailyIssuance(uint256 newPayout) internal {
        if (maxDailyIssuanceBps == 0) return; // Disabled

        uint256 totalSupply = IERC20(APIARY).totalSupply();
        if (totalSupply == 0) return; // No supply yet, skip check

        uint256 maxDaily = totalSupply.mulDiv(maxDailyIssuanceBps, BPS);

        // Reset counter if a new day has started.
        uint256 currentBucket = block.number - (block.number % blocksPerDay);
        if (dailyIssuanceResetBlock == 0 || currentBucket > dailyIssuanceResetBlock) {
            // FIX (Finding 7): Carry forward issuance from the tail of the previous bucket.
            // Calculate how much was issued in the last portion of the previous bucket
            // that falls within the "lookback window" (blocksPerDay from now).
            // If the previous bucket just ended (1 block ago), almost all of its issuance
            // carries over. If it ended long ago, nothing carries over.
            uint256 carryForward = 0;
            if (dailyIssuanceResetBlock != 0 && dailyIssuanceAmount > 0) {
                uint256 prevBucketEnd = dailyIssuanceResetBlock + blocksPerDay;
                // AUDIT-FIX-07: Guard against underflow when blocksPerDay is changed mid-epoch.
                // If block.number < prevBucketEnd (possible after blocksPerDay increase),
                // carry forward 100% of previous issuance (conservative).
                if (block.number < prevBucketEnd) {
                    carryForward = dailyIssuanceAmount;
                } else if (block.number < prevBucketEnd + blocksPerDay) {
                    // Blocks elapsed since previous bucket ended
                    uint256 blocksSincePrevEnd = block.number - prevBucketEnd;
                    if (blocksSincePrevEnd < blocksPerDay) {
                        // Pro-rate: carry forward the portion of previous issuance
                        // that was issued "recently" (within blocksPerDay of now)
                        uint256 remainingWeight = blocksPerDay - blocksSincePrevEnd;
                        carryForward = dailyIssuanceAmount.mulDiv(remainingWeight, blocksPerDay);
                    }
                }
            }
            dailyIssuanceAmount = carryForward;
            dailyIssuanceResetBlock = currentBucket;
        }

        if (dailyIssuanceAmount + newPayout > maxDaily) {
            revert APIARY__DAILY_ISSUANCE_EXCEEDED();
        }

        dailyIssuanceAmount += newPayout;
    }

    /**
     * @notice Check that the bond's discounted price is not below treasury backing per token
     * @dev Calculates backing = treasuryValue / totalSupply, applies buffer, reverts if bond price is below.
     *      Uses cached oracle prices to avoid extra external calls.
     * @param discountedPriceInHoney The bond price after discount (18 decimals, HONEY per APIARY)
     */
    function _checkBackingFloor(uint256 discountedPriceInHoney) internal view {
        uint256 totalSupply = IERC20(APIARY).totalSupply();
        if (totalSupply == 0) return; // No supply = no backing to protect

        // Estimate treasury value in HONEY (18 decimals) using cached prices
        uint256 treasuryValueHoney = _estimateTreasuryValueInHoney();
        if (treasuryValueHoney == 0) return; // Can't compute backing, skip

        // backingPerToken = treasuryValue(18-dec) * 1e9 / totalSupply(9-dec) = 18-dec HONEY per APIARY
        uint256 backingPerToken = treasuryValueHoney.mulDiv(1e9, totalSupply);

        // Apply buffer: floor = backing * (10000 + buffer) / 10000
        uint256 floor = backingPerToken.mulDiv(BPS + backingFloorBufferBps, BPS);

        if (discountedPriceInHoney < floor) {
            revert APIARY__BELOW_BACKING_FLOOR();
        }
    }

    /**
     * @notice Estimate total treasury value of this bond's principle reserves in HONEY
     * @dev Uses cached oracle prices. Returns 0 if prices not available.
     * @return valueInHoney Treasury reserves value in HONEY (18 decimals)
     */
    function _estimateTreasuryValueInHoney() internal view returns (uint256 valueInHoney) {
        uint256 reserves = IApiaryTreasury(treasury).totalReserves(principle);
        if (reserves == 0) return 0;

        if (isLiquidityBond) {
            // LP valuation returns APIARY-equivalent (9-dec), convert to HONEY using cached price
            uint256 valueInApiary = IApiaryBondingCalculator(bondCalculator).valuation(principle, reserves);
            uint256 cachedApiary = lastCachedApiaryPrice;
            if (cachedApiary == 0) return 0;
            // APIARY(9-dec) * apiaryPrice(18-dec) / 1e9 = HONEY(18-dec)
            return valueInApiary.mulDiv(cachedApiary, 1e9);
        } else {
            // iBGT: convert using cached iBGT price
            uint256 cachedIbgt = lastCachedIbgtPrice;
            if (cachedIbgt == 0) return 0;
            // reserves(18-dec) * ibgtPrice / feedDecimals = HONEY(18-dec)
            return reserves.mulDiv(cachedIbgt, 10 ** ibgtPriceFeedDecimals);
        }
    }

    /**
     * @notice Set maximum daily issuance as basis points of total APIARY supply
     * @dev Set to 0 to disable the daily cap. Default: 300 (3%).
     * @param _bps New max daily issuance in basis points (max 1000 = 10%)
     */
    function setMaxDailyIssuanceBps(uint256 _bps) external onlyOwner {
        if (_bps > 1000) revert APIARY__INVALID_AMOUNT(); // Max 10%
        uint256 oldBps = maxDailyIssuanceBps;
        maxDailyIssuanceBps = _bps;
        emit MaxDailyIssuanceBpsUpdated(oldBps, _bps);
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
            if (allBonds[i].payout > 0 && allBonds[i].claimed < allBonds[i].payout) {
                activeCount++;
            }
            unchecked { ++i; }
        }

        // Build arrays
        activeBonds = new Bond[](activeCount);
        indices = new uint256[](activeCount);
        uint256 j = 0;

        for (uint256 i = 0; i < allBonds.length;) {
            if (allBonds[i].payout > 0 && allBonds[i].claimed < allBonds[i].payout) {
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
     * @dev Debt ratio = (totalDebt / reserveValueInApiary) * BPS
     *      Both numerator and denominator are in APIARY (9 decimals) for correct comparison.
     *      Uses _estimateTreasuryValueInApiary() to convert raw reserves to APIARY terms
     *      via cached oracle prices (iBGT bonds) or bonding calculator (LP bonds).
     * @return ratio Debt ratio in basis points
     */
    function _calculateDebtRatio() internal view returns (uint256 ratio) {
        uint256 reserveValueInApiary = _estimateTreasuryValueInApiary();

        if (reserveValueInApiary == 0) {
            // No reserves or no cached prices = infinite debt ratio = paused
            return type(uint256).max;
        }

        ratio = totalDebt.mulDiv(BPS, reserveValueInApiary);
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
            // CODEX-HIGH-02 Fix: Calculator returns geometric mean in 9-dec, not HONEY-equivalent.
            // Multiply by sqrt(apiaryPrice) to convert to HONEY-equivalent (9-dec).
            // Math: fair_LP_value_in_HONEY = 2*sqrt(k*P)/totalSupply*amount = geometric * sqrt(P)
            // where sqrt(apiaryPrice_18dec) returns a 9-dec value.
            uint256 geometric = IApiaryBondingCalculator(bondCalculator).valuation(_token, _amount);
            value_ = geometric.mulDiv(Math.sqrt(apiaryPrice), 1e9);
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
        if (bond.payout == 0 || bond.claimed >= bond.payout) return 0;

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
            if (bonds[i].payout > 0 && bonds[i].claimed < bonds[i].payout) {
                uint256 percentVested = _percentVestedFor(bonds[i]);
                // CODEX-HIGH-01 Fix: incremental payout = totalVested - claimed
                uint256 totalVested = uint256(bonds[i].payout).mulDiv(
                    percentVested >= BPS ? BPS : percentVested, BPS
                );
                totalPending_ += totalVested - uint256(bonds[i].claimed);
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
        if (bond.payout == 0 || bond.claimed >= bond.payout) return 0;

        uint256 percentVested = _percentVestedFor(bond);
        // CODEX-HIGH-01 Fix: incremental payout = totalVested - claimed
        uint256 totalVested = uint256(bond.payout).mulDiv(
            percentVested >= BPS ? BPS : percentVested, BPS
        );
        pendingPayout_ = totalVested - uint256(bond.claimed);
    }

    /**
     * @notice Calculate maximum payout per bond (1% of treasury value per doc)
     * @dev Uses cached oracle prices to estimate treasury value in APIARY terms.
     *      Falls back to allocation-based limit before first deposit (no cached prices).
     * @return Maximum payout in APIARY (9 decimals)
     */
    function maxPayout() public view returns (uint256) {
        uint256 treasuryValueInApiary = _estimateTreasuryValueInApiary();

        if (treasuryValueInApiary > 0) {
            return treasuryValueInApiary.mulDiv(terms.maxPayout, BPS);
        }

        // AUDIT-FIX-09: Before first deposit (cached prices are zero), return MINIMUM_PAYOUT
        // instead of allocation-based fallback. The allocation fallback can be orders of
        // magnitude larger than actual treasury value, violating the spec's "1% of treasury value".
        if (lastCachedApiaryPrice == 0) {
            return MINIMUM_PAYOUT;
        }

        // Fallback when treasury value estimate returns 0 but prices are cached
        uint256 totalAllocatedToTreasury = IApiaryToken(APIARY).allocationLimits(treasury);
        return totalAllocatedToTreasury.mulDiv(terms.maxPayout, BPS);
    }

    /**
     * @notice Estimate treasury value of this bond's principle reserves in APIARY terms
     * @dev Uses cached oracle prices from the most recent deposit() call.
     *      For iBGT: converts via iBGT/USD and APIARY/HONEY cached prices.
     *      For LP: uses bonding calculator valuation (already APIARY-denominated).
     * @return valueInApiary Estimated treasury reserves value in APIARY (9 decimals)
     */
    function _estimateTreasuryValueInApiary() internal view returns (uint256 valueInApiary) {
        uint256 reserves = IApiaryTreasury(treasury).totalReserves(principle);
        if (reserves == 0) return 0;

        if (isLiquidityBond) {
            // CODEX-HIGH-02 Fix: Convert geometric mean → APIARY value (9-dec)
            // APIARY_value = geometric * 1e9 / sqrt(apiaryPrice)
            uint256 geometric = IApiaryBondingCalculator(bondCalculator).valuation(principle, reserves);
            uint256 cachedApiary = lastCachedApiaryPrice;
            if (cachedApiary == 0) return 0;
            uint256 sqrtPrice = Math.sqrt(cachedApiary);
            if (sqrtPrice == 0) return 0;
            return geometric.mulDiv(1e9, sqrtPrice);
        } else {
            // iBGT: convert reserves → HONEY → APIARY using cached prices
            uint256 cachedIbgt = lastCachedIbgtPrice;
            uint256 cachedApiary = lastCachedApiaryPrice;
            if (cachedIbgt == 0 || cachedApiary == 0) return 0;

            // reserves(18-dec) * ibgtPrice / feedDecimals → HONEY(18-dec)
            uint256 honeyValue = reserves.mulDiv(cachedIbgt, 10 ** ibgtPriceFeedDecimals);
            // HONEY(18-dec) * 1e9 / apiaryPrice(18-dec) → APIARY(9-dec)
            return honeyValue.mulDiv(1e9, cachedApiary);
        }
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
            // CODEX-HIGH-02 Fix: Convert geometric mean → HONEY-equivalent using sqrt(price)
            uint256 geometric = IApiaryBondingCalculator(bondCalculator).valuation(_token, _amount);
            estimatedPayout = geometric.mulDiv(Math.sqrt(cachedPrice), 1e9);
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
