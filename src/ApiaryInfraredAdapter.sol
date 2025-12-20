// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IInfrared } from "./interfaces/IInfrared.sol";

/**
 * @title ApiaryInfraredAdapter
 * @author Apiary Protocol
 * @notice Adapter contract for integrating Apiary with Infrared liquid staking
 * @dev Enables YieldManager to stake iBGT on Infrared and earn yield
 * 
 * FLOW:
 * 1. YieldManager approves this adapter for iBGT
 * 2. YieldManager calls stake() - adapter pulls iBGT, stakes on Infrared
 * 3. YieldManager calls claimRewards() - adapter claims and returns rewards
 * 4. YieldManager calls unstake() - adapter unstakes and returns iBGT
 * 
 * ACCESS CONTROL:
 * - YieldManager: stake/unstake/claimRewards (operational)
 * - Owner: admin functions, emergency actions
 * 
 * SECURITY:
 * - Pull pattern: Adapter pulls tokens from YieldManager (requires approval)
 * - Atomic operations: Each function reverts on failure
 * - Actual balance verification: Don't trust return values blindly
 * - No unlimited approvals in constructor
 * - Emergency withdraw available
 */
contract ApiaryInfraredAdapter is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Infrared staking contract
    IInfrared public immutable infrared;

    /// @notice iBGT token (staked BGT)
    IERC20 public immutable ibgt;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Yield manager address (can stake/unstake/claim)
    address public yieldManager;

    /// @notice Total iBGT staked through this adapter (tracking)
    uint256 public totalStaked;

    /// @notice Total rewards claimed (tracking)
    uint256 public totalRewardsClaimed;

    /// @notice Minimum stake amount (prevents dust)
    uint256 public minStakeAmount;

    /// @notice Minimum unstake amount (prevents dust)
    uint256 public minUnstakeAmount;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_AMOUNT();
    error APIARY__ONLY_YIELD_MANAGER();
    error APIARY__INSUFFICIENT_STAKED();
    error APIARY__INSUFFICIENT_BALANCE();
    error APIARY__NO_REWARDS();
    error APIARY__BELOW_MINIMUM();
    error APIARY__STAKE_FAILED();
    error APIARY__UNSTAKE_FAILED();
    error APIARY__CLAIM_FAILED();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when iBGT is staked on Infrared
    event Staked(uint256 amountRequested, uint256 amountStaked);

    /// @notice Emitted when iBGT is unstaked from Infrared
    event Unstaked(uint256 amountRequested, uint256 amountReceived);

    /// @notice Emitted when rewards are claimed
    event RewardsClaimed(address indexed rewardToken, uint256 amount);

    /// @notice Emitted when yield manager is updated
    event YieldManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when minimum amounts are updated
    event MinimumAmountsUpdated(uint256 minStake, uint256 minUnstake);

    /// @notice Emitted when token approvals are set up
    event ApprovalsSetup(address indexed spender);

    /// @notice Emitted when accounting is synced with actual balance
    event AccountingSynced(uint256 oldValue, uint256 newValue);

    /// @notice Emitted on emergency withdraw
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed recipient);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restrict function to yield manager only
    modifier onlyYieldManager() {
        if (msg.sender != yieldManager) {
            revert APIARY__ONLY_YIELD_MANAGER();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the Infrared adapter
     * @param _infrared Infrared staking contract address
     * @param _ibgt iBGT token address
     * @param _yieldManager Yield manager address (can stake/unstake)
     * @param _admin Owner address
     * @dev Does NOT set unlimited approval - call setupApprovals() after deployment
     */
    constructor(
        address _infrared,
        address _ibgt,
        address _yieldManager,
        address _admin
    ) Ownable(_admin) {
        if (
            _infrared == address(0) ||
            _ibgt == address(0) ||
            _yieldManager == address(0)
        ) {
            revert APIARY__ZERO_ADDRESS();
        }

        infrared = IInfrared(_infrared);
        ibgt = IERC20(_ibgt);
        yieldManager = _yieldManager;

        // Default minimum amounts (0.01 iBGT)
        minStakeAmount = 0.01e18;
        minUnstakeAmount = 0.01e18;

        // NOTE: Call setupApprovals() after deployment to approve Infrared
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake iBGT on Infrared
     * @dev Only callable by yield manager. Uses pull pattern - YieldManager must approve adapter.
     * 
     * Flow:
     * 1. Pull iBGT from YieldManager (caller)
     * 2. Approve Infrared (if needed)
     * 3. Stake iBGT on Infrared
     * 4. Verify stake succeeded
     * 5. Update tracking
     * 
     * @param amount Amount of iBGT to stake
     * @return stakedAmount Actual amount staked (verified)
     */
    function stake(uint256 amount) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 stakedAmount) {
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }
        if (amount < minStakeAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        // 1. Pull iBGT from YieldManager (caller)
        ibgt.safeTransferFrom(msg.sender, address(this), amount);

        // 2. Approve Infrared if needed
        _approveIfNeeded(address(ibgt), address(infrared), amount);

        // 3. Get staked balance before
        uint256 stakedBefore = _getStakedBalance();

        // 4. Stake on Infrared
        infrared.stake(amount);

        // 5. Get staked balance after and verify
        uint256 stakedAfter = _getStakedBalance();
        stakedAmount = stakedAfter - stakedBefore;

        if (stakedAmount == 0) {
            revert APIARY__STAKE_FAILED();
        }

        // 6. Update tracking
        totalStaked += stakedAmount;

        emit Staked(amount, stakedAmount);
    }

    /**
     * @notice Unstake iBGT from Infrared
     * @dev Only callable by yield manager. Returns iBGT to caller.
     * 
     * Flow:
     * 1. Verify sufficient staked balance
     * 2. Unstake from Infrared
     * 3. Verify iBGT received
     * 4. Transfer iBGT to YieldManager (caller)
     * 5. Update tracking
     * 
     * @param amount Amount of iBGT to unstake
     * @return unstakedAmount Actual amount received (may differ due to fees)
     */
    function unstake(uint256 amount) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 unstakedAmount) {
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }
        if (amount < minUnstakeAmount) {
            revert APIARY__BELOW_MINIMUM();
        }
        if (amount > totalStaked) {
            revert APIARY__INSUFFICIENT_STAKED();
        }

        // 1. Get iBGT balance before
        uint256 balanceBefore = ibgt.balanceOf(address(this));

        // 2. Unstake from Infrared
        infrared.unstake(amount);

        // 3. Get iBGT balance after
        uint256 balanceAfter = ibgt.balanceOf(address(this));
        unstakedAmount = balanceAfter - balanceBefore;

        if (unstakedAmount == 0) {
            revert APIARY__UNSTAKE_FAILED();
        }

        // 4. Update tracking (use requested amount for consistency)
        totalStaked -= amount;

        // 5. Transfer iBGT back to YieldManager (caller)
        ibgt.safeTransfer(msg.sender, unstakedAmount);

        emit Unstaked(amount, unstakedAmount);
    }

    /**
     * @notice Claim pending rewards from Infrared
     * @dev Only callable by yield manager. Returns rewards to caller.
     * Simplified: No auto-compound - YieldManager decides what to do with rewards.
     * 
     * Flow:
     * 1. Get reward token from Infrared
     * 2. Get balance before
     * 3. Claim from Infrared
     * 4. Verify rewards received
     * 5. Transfer rewards to YieldManager (caller)
     * 
     * @return rewardAmount Amount of rewards claimed
     */
    function claimRewards() external onlyYieldManager whenNotPaused nonReentrant returns (uint256 rewardAmount) {
        // 1. Get reward token from Infrared
        address rewardToken = infrared.rewardToken();

        // 2. Get balance before
        uint256 balanceBefore = IERC20(rewardToken).balanceOf(address(this));

        // 3. Claim from Infrared
        infrared.claimRewards();

        // 4. Get balance after
        uint256 balanceAfter = IERC20(rewardToken).balanceOf(address(this));
        rewardAmount = balanceAfter - balanceBefore;

        // 5. Update tracking
        totalRewardsClaimed += rewardAmount;

        // 6. Transfer rewards to YieldManager (caller) if any
        if (rewardAmount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, rewardAmount);
        }

        emit RewardsClaimed(rewardToken, rewardAmount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approve token spending if current allowance is insufficient
     * @param token Token to approve
     * @param spender Spender address
     * @param amount Amount needed
     */
    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
        if (currentAllowance < amount) {
            // Reset to 0 first (required by some tokens like USDT)
            if (currentAllowance > 0) {
                IERC20(token).approve(spender, 0);
            }
            IERC20(token).approve(spender, amount);
        }
    }

    /**
     * @notice Get actual staked balance from Infrared
     * @return Staked iBGT balance
     */
    function _getStakedBalance() internal view returns (uint256) {
        return infrared.stakedBalance(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update yield manager address
     * @param _yieldManager New yield manager address
     */
    function setYieldManager(address _yieldManager) external onlyOwner {
        if (_yieldManager == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldManager = yieldManager;
        yieldManager = _yieldManager;

        emit YieldManagerUpdated(oldManager, _yieldManager);
    }

    /**
     * @notice Update minimum stake/unstake amounts
     * @param _minStake Minimum stake amount
     * @param _minUnstake Minimum unstake amount
     */
    function setMinimumAmounts(uint256 _minStake, uint256 _minUnstake) external onlyOwner {
        minStakeAmount = _minStake;
        minUnstakeAmount = _minUnstake;
        emit MinimumAmountsUpdated(_minStake, _minUnstake);
    }

    /**
     * @notice Set up unlimited approval to Infrared
     * @dev Call after deployment. Can be called again if approval needs refresh.
     */
    function setupApprovals() external onlyOwner {
        ibgt.approve(address(infrared), type(uint256).max);
        emit ApprovalsSetup(address(infrared));
    }

    /**
     * @notice Revoke all approvals (for emergency or before upgrade)
     */
    function revokeApprovals() external onlyOwner {
        ibgt.approve(address(infrared), 0);
    }

    /**
     * @notice Sync accounting with actual staked balance
     * @dev Use if accounting drifts due to external changes
     */
    function syncAccounting() external onlyOwner {
        uint256 actualStaked = _getStakedBalance();
        uint256 oldTracked = totalStaked;
        totalStaked = actualStaked;
        emit AccountingSynced(oldTracked, actualStaked);
    }

    /**
     * @notice Pause the adapter (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the adapter
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw all staked iBGT
     * @dev Uses Infrared's emergency withdraw (may incur penalty). Sends to owner.
     */
    function emergencyUnstakeAll() external onlyOwner {
        uint256 stakedBal = infrared.stakedBalance(address(this));

        if (stakedBal == 0) {
            revert APIARY__INSUFFICIENT_STAKED();
        }

        // Emergency withdraw from Infrared
        infrared.emergencyWithdraw();

        // Get iBGT balance after withdraw
        uint256 ibgtBalance = ibgt.balanceOf(address(this));

        // Transfer to owner
        if (ibgtBalance > 0) {
            ibgt.safeTransfer(msg.sender, ibgtBalance);
        }

        // Reset total staked
        totalStaked = 0;

        emit EmergencyWithdraw(address(ibgt), ibgtBalance, msg.sender);
    }

    /**
     * @notice Emergency token recovery
     * @dev Recover accidentally sent tokens to owner
     * @param token Token address
     * @param amount Amount to recover
     * @param to Recipient address
     */
    function emergencyWithdrawToken(address token, uint256 amount, address to) external onlyOwner {
        if (token == address(0) || to == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) {
            revert APIARY__INSUFFICIENT_BALANCE();
        }

        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdraw(token, amount, to);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending rewards for this adapter
     * @return Amount of pending rewards
     */
    function pendingRewards() external view returns (uint256) {
        return infrared.pendingRewards(address(this));
    }

    /**
     * @notice Get actual staked balance on Infrared
     * @return Amount of iBGT staked (from Infrared)
     */
    function getStakedBalance() external view returns (uint256) {
        return _getStakedBalance();
    }

    /**
     * @notice Get iBGT balance held in adapter (should be 0 normally)
     * @return Amount of iBGT in adapter
     */
    function getIBGTBalance() external view returns (uint256) {
        return ibgt.balanceOf(address(this));
    }

    /**
     * @notice Get shares balance on Infrared
     * @return Amount of shares owned
     */
    function sharesBalance() external view returns (uint256) {
        return infrared.sharesOf(address(this));
    }

    /**
     * @notice Get stake information from Infrared
     * @return StakeInfo struct with staking details
     */
    function getStakeInfo() external view returns (IInfrared.StakeInfo memory) {
        return infrared.getStakeInfo(address(this));
    }

    /**
     * @notice Get Infrared protocol info
     * @return ibgtToken iBGT token address
     * @return rewardTokenAddress Reward token address
     * @return totalStakedInProtocol Total iBGT staked in Infrared
     * @return lockupPeriod Lockup duration (0 if none)
     * @return unstakeFee Unstake fee in basis points
     */
    function getInfraredInfo() external view returns (
        address ibgtToken,
        address rewardTokenAddress,
        uint256 totalStakedInProtocol,
        uint256 lockupPeriod,
        uint256 unstakeFee
    ) {
        ibgtToken = address(ibgt);
        rewardTokenAddress = infrared.rewardToken();
        totalStakedInProtocol = infrared.totalStaked();
        lockupPeriod = infrared.lockupPeriod();
        unstakeFee = infrared.unstakeFee();
    }

    /**
     * @notice Get adapter configuration
     * @return yieldManagerAddress Yield manager address
     * @return totalStakedAmount Total staked through adapter (tracking)
     * @return totalRewards Total rewards claimed
     * @return minStake Minimum stake amount
     * @return minUnstake Minimum unstake amount
     */
    function getAdapterInfo() external view returns (
        address yieldManagerAddress,
        uint256 totalStakedAmount,
        uint256 totalRewards,
        uint256 minStake,
        uint256 minUnstake
    ) {
        yieldManagerAddress = yieldManager;
        totalStakedAmount = totalStaked;
        totalRewards = totalRewardsClaimed;
        minStake = minStakeAmount;
        minUnstake = minUnstakeAmount;
    }

    /**
     * @notice Check if adapter can stake a given amount
     * @param amount Amount to check
     * @return True if amount meets minimum and adapter is active
     */
    function canStake(uint256 amount) external view returns (bool) {
        return amount >= minStakeAmount && !paused();
    }

    /**
     * @notice Check if adapter can unstake a given amount
     * @param amount Amount to check
     * @return True if amount meets minimum, is staked, and adapter is active
     */
    function canUnstake(uint256 amount) external view returns (bool) {
        return amount >= minUnstakeAmount && amount <= totalStaked && !paused();
    }
}
