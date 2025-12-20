// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IApiaryInfraredAdapter
 * @author Apiary Protocol
 * @notice Interface for the Apiary Infrared adapter
 * @dev Used by YieldManager to stake iBGT on Infrared and earn yield
 * 
 * FLOW:
 * 1. YieldManager approves adapter for iBGT
 * 2. YieldManager calls stake() - adapter pulls iBGT, stakes on Infrared
 * 3. YieldManager calls claimRewards() - adapter claims and returns rewards
 * 4. YieldManager calls unstake() - adapter unstakes and returns iBGT
 */
interface IApiaryInfraredAdapter {
    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake iBGT on Infrared
     * @dev Pulls iBGT from caller (YieldManager must approve adapter first)
     * @param amount Amount of iBGT to stake
     * @return stakedAmount Actual amount staked (verified from Infrared)
     */
    function stake(uint256 amount) external returns (uint256 stakedAmount);

    /**
     * @notice Unstake iBGT from Infrared
     * @dev Returns iBGT to caller (YieldManager)
     * @param amount Amount of iBGT to unstake
     * @return unstakedAmount Actual amount received (may differ due to fees)
     */
    function unstake(uint256 amount) external returns (uint256 unstakedAmount);

    /**
     * @notice Claim pending rewards from Infrared
     * @dev Returns rewards to caller (YieldManager)
     * @return rewardAmount Amount of rewards claimed and transferred
     */
    function claimRewards() external returns (uint256 rewardAmount);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending rewards for this adapter
     * @return Amount of pending rewards from Infrared
     */
    function pendingRewards() external view returns (uint256);

    /**
     * @notice Get tracked total staked amount
     * @return Amount of iBGT staked through this adapter (internal tracking)
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Get total rewards claimed historically
     * @return Total rewards claimed
     */
    function totalRewardsClaimed() external view returns (uint256);

    /**
     * @notice Get actual staked balance from Infrared
     * @return Amount of iBGT staked (queried from Infrared)
     */
    function getStakedBalance() external view returns (uint256);

    /**
     * @notice Get iBGT balance held in adapter
     * @return Amount of iBGT in adapter (should be 0 normally)
     */
    function getIBGTBalance() external view returns (uint256);

    /**
     * @notice Get yield manager address
     * @return Yield manager address
     */
    function yieldManager() external view returns (address);

    /**
     * @notice Check if adapter can stake a given amount
     * @param amount Amount to check
     * @return True if amount meets minimum and adapter is active
     */
    function canStake(uint256 amount) external view returns (bool);

    /**
     * @notice Check if adapter can unstake a given amount
     * @param amount Amount to check
     * @return True if amount meets minimum, is staked, and adapter is active
     */
    function canUnstake(uint256 amount) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update yield manager address
     * @param _yieldManager New yield manager address
     */
    function setYieldManager(address _yieldManager) external;

    /**
     * @notice Set up approvals for Infrared
     * @dev Call after deployment
     */
    function setupApprovals() external;

    /**
     * @notice Sync internal accounting with actual Infrared balance
     */
    function syncAccounting() external;

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token address
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function emergencyWithdrawToken(address token, uint256 amount, address to) external;

    /**
     * @notice Emergency unstake all from Infrared
     */
    function emergencyUnstakeAll() external;
}
