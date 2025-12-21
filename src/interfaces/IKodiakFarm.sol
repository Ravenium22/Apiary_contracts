// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IKodiakFarm
 * @notice Interface for Kodiak Farm locked staking contracts on Berachain
 * @dev Kodiak Farms use a LOCKED staking model where:
 *      - Each stake is locked for a specified duration (between lock_time_min and lock_time_for_max_multiplier)
 *      - Each stake receives a unique kek_id (bytes32) generated on-chain
 *      - Longer lock durations = higher reward multipliers (up to lock_max_multiplier)
 *      - The kek_id must be tracked to withdraw specific stakes
 *      - Multiple stakes can exist simultaneously for the same user
 *
 * Staking Flow:
 *   1. User calls stakeLocked(amount, lockDuration) with approved LP tokens
 *   2. Contract emits StakeLocked event containing the generated kek_id
 *   3. User must track this kek_id for later withdrawal
 *   4. After lock expires, user calls withdrawLocked(kek_id) to retrieve LP + rewards
 *
 * Reward Tokens:
 *   - Farms can distribute multiple reward tokens (xKDK, BGT, etc.)
 *   - earned() and getReward() return arrays corresponding to getAllRewardTokens()
 */
interface IKodiakFarm {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents a single locked stake position
     * @param kek_id Unique identifier for this stake (generated on-chain)
     * @param start_timestamp When the stake was created
     * @param liquidity Amount of LP tokens staked
     * @param ending_timestamp When the lock expires (start + lock duration)
     * @param lock_multiplier Reward multiplier based on lock duration (1e18 = 1x)
     */
    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
        uint256 lock_multiplier;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when LP tokens are staked with a lock
     * @param user Address that staked
     * @param liquidity Amount of LP tokens staked
     * @param secs Lock duration in seconds
     * @param kek_id Unique identifier for this stake - MUST BE TRACKED FOR WITHDRAWAL
     * @param source Address that initiated the stake
     */
    event StakeLocked(
        address indexed user,
        uint256 liquidity,
        uint256 secs,
        bytes32 kek_id,
        address source
    );

    /**
     * @notice Emitted when a locked stake is withdrawn
     * @param user Address that withdrew
     * @param liquidity Amount of LP tokens withdrawn
     * @param kek_id Unique identifier of the withdrawn stake
     */
    event WithdrawLocked(
        address indexed user,
        uint256 liquidity,
        bytes32 kek_id,
        address destination
    );

    /**
     * @notice Emitted when rewards are claimed
     * @param user Address that claimed
     * @param rewardToken Address of the reward token
     * @param amount Amount of rewards claimed
     * @param destination Address rewards were sent to
     */
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 amount,
        address destination
    );

    /*//////////////////////////////////////////////////////////////
                            STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake LP tokens with a lock period
     * @dev Emits StakeLocked event containing the kek_id - MUST track this for withdrawal
     * @param liquidity Amount of LP tokens to stake
     * @param secs Lock duration in seconds (must be >= lock_time_min)
     * @return kek_id The unique identifier for this stake position
     *
     * Lock Duration Effects:
     * - lock_time_min: Minimum allowed, gives base multiplier
     * - lock_time_for_max_multiplier: Gives maximum multiplier (lock_max_multiplier)
     * - Durations between these interpolate the multiplier
     */
    function stakeLocked(uint256 liquidity, uint256 secs) external returns (bytes32 kek_id);

    /**
     * @notice Withdraw a specific locked stake after its lock expires
     * @dev Reverts if lock has not expired (unless stakesUnlocked is true)
     * @param kek_id The unique identifier of the stake to withdraw
     */
    function withdrawLocked(bytes32 kek_id) external;

    /**
     * @notice Withdraw all expired locked stakes at once
     * @dev Only withdraws stakes where ending_timestamp has passed
     */
    function withdrawLockedAll() external;

    /**
     * @notice Withdraw multiple specific locked stakes
     * @dev More gas efficient than calling withdrawLocked multiple times
     * @param kek_ids Array of stake identifiers to withdraw
     */
    function withdrawLockedMultiple(bytes32[] calldata kek_ids) external;

    /**
     * @notice Emergency withdraw a stake before lock expires
     * @dev May incur a penalty depending on farm configuration
     * @param kek_id The unique identifier of the stake to emergency withdraw
     */
    function emergencyWithdraw(bytes32 kek_id) external;

    /**
     * @notice Claim all pending rewards across all reward tokens
     * @return rewardAmounts Array of reward amounts (one per reward token)
     *         Indices correspond to getAllRewardTokens() ordering
     */
    function getReward() external returns (uint256[] memory rewardAmounts);

    /*//////////////////////////////////////////////////////////////
                        USER VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total locked LP tokens for an account
     * @param account Address to check
     * @return Total LP tokens locked across all stakes
     */
    function lockedLiquidityOf(address account) external view returns (uint256);

    /**
     * @notice Get all locked stake positions for an account
     * @dev Use this to enumerate kek_ids for withdrawal
     * @param account Address to check
     * @return Array of LockedStake structs containing all stake details
     */
    function lockedStakesOf(address account) external view returns (LockedStake[] memory);

    /**
     * @notice Get pending reward amounts for an account
     * @param account Address to check
     * @return Array of pending reward amounts (one per reward token)
     *         Indices correspond to getAllRewardTokens() ordering
     */
    function earned(address account) external view returns (uint256[] memory);

    /**
     * @notice Get combined weight for an account including lock multipliers
     * @dev Weight = sum of (liquidity * lock_multiplier) for each stake
     * @param account Address to check
     * @return Combined weight value
     */
    function combinedWeightOf(address account) external view returns (uint256);

    /**
     * @notice Calculate the lock multiplier for a given duration
     * @param secs Lock duration in seconds
     * @return multiplier The reward multiplier (1e18 = 1x, 2e18 = 2x, etc.)
     */
    function lockMultiplier(uint256 secs) external view returns (uint256 multiplier);

    /*//////////////////////////////////////////////////////////////
                        REWARD TOKEN VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all reward token addresses
     * @return Array of reward token addresses (xKDK, BGT, etc.)
     */
    function getAllRewardTokens() external view returns (address[] memory);

    /**
     * @notice Get all reward rates (tokens per second)
     * @return Array of reward rates (indices match getAllRewardTokens())
     */
    function getAllRewardRates() external view returns (uint256[] memory);

    /*//////////////////////////////////////////////////////////////
                        CONFIG VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the LP token address this farm accepts
     * @return Address of the staking (LP) token
     */
    function stakingToken() external view returns (address);

    /**
     * @notice Get minimum lock time in seconds
     * @return Minimum seconds a stake must be locked
     */
    function lock_time_min() external view returns (uint256);

    /**
     * @notice Get lock time required for maximum multiplier
     * @return Seconds of lock time to get lock_max_multiplier
     */
    function lock_time_for_max_multiplier() external view returns (uint256);

    /**
     * @notice Get maximum lock multiplier value
     * @dev Returned as fixed point with 1e18 = 1x multiplier
     * @return Maximum multiplier achievable (e.g., 3e18 = 3x)
     */
    function lock_max_multiplier() external view returns (uint256);

    /**
     * @notice Check if new staking is paused
     * @return True if staking is currently paused
     */
    function stakingPaused() external view returns (bool);

    /**
     * @notice Check if reward collection is paused
     * @return True if getReward() is currently paused
     */
    function rewardsCollectionPaused() external view returns (bool);

    /**
     * @notice Check if stakes are unlocked (can withdraw anytime)
     * @dev When true, withdrawLocked() works even before ending_timestamp
     * @return True if early withdrawal is allowed without penalty
     */
    function stakesUnlocked() external view returns (bool);

    /**
     * @notice Get total LP tokens locked in the farm
     * @return Total locked liquidity across all users
     */
    function totalLiquidityLocked() external view returns (uint256);

    /**
     * @notice Get when the current reward period ends
     * @return Unix timestamp when rewards stop accumulating
     */
    function periodFinish() external view returns (uint256);
}
