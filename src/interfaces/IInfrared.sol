// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IInfrared
 * @notice Interface for Infrared InfraredVault (MultiRewards-based) on Berachain
 * @dev Matches the real InfraredVault contract interface.
 *
 * Key differences from previous mock interface:
 * - No shares-based accounting — staking is 1:1
 * - Multiple reward tokens (HONEY, wBERA, etc.) via MultiRewards
 * - `withdraw(uint256)` instead of `unstake(uint256)`
 * - `getReward()` instead of `claimRewards()`
 * - `exit()` instead of `emergencyWithdraw()`
 * - `balanceOf(address)` instead of `stakedBalance(address)`
 * - `earned(address, address)` per reward token instead of single `pendingRewards(address)`
 * - `getAllRewardTokens()` returns array of reward token addresses
 */
interface IInfrared {
    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake tokens into the vault
     * @param amount Amount of staking token to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice Withdraw staked tokens from the vault
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Claim all accumulated rewards for all reward tokens
     */
    function getReward() external;

    /**
     * @notice Withdraw all staked tokens and claim all rewards
     * @dev Equivalent to withdraw(balanceOf(msg.sender)) + getReward()
     */
    function exit() external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get staked balance for a user
     * @param account User address
     * @return Staked token balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get total staked supply in the vault
     * @return Total staked amount
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get the staking token address
     * @return Address of the token being staked (e.g., iBGT)
     */
    function stakingToken() external view returns (address);

    /**
     * @notice Get all reward token addresses
     * @return Array of reward token addresses
     */
    function getAllRewardTokens() external view returns (address[] memory);

    /**
     * @notice Get all earned rewards for a user across all reward tokens
     * @param user User address
     * @return rewards Array of (token, amount) tuples
     */
    function getAllRewardsForUser(address user) external view returns (RewardData[] memory rewards);

    /**
     * @notice Get earned (pending) rewards for a user for a specific reward token
     * @param account User address
     * @param rewardToken Reward token address
     * @return Amount of earned rewards
     */
    function earned(address account, address rewardToken) external view returns (uint256);

    /**
     * @notice Get reward per token stored for a specific reward token
     * @param rewardToken Reward token address
     * @return Accumulated reward per token
     */
    function rewardPerToken(address rewardToken) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reward data returned by getAllRewardsForUser
     * @param token Reward token address
     * @param amount Earned reward amount
     */
    struct RewardData {
        address token;
        uint256 amount;
    }
}
