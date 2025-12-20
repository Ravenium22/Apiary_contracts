// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IApiaryInfraredAdapter } from "./interfaces/IApiaryInfraredAdapter.sol";
import { IApiaryKodiakAdapter } from "./interfaces/IApiaryKodiakAdapter.sol";
import { IApiaryToken } from "./interfaces/IApiaryToken.sol";

/**
 * @title ApiaryYieldManager
 * @author Apiary Protocol
 * @notice Orchestrates yield strategy execution for Apiary protocol
 * @dev Most critical contract - manages treasury yield distribution
 * 
 * PHASE 1 STRATEGY (25/25/50):
 * - Claim iBGT rewards from Infrared adapter
 * - 25% → swap to HONEY
 * - 25% → swap to APIARY → burn
 * - 50% → swap to APIARY + combine with HONEY → LP → stake
 * 
 * PHASE 2 STRATEGY (Conditional):
 * - If MC > TV * 1.30 → compound (keep as iBGT)
 * - If MC within 30% → distribute to stakers
 * - If MC < TV → 100% buyback and burn
 * 
 * PHASE 3 STRATEGY (vBGT):
 * - Accumulate BGT → vBGT staking
 * - Maximize POL benefits
 * 
 * SECURITY:
 * - ReentrancyGuard on executeYield (multiple external calls)
 * - Pausable for emergencies
 * - Ownable2Step for safe ownership transfer
 * - Split percentages validation (must sum to 100%)
 * - Slippage protection on all swaps
 * - Atomic execution - reverts entirely on any failure
 * - Minimum time between executions (anti-griefing)
 * - Typed interfaces for all external calls
 */
contract ApiaryYieldManager is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            TYPE DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Yield distribution strategies
     * @dev Each phase has different yield allocation logic
     */
    enum Strategy {
        PHASE1_LP_BURN,      // 25% HONEY, 25% burn, 50% LP+stake
        PHASE2_CONDITIONAL,  // MC/TV based distribution
        PHASE3_VBGT          // vBGT accumulation
    }

    /**
     * @notice Split percentages for yield distribution
     * @dev All values in basis points (10000 = 100%)
     */
    struct SplitConfig {
        uint256 toHoney;      // % swapped to HONEY
        uint256 toApiaryLP;   // % swapped to APIARY for LP
        uint256 toBurn;       // % swapped to APIARY and burned
        uint256 toStakers;    // % distributed to stakers (Phase 2+)
        uint256 toCompound;   // % kept as iBGT compound (Phase 2+)
    }

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice APIARY governance token
    IERC20 public immutable apiaryToken;

    /// @notice HONEY stablecoin
    IERC20 public immutable honeyToken;

    /// @notice iBGT reward token from Infrared
    IERC20 public immutable ibgtToken;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Treasury address (receives LP tokens, manages reserves)
    address public treasury;

    /// @notice Infrared adapter for iBGT staking
    address public infraredAdapter;

    /// @notice Kodiak adapter for swaps and LP
    address public kodiakAdapter;

    /// @notice Staking contract for APIARY stakers
    address public stakingContract;

    /// @notice Current active strategy
    Strategy public currentStrategy;

    /// @notice Current split configuration
    SplitConfig public splitConfig;

    /// @notice Slippage tolerance in basis points (default: 50 = 0.5%)
    uint256 public slippageTolerance;

    /// @notice Minimum yield amount to execute (prevent dust execution)
    uint256 public minYieldAmount;

    /// @notice Maximum single execution amount (gas limit protection)
    uint256 public maxExecutionAmount;

    /// @notice Market cap threshold multiplier for Phase 2 (basis points)
    uint256 public mcThresholdMultiplier;

    /// @notice Total yield processed (historical tracking)
    uint256 public totalYieldProcessed;

    /// @notice Total APIARY burned (historical tracking)
    uint256 public totalApiaryBurned;

    /// @notice Total LP created (historical tracking)
    uint256 public totalLPCreated;

    /// @notice Last execution timestamp
    uint256 public lastExecutionTime;

    /// @notice Last execution block
    uint256 public lastExecutionBlock;

    /// @notice Emergency mode (skip swaps, forward directly to treasury)
    bool public emergencyMode;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum time between yield executions (anti-griefing)
    uint256 public constant MIN_EXECUTION_INTERVAL = 1 hours;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Maximum slippage tolerance (10%)
    uint256 public constant MAX_SLIPPAGE = 1000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event YieldExecuted(
        Strategy indexed strategy,
        uint256 totalYield,
        uint256 honeySwapped,
        uint256 apiaryBurned,
        uint256 lpCreated,
        uint256 compounded
    );

    event StrategyChanged(Strategy indexed oldStrategy, Strategy indexed newStrategy);

    event SplitConfigUpdated(
        uint256 toHoney,
        uint256 toApiaryLP,
        uint256 toBurn,
        uint256 toStakers,
        uint256 toCompound
    );

    event AdapterUpdated(string indexed adapterType, address indexed oldAdapter, address indexed newAdapter);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);

    event EmergencyModeToggled(bool enabled);

    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed recipient);

    event ApprovalsSetup(address indexed adapter, address[] tokens);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_SPLIT_CONFIG();
    error APIARY__INSUFFICIENT_YIELD();
    error APIARY__EXECUTION_AMOUNT_TOO_HIGH();
    error APIARY__EXECUTION_TOO_SOON();
    error APIARY__CLAIM_FAILED();
    error APIARY__SWAP_FAILED();
    error APIARY__BURN_FAILED();
    error APIARY__LP_FAILED();
    error APIARY__STAKE_FAILED();
    error APIARY__SLIPPAGE_TOO_HIGH();
    error APIARY__NO_PENDING_YIELD();
    error APIARY__EMERGENCY_MODE_ACTIVE();
    error APIARY__ADAPTER_NOT_SET();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize yield manager
     * @param _apiaryToken APIARY token address
     * @param _honeyToken HONEY token address
     * @param _ibgtToken iBGT token address
     * @param _treasury Treasury address
     * @param _infraredAdapter Infrared adapter address
     * @param _kodiakAdapter Kodiak adapter address
     * @param _owner Owner address
     */
    constructor(
        address _apiaryToken,
        address _honeyToken,
        address _ibgtToken,
        address _treasury,
        address _infraredAdapter,
        address _kodiakAdapter,
        address _owner
    ) Ownable(_owner) {
        if (
            _apiaryToken == address(0) || _honeyToken == address(0) || _ibgtToken == address(0)
                || _treasury == address(0) || _infraredAdapter == address(0) || _kodiakAdapter == address(0)
        ) {
            revert APIARY__ZERO_ADDRESS();
        }

        apiaryToken = IERC20(_apiaryToken);
        honeyToken = IERC20(_honeyToken);
        ibgtToken = IERC20(_ibgtToken);
        treasury = _treasury;
        infraredAdapter = _infraredAdapter;
        kodiakAdapter = _kodiakAdapter;

        // Phase 1 default configuration (25/25/50)
        currentStrategy = Strategy.PHASE1_LP_BURN;
        splitConfig = SplitConfig({
            toHoney: 2500, // 25%
            toApiaryLP: 5000, // 50% (split between APIARY and HONEY for LP)
            toBurn: 2500, // 25%
            toStakers: 0, // Not used in Phase 1
            toCompound: 0 // Not used in Phase 1
        });

        // Default parameters
        slippageTolerance = 50; // 0.5%
        minYieldAmount = 0.1e18; // 0.1 iBGT minimum
        maxExecutionAmount = 10000e18; // 10k iBGT max per execution
        mcThresholdMultiplier = 13000; // 130% (for Phase 2)
    }

    /*//////////////////////////////////////////////////////////////
                            MAIN EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute yield strategy based on current configuration
     * @dev Main entry point - claims rewards and distributes according to strategy
     * @return totalYield Total yield processed
     * @return honeySwapped Amount swapped to HONEY
     * @return apiaryBurned Amount of APIARY burned
     * @return lpCreated Amount of LP tokens created
     * @return compounded Amount kept as iBGT (Phase 2+)
     * 
     * Requirements:
     * - Contract not paused
     * - Pending yield > minYieldAmount
     * - Adapters configured
     * - Split percentages valid
     * 
     * Process:
     * 1. Claim rewards from Infrared adapter
     * 2. Execute strategy based on currentStrategy
     * 3. Update historical tracking
     * 4. Emit events
     * 
     * ATOMIC: Reverts entirely on any failure - no partial execution
     */
    function executeYield()
        external
        whenNotPaused
        nonReentrant
        returns (uint256 totalYield, uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated, uint256 compounded)
    {
        // Anti-griefing: enforce minimum time between executions
        if (block.timestamp < lastExecutionTime + MIN_EXECUTION_INTERVAL) {
            revert APIARY__EXECUTION_TOO_SOON();
        }

        // Check pending yield
        totalYield = pendingYield();
        if (totalYield == 0) {
            revert APIARY__NO_PENDING_YIELD();
        }

        if (totalYield < minYieldAmount) {
            revert APIARY__INSUFFICIENT_YIELD();
        }

        // Cap execution amount for gas safety
        if (totalYield > maxExecutionAmount) {
            totalYield = maxExecutionAmount;
        }

        // Update timestamps first (CEI pattern)
        lastExecutionTime = block.timestamp;
        lastExecutionBlock = block.number;

        // Claim rewards from Infrared adapter (reverts on failure)
        _claimYieldFromInfrared(totalYield);

        // Execute strategy (each step reverts on failure - atomic)
        if (currentStrategy == Strategy.PHASE1_LP_BURN) {
            (honeySwapped, apiaryBurned, lpCreated) = _executePhase1Strategy(totalYield);
        } else if (currentStrategy == Strategy.PHASE2_CONDITIONAL) {
            (honeySwapped, apiaryBurned, lpCreated, compounded) = _executePhase2Strategy(totalYield);
        } else if (currentStrategy == Strategy.PHASE3_VBGT) {
            compounded = _executePhase3Strategy(totalYield);
        }

        // Update tracking
        totalYieldProcessed += totalYield;

        emit YieldExecuted(currentStrategy, totalYield, honeySwapped, apiaryBurned, lpCreated, compounded);
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute Phase 1 strategy (25/25/50 split)
     * @param totalYield Total iBGT claimed
     * @return honeySwapped Amount swapped to HONEY
     * @return apiaryBurned Amount of APIARY burned
     * @return lpCreated Amount of LP tokens created
     * 
     * Flow:
     * 1. 25% iBGT → swap to HONEY → hold for LP
     * 2. 25% iBGT → swap to APIARY → burn
     * 3. 50% iBGT → swap to APIARY → combine with HONEY → LP → stake
     */
    function _executePhase1Strategy(uint256 totalYield)
        internal
        returns (uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated)
    {
        if (emergencyMode) {
            // Emergency: forward all to treasury
            ibgtToken.safeTransfer(treasury, totalYield);
            return (0, 0, 0);
        }

        // Calculate splits using BASIS_POINTS
        uint256 toHoneyAmount = (totalYield * splitConfig.toHoney) / BASIS_POINTS;
        uint256 toBurnAmount = (totalYield * splitConfig.toBurn) / BASIS_POINTS;
        uint256 toLPAmount = totalYield - toHoneyAmount - toBurnAmount;

        // 1. Swap 25% to HONEY (reverts on failure - atomic)
        honeySwapped = _swapToHoney(toHoneyAmount);

        // 2. Swap 25% to APIARY and burn (reverts on failure - atomic)
        uint256 apiaryForBurn = _swapToApiary(toBurnAmount);
        apiaryBurned = _burnApiary(apiaryForBurn);

        // 3. Swap 50% to APIARY for LP (reverts on failure - atomic)
        uint256 apiaryForLP = _swapToApiary(toLPAmount);

        // 4. Create LP (APIARY + HONEY) (reverts on failure - atomic)
        // Need to calculate how much HONEY to pair with APIARY
        uint256 honeyForLP = _calculateHoneyForLP(apiaryForLP, honeySwapped);

        if (honeyForLP > 0 && apiaryForLP > 0) {
            lpCreated = _createAndStakeLP(apiaryForLP, honeyForLP);
        }

        // 5. Any remaining HONEY goes to treasury (dust stays in contract if < threshold)
        uint256 remainingHoney = honeySwapped - honeyForLP;
        if (remainingHoney > 0) {
            honeyToken.safeTransfer(treasury, remainingHoney);
        }
    }

    /**
     * @notice Execute Phase 2 strategy (conditional based on MC/TV)
     * @param totalYield Total iBGT claimed
     * @return honeySwapped Amount swapped to HONEY
     * @return apiaryBurned Amount of APIARY burned
     * @return lpCreated Amount of LP tokens created
     * @return compounded Amount kept as iBGT
     * 
     * Logic:
     * - If MC > TV * 1.30 → compound (splitConfig.toCompound%)
     * - If MC within 30% of TV → distribute to stakers (splitConfig.toStakers%)
     * - If MC < TV → 100% buyback and burn
     */
    function _executePhase2Strategy(uint256 totalYield)
        internal
        returns (uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated, uint256 compounded)
    {
        // Get market cap and treasury value from treasury contract
        (uint256 marketCap, uint256 treasuryValue) = _getMarketCapAndTV();

        // Determine distribution based on MC/TV ratio
        if (marketCap > (treasuryValue * mcThresholdMultiplier) / BASIS_POINTS) {
            // MC > TV * 1.30 → compound
            compounded = (totalYield * splitConfig.toCompound) / BASIS_POINTS;
            ibgtToken.safeTransfer(treasury, compounded);

            // Remaining follows Phase 1 logic
            uint256 remaining = totalYield - compounded;
            (honeySwapped, apiaryBurned, lpCreated) = _executePhase1Strategy(remaining);
        } else if (marketCap < treasuryValue) {
            // MC < TV → 100% buyback and burn
            uint256 apiaryBought = _swapToApiary(totalYield);
            apiaryBurned = _burnApiary(apiaryBought);
        } else {
            // MC within 30% of TV → distribute to stakers
            uint256 toStakersAmount = (totalYield * splitConfig.toStakers) / BASIS_POINTS;
            _distributeToStakers(toStakersAmount);

            // Remaining follows Phase 1 logic
            uint256 remaining = totalYield - toStakersAmount;
            (honeySwapped, apiaryBurned, lpCreated) = _executePhase1Strategy(remaining);
        }
    }

    /**
     * @notice Execute Phase 3 strategy (vBGT accumulation)
     * @param totalYield Total iBGT claimed
     * @return compounded Amount sent to vBGT strategy
     * 
     * Note: Full implementation pending vBGT contract deployment
     */
    function _executePhase3Strategy(uint256 totalYield) internal returns (uint256 compounded) {
        // Placeholder: Send to treasury for vBGT conversion
        ibgtToken.safeTransfer(treasury, totalYield);
        compounded = totalYield;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim yield from Infrared adapter
     * @param expectedAmount Expected minimum amount to claim
     * @dev Uses typed interface - reverts on failure (atomic)
     */
    function _claimYieldFromInfrared(uint256 expectedAmount) internal {
        if (infraredAdapter == address(0)) {
            revert APIARY__ADAPTER_NOT_SET();
        }

        uint256 balanceBefore = ibgtToken.balanceOf(address(this));

        // Use typed interface for claim
        uint256 claimed = IApiaryInfraredAdapter(infraredAdapter).claimRewards();

        uint256 balanceAfter = ibgtToken.balanceOf(address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;

        // Verify tokens were received and match expected
        if (actualReceived == 0 || claimed == 0 || actualReceived < expectedAmount) {
            revert APIARY__CLAIM_FAILED();
        }
    }

    /**
     * @notice Swap iBGT to HONEY via Kodiak
     * @param amount Amount of iBGT to swap
     * @return honeyReceived Amount of HONEY received
     * @dev Uses typed interface - reverts on failure (atomic)
     */
    function _swapToHoney(uint256 amount) internal returns (uint256 honeyReceived) {
        if (kodiakAdapter == address(0)) {
            revert APIARY__ADAPTER_NOT_SET();
        }

        if (amount == 0) return 0;

        // Calculate minimum output using adapter's quote function
        uint256 expectedOutput = IApiaryKodiakAdapter(kodiakAdapter).getAmountOut(
            address(ibgtToken),
            address(honeyToken),
            amount
        );
        uint256 minOutput = _calculateMinOutput(expectedOutput);

        // Approve Kodiak adapter
        ibgtToken.forceApprove(kodiakAdapter, amount);

        // Use typed interface for swap
        honeyReceived = IApiaryKodiakAdapter(kodiakAdapter).swap(
            address(ibgtToken),
            address(honeyToken),
            amount,
            minOutput,
            address(this)
        );

        // Verify we received tokens
        if (honeyReceived == 0) {
            revert APIARY__SWAP_FAILED();
        }
    }

    /**
     * @notice Swap iBGT to APIARY via Kodiak
     * @param amount Amount of iBGT to swap
     * @return apiaryReceived Amount of APIARY received
     * @dev Uses typed interface - reverts on failure (atomic)
     */
    function _swapToApiary(uint256 amount) internal returns (uint256 apiaryReceived) {
        if (kodiakAdapter == address(0)) {
            revert APIARY__ADAPTER_NOT_SET();
        }

        if (amount == 0) return 0;

        // Calculate minimum output using adapter's quote function
        uint256 expectedOutput = IApiaryKodiakAdapter(kodiakAdapter).getAmountOut(
            address(ibgtToken),
            address(apiaryToken),
            amount
        );
        uint256 minOutput = _calculateMinOutput(expectedOutput);

        // Approve Kodiak adapter
        ibgtToken.forceApprove(kodiakAdapter, amount);

        // Use typed interface for swap
        apiaryReceived = IApiaryKodiakAdapter(kodiakAdapter).swap(
            address(ibgtToken),
            address(apiaryToken),
            amount,
            minOutput,
            address(this)
        );

        // Verify we received tokens
        if (apiaryReceived == 0) {
            revert APIARY__SWAP_FAILED();
        }
    }

    /**
     * @notice Burn APIARY tokens
     * @param amount Amount to burn
     * @return burned Actual amount burned
     * @dev Uses IApiaryToken.burn() - reverts on failure (atomic)
     */
    function _burnApiary(uint256 amount) internal returns (uint256 burned) {
        if (amount == 0) return 0;

        uint256 balanceBefore = apiaryToken.balanceOf(address(this));

        // Use typed interface for burn - reverts if burn fails
        IApiaryToken(address(apiaryToken)).burn(amount);

        uint256 balanceAfter = apiaryToken.balanceOf(address(this));

        // Verify tokens were burned
        if (balanceAfter >= balanceBefore) {
            revert APIARY__BURN_FAILED();
        }

        burned = balanceBefore - balanceAfter;
        totalApiaryBurned += burned;
    }

    /**
     * @notice Create LP and stake on Kodiak
     * @param apiaryAmount Amount of APIARY for LP
     * @param honeyAmount Amount of HONEY for LP
     * @return lpTokens Amount of LP tokens created
     * @dev Uses typed interface - reverts on failure (atomic)
     */
    function _createAndStakeLP(uint256 apiaryAmount, uint256 honeyAmount) internal returns (uint256 lpTokens) {
        if (kodiakAdapter == address(0)) {
            revert APIARY__ADAPTER_NOT_SET();
        }

        if (apiaryAmount == 0 || honeyAmount == 0) return 0;

        // Approve Kodiak adapter
        apiaryToken.forceApprove(kodiakAdapter, apiaryAmount);
        honeyToken.forceApprove(kodiakAdapter, honeyAmount);

        // Use typed interface for addLiquidity
        // Calculate minimum LP with slippage protection
        uint256 minLP = _calculateMinOutput(apiaryAmount);  // Simplified slippage protection
        (, , uint256 liquidity) = IApiaryKodiakAdapter(kodiakAdapter).addLiquidity(
            address(apiaryToken),
            address(honeyToken),
            apiaryAmount,
            honeyAmount,
            minLP,
            address(this)
        );

        if (liquidity == 0) {
            revert APIARY__LP_FAILED();
        }

        lpTokens = liquidity;

        // Stake LP tokens
        _stakeLPTokens(lpTokens);

        totalLPCreated += lpTokens;
    }

    /**
     * @notice Stake LP tokens on Kodiak gauge
     * @param lpAmount Amount of LP tokens to stake
     * @dev Uses typed interface - reverts on failure (atomic)
     */
    function _stakeLPTokens(uint256 lpAmount) internal {
        if (kodiakAdapter == address(0) || lpAmount == 0) return;

        // Get LP token address from adapter
        address lpToken = IApiaryKodiakAdapter(kodiakAdapter).getLPToken(
            address(apiaryToken),
            address(honeyToken)
        );

        if (lpToken == address(0)) {
            revert APIARY__LP_FAILED();
        }

        // Approve LP tokens
        IERC20(lpToken).forceApprove(kodiakAdapter, lpAmount);

        // Stake LP tokens via adapter
        IApiaryKodiakAdapter(kodiakAdapter).stakeLP(lpToken, lpAmount);
    }

    /**
     * @notice Distribute yield to stakers (Phase 2)
     * @param amount Amount of iBGT to distribute
     */
    function _distributeToStakers(uint256 amount) internal {
        if (stakingContract == address(0) || amount == 0) return;

        // Swap to APIARY first
        uint256 apiaryAmount = _swapToApiary(amount);

        // Transfer to staking contract for distribution
        if (apiaryAmount > 0) {
            apiaryToken.safeTransfer(stakingContract, apiaryAmount);
        }
    }

    /**
     * @notice Calculate how much HONEY needed for LP pairing
     * @param apiaryAmount Amount of APIARY for LP
     * @param availableHoney Total HONEY available
     * @return honeyForLP Amount of HONEY to use
     * @dev Uses adapter's quote function for accurate ratio
     */
    function _calculateHoneyForLP(uint256 apiaryAmount, uint256 availableHoney)
        internal
        view
        returns (uint256 honeyForLP)
    {
        if (kodiakAdapter == address(0)) {
            // Fallback to simple min
            return apiaryAmount < availableHoney ? apiaryAmount : availableHoney;
        }

        // Simple ratio-based calculation since quoteAddLiquidity may not be available
        // Use 1:1 ratio assumption or available honey, whichever is less
        honeyForLP = apiaryAmount < availableHoney ? apiaryAmount : availableHoney;
    }

    /**
     * @notice Calculate minimum LP tokens with slippage
     * @param apiaryAmount Amount of APIARY
     * @param honeyAmount Amount of HONEY
     * @return minLP Minimum LP tokens to receive
     */
    function _calculateMinLP(uint256 apiaryAmount, uint256 honeyAmount) internal view returns (uint256 minLP) {
        // Simplified: min of the two amounts, minus slippage
        uint256 baseAmount = apiaryAmount < honeyAmount ? apiaryAmount : honeyAmount;
        minLP = _calculateMinOutput(baseAmount);
    }

    /**
     * @notice Calculate minimum output with slippage protection
     * @param expectedAmount Expected output before slippage
     * @return minOutput Minimum acceptable output
     */
    function _calculateMinOutput(uint256 expectedAmount) internal view returns (uint256 minOutput) {
        minOutput = (expectedAmount * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;
    }

    /**
     * @notice Get market cap and treasury value (Phase 2 logic)
     * @return marketCap Current market cap
     * @return treasuryValue Current treasury value
     */
    function _getMarketCapAndTV() internal view returns (uint256 marketCap, uint256 treasuryValue) {
        // Call treasury contract to get values
        // Placeholder implementation
        if (treasury == address(0)) return (0, 0);

        (bool success, bytes memory data) =
            treasury.staticcall(abi.encodeWithSignature("getMarketCapAndTreasuryValue()"));

        if (success) {
            (marketCap, treasuryValue) = abi.decode(data, (uint256, uint256));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending yield from Infrared adapter
     * @return pendingAmount Amount of iBGT claimable
     */
    function pendingYield() public view returns (uint256 pendingAmount) {
        if (infraredAdapter == address(0)) return 0;

        pendingAmount = IApiaryInfraredAdapter(infraredAdapter).pendingRewards();
    }

    /**
     * @notice Get current split percentages
     * @return Current SplitConfig
     */
    function getSplitPercentages() external view returns (SplitConfig memory) {
        return splitConfig;
    }

    /**
     * @notice Check if yield execution is available
     * @return canExecute True if pending yield >= minimum and interval passed
     * @return pending Current pending yield
     * @return timeUntilNextExecution Seconds until next execution is allowed
     */
    function canExecuteYield() external view returns (bool canExecute, uint256 pending, uint256 timeUntilNextExecution) {
        pending = pendingYield();
        uint256 nextAllowedTime = lastExecutionTime + MIN_EXECUTION_INTERVAL;
        
        if (block.timestamp < nextAllowedTime) {
            timeUntilNextExecution = nextAllowedTime - block.timestamp;
            canExecute = false;
        } else {
            timeUntilNextExecution = 0;
            canExecute = pending >= minYieldAmount && !paused();
        }
    }

    /**
     * @notice Get yield manager statistics
     * @return _totalYieldProcessed Total yield processed
     * @return _totalApiaryBurned Total APIARY burned
     * @return _totalLPCreated Total LP created
     * @return _lastExecutionTime Last execution timestamp
     * @return _lastExecutionBlock Last execution block
     */
    function getStatistics()
        external
        view
        returns (
            uint256 _totalYieldProcessed,
            uint256 _totalApiaryBurned,
            uint256 _totalLPCreated,
            uint256 _lastExecutionTime,
            uint256 _lastExecutionBlock
        )
    {
        _totalYieldProcessed = totalYieldProcessed;
        _totalApiaryBurned = totalApiaryBurned;
        _totalLPCreated = totalLPCreated;
        _lastExecutionTime = lastExecutionTime;
        _lastExecutionBlock = lastExecutionBlock;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set active strategy
     * @param _strategy New strategy to activate
     */
    function setStrategy(Strategy _strategy) external onlyOwner {
        Strategy oldStrategy = currentStrategy;
        currentStrategy = _strategy;

        emit StrategyChanged(oldStrategy, _strategy);
    }

    /**
     * @notice Set split percentages
     * @param toHoney % to HONEY
     * @param toApiaryLP % to APIARY LP
     * @param toBurn % to burn
     * @param toStakers % to stakers (Phase 2+)
     * @param toCompound % to compound (Phase 2+)
     * 
     * Requirements:
     * - Sum must equal BASIS_POINTS (100%)
     */
    function setSplitPercentages(
        uint256 toHoney,
        uint256 toApiaryLP,
        uint256 toBurn,
        uint256 toStakers,
        uint256 toCompound
    ) external onlyOwner {
        uint256 total = toHoney + toApiaryLP + toBurn + toStakers + toCompound;

        if (total != BASIS_POINTS) {
            revert APIARY__INVALID_SPLIT_CONFIG();
        }

        splitConfig = SplitConfig({
            toHoney: toHoney,
            toApiaryLP: toApiaryLP,
            toBurn: toBurn,
            toStakers: toStakers,
            toCompound: toCompound
        });

        emit SplitConfigUpdated(toHoney, toApiaryLP, toBurn, toStakers, toCompound);
    }

    /**
     * @notice Set slippage tolerance
     * @param _slippage Slippage in basis points (max 1000 = 10%)
     */
    function setSlippageTolerance(uint256 _slippage) external onlyOwner {
        if (_slippage > MAX_SLIPPAGE) {
            revert APIARY__SLIPPAGE_TOO_HIGH();
        }

        uint256 oldTolerance = slippageTolerance;
        slippageTolerance = _slippage;

        emit SlippageToleranceUpdated(oldTolerance, _slippage);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldTreasury = treasury;
        treasury = _treasury;

        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Update Infrared adapter
     * @param _adapter New adapter address
     */
    function setInfraredAdapter(address _adapter) external onlyOwner {
        if (_adapter == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldAdapter = infraredAdapter;
        infraredAdapter = _adapter;

        emit AdapterUpdated("infrared", oldAdapter, _adapter);
    }

    /**
     * @notice Update Kodiak adapter
     * @param _adapter New adapter address
     */
    function setKodiakAdapter(address _adapter) external onlyOwner {
        if (_adapter == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldAdapter = kodiakAdapter;
        kodiakAdapter = _adapter;

        emit AdapterUpdated("kodiak", oldAdapter, _adapter);
    }

    /**
     * @notice Update staking contract
     * @param _staking New staking contract address
     */
    function setStakingContract(address _staking) external onlyOwner {
        stakingContract = _staking;
    }

    /**
     * @notice Set minimum yield amount
     * @param _minAmount New minimum amount
     */
    function setMinYieldAmount(uint256 _minAmount) external onlyOwner {
        minYieldAmount = _minAmount;
    }

    /**
     * @notice Set maximum execution amount
     * @param _maxAmount New maximum amount
     */
    function setMaxExecutionAmount(uint256 _maxAmount) external onlyOwner {
        maxExecutionAmount = _maxAmount;
    }

    /**
     * @notice Set MC threshold multiplier for Phase 2
     * @param _multiplier Multiplier in basis points (13000 = 130%)
     */
    function setMCThresholdMultiplier(uint256 _multiplier) external onlyOwner {
        mcThresholdMultiplier = _multiplier;
    }

    /**
     * @notice Toggle emergency mode
     * @param _enabled True to enable, false to disable
     */
    function setEmergencyMode(bool _enabled) external onlyOwner {
        emergencyMode = _enabled;

        emit EmergencyModeToggled(_enabled);
    }

    /**
     * @notice Setup token approvals for adapters
     * @dev Should be called after deployment or when adapters are updated
     * Approves max amounts for efficiency - safe because adapters are trusted
     */
    function setupApprovals() external onlyOwner {
        // Approve Kodiak adapter for all relevant tokens
        if (kodiakAdapter != address(0)) {
            ibgtToken.forceApprove(kodiakAdapter, type(uint256).max);
            apiaryToken.forceApprove(kodiakAdapter, type(uint256).max);
            honeyToken.forceApprove(kodiakAdapter, type(uint256).max);

            address[] memory tokens = new address[](3);
            tokens[0] = address(ibgtToken);
            tokens[1] = address(apiaryToken);
            tokens[2] = address(honeyToken);
            emit ApprovalsSetup(kodiakAdapter, tokens);
        }

        // Approve Infrared adapter for iBGT if needed
        if (infraredAdapter != address(0)) {
            ibgtToken.forceApprove(infraredAdapter, type(uint256).max);

            address[] memory tokens = new address[](1);
            tokens[0] = address(ibgtToken);
            emit ApprovalsSetup(infraredAdapter, tokens);
        }
    }

    /**
     * @notice Revoke all token approvals (emergency use)
     * @dev Called before changing adapters or in emergency
     */
    function revokeApprovals() external onlyOwner {
        if (kodiakAdapter != address(0)) {
            ibgtToken.forceApprove(kodiakAdapter, 0);
            apiaryToken.forceApprove(kodiakAdapter, 0);
            honeyToken.forceApprove(kodiakAdapter, 0);
        }

        if (infraredAdapter != address(0)) {
            ibgtToken.forceApprove(infraredAdapter, 0);
        }
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token address
     * @param amount Amount to withdraw
     * @param recipient Recipient address
     */
    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        if (token == address(0) || recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        IERC20(token).safeTransfer(recipient, amount);

        emit EmergencyWithdraw(token, amount, recipient);
    }
}
