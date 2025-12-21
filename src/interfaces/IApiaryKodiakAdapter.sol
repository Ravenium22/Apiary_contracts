// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IKodiakFarm } from "./IKodiakFarm.sol";

/**
 * @title IApiaryKodiakAdapter
 * @notice Interface for the Apiary Kodiak DEX adapter with locked staking support
 * @dev Used by YieldManager for swaps, liquidity provision, and LP staking
 *
 * LOCKED STAKING MODEL:
 * - Each stake creates a unique kek_id that must be tracked for withdrawal
 * - Lock duration is configurable per LP token (set by admin)
 * - Longer locks = higher reward multipliers
 * - Cannot withdraw until lock expires (unless farm has stakesUnlocked enabled)
 */
interface IApiaryKodiakAdapter {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Swapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed recipient
    );

    event LPStaked(
        address indexed lpToken,
        address indexed farm,
        uint256 amount,
        bytes32 indexed kekId,
        uint256 lockDuration
    );

    event LPUnstaked(
        address indexed lpToken,
        address indexed farm,
        uint256 amount,
        bytes32 indexed kekId
    );

    event AllExpiredLPUnstaked(
        address indexed lpToken,
        address indexed farm,
        uint256 totalAmount,
        uint256 stakesWithdrawn
    );

    event RewardsClaimed(
        address indexed lpToken,
        address indexed farm,
        address[] rewardTokens,
        uint256[] rewardAmounts
    );

    event FarmRegistered(address indexed lpToken, address indexed farm);
    event LockDurationUpdated(address indexed lpToken, uint256 oldDuration, uint256 newDuration);

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    function swapWithDeadline(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapMultiHop(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLP,
        address recipient
    ) external returns (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB,
        address recipient
    ) external returns (uint256 amountA, uint256 amountB);

    /*//////////////////////////////////////////////////////////////
                        LP STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake LP tokens with locked staking
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to stake
     * @return kekId Unique identifier for this stake position
     */
    function stakeLP(address lpToken, uint256 amount) external returns (bytes32 kekId);

    /**
     * @notice Unstake a specific locked stake by kek_id
     * @param lpToken LP token address
     * @param kekId The unique identifier of the stake to withdraw
     * @return amount Amount of LP tokens withdrawn
     */
    function unstakeLP(address lpToken, bytes32 kekId) external returns (uint256 amount);

    /**
     * @notice Unstake a specific locked stake to a recipient
     * @param lpToken LP token address
     * @param kekId The unique identifier of the stake to withdraw
     * @param recipient Address to receive unstaked LP tokens
     * @return amount Amount of LP tokens withdrawn
     */
    function unstakeLPTo(address lpToken, bytes32 kekId, address recipient) external returns (uint256 amount);

    /**
     * @notice Withdraw all expired stakes for an LP token
     * @param lpToken LP token address
     * @return totalAmount Total LP tokens withdrawn
     */
    function unstakeAllExpired(address lpToken) external returns (uint256 totalAmount);

    /**
     * @notice Withdraw all expired stakes to a recipient
     * @param lpToken LP token address
     * @param recipient Address to receive unstaked LP tokens
     * @return totalAmount Total LP tokens withdrawn
     */
    function unstakeAllExpiredTo(address lpToken, address recipient) external returns (uint256 totalAmount);

    /**
     * @notice Claim rewards (sends to caller)
     * @param lpToken LP token address
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of reward amounts claimed
     */
    function claimLPRewards(address lpToken) external returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /**
     * @notice Claim rewards to specific recipient
     * @param lpToken LP token address
     * @param recipient Address to receive rewards
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of reward amounts claimed
     */
    function claimLPRewardsTo(address lpToken, address recipient) external returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get expected swap output
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Alias for getAmountOut
    function getExpectedSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Quote LP tokens for adding liquidity
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external view returns (uint256 expectedLP);

    /// @notice Get LP token address for pair
    function getLPToken(address tokenA, address tokenB) external view returns (address lpToken);

    /// @notice Check if pool exists
    function poolExists(address tokenA, address tokenB) external view returns (bool exists);

    /// @notice Get farm address for LP token
    function lpToFarm(address lpToken) external view returns (address farm);

    /// @notice Get farm address for LP token (backward compatible alias)
    function lpToGauge(address lpToken) external view returns (address farm);

    /// @notice Get total staked LP for LP token
    function totalStakedLP(address lpToken) external view returns (uint256 amount);

    /// @notice Get yield manager address
    function yieldManager() external view returns (address);

    /// @notice Get treasury address
    function treasury() external view returns (address);

    /// @notice Get default slippage
    function defaultSlippageBps() external view returns (uint256);

    /// @notice Get staked balance (total locked liquidity)
    function getStakedBalance(address lpToken) external view returns (uint256 balance);

    /// @notice Get all stake IDs for an LP token
    function getStakeIds(address lpToken) external view returns (bytes32[] memory);

    /// @notice Get detailed stake info by kek_id
    function getStakeInfo(address lpToken, bytes32 kekId) external view returns (IKodiakFarm.LockedStake memory stake);

    /// @notice Get all expired stakes that can be withdrawn
    function getExpiredStakes(address lpToken) external view returns (bytes32[] memory expiredKekIds, uint256 totalExpiredLiquidity);

    /// @notice Get pending rewards
    function getPendingRewards(address lpToken) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /// @notice Get farm configuration info
    function getFarmConfig(address lpToken) external view returns (
        uint256 minLock,
        uint256 maxMultiplierLock,
        uint256 maxMultiplier,
        bool isPaused,
        bool areStakesUnlocked
    );

    /// @notice Get lock multiplier for a duration
    function getLockMultiplier(address lpToken, uint256 secs) external view returns (uint256 multiplier);

    /// @notice Get combined weight (includes multipliers)
    function getCombinedWeight(address lpToken) external view returns (uint256 weight);

    /// @notice Get configured lock duration
    function getLockDuration(address lpToken) external view returns (uint256);

    /// @notice Calculate min output with slippage
    function calculateMinOutput(uint256 amount, uint256 slippageBps) external pure returns (uint256 minAmount);

    /// @notice Get adapter info
    function getAdapterInfo() external view returns (
        address _yieldManager,
        address _treasury,
        uint256 _totalSwaps,
        uint256 _totalLiquidityOps,
        uint256 _totalRewards
    );

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a farm for LP staking
    function registerFarm(address lpToken, address farm) external;

    /// @notice Alias for registerFarm (backward compatibility)
    function registerGauge(address lpToken, address farm) external;

    /// @notice Set lock duration for staking
    function setLockDuration(address lpToken, uint256 _seconds) external;

    /// @notice Check if a kek_id belongs to this adapter
    function isOurStake(bytes32 kekId) external view returns (bool);

    /// @notice Get LP token for a stake ID
    function stakeIdToLP(bytes32 kekId) external view returns (address);

    /// @notice Get configured lock duration for LP token
    function lpLockDuration(address lpToken) external view returns (uint256);
}
