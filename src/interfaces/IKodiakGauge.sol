// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IKodiakGauge
 * @notice Interface for Kodiak LP staking/gauge contracts
 * @dev Gauges allow staking LP tokens to earn xKDK and BGT rewards
 */
interface IKodiakGauge {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);

    /*//////////////////////////////////////////////////////////////
                            STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake LP tokens in gauge
     * @param amount Amount of LP tokens to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice Stake LP tokens on behalf of another address
     * @param amount Amount of LP tokens to stake
     * @param recipient Address to credit the stake to
     */
    function stakeFor(uint256 amount, address recipient) external;

    /**
     * @notice Withdraw staked LP tokens
     * @param amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Claim accumulated rewards
     * @dev Claims all available reward tokens (xKDK, BGT, etc.)
     */
    function getReward() external;

    /**
     * @notice Claim rewards on behalf of another address
     * @param account Address to claim rewards for
     */
    function getReward(address account) external;

    /**
     * @notice Exit gauge (withdraw all and claim rewards)
     */
    function exit() external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get staked balance for an account
     * @param account Address to check
     * @return Staked LP token balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get total staked in gauge
     * @return Total LP tokens staked
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get earned rewards for a specific token
     * @param account Address to check
     * @param rewardToken Address of reward token
     * @return Amount of rewards earned
     */
    function earned(address account, address rewardToken) external view returns (uint256);

    /**
     * @notice Get LP token address
     * @return Address of LP token this gauge accepts
     */
    function stakingToken() external view returns (address);

    /**
     * @notice Get reward token at specific index
     * @param index Index of reward token
     * @return Address of reward token
     */
    function rewardTokens(uint256 index) external view returns (address);

    /**
     * @notice Get number of reward tokens
     * @return Number of reward tokens
     */
    function rewardTokensLength() external view returns (uint256);

    /**
     * @notice Get reward rate for a specific token
     * @param rewardToken Address of reward token
     * @return Reward rate per second
     */
    function rewardRate(address rewardToken) external view returns (uint256);

    /**
     * @notice Get reward duration
     * @return Duration rewards are distributed over
     */
    function rewardsDuration() external view returns (uint256);

    /**
     * @notice Get last time rewards were updated
     * @return Unix timestamp of last update
     */
    function lastUpdateTime() external view returns (uint256);

    /**
     * @notice Get period finish time for rewards
     * @return Unix timestamp when current reward period ends
     */
    function periodFinish() external view returns (uint256);
}
