// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ApiaryStaking
 * @notice Staking contract for Apiary protocol — farm/reward pool model
 * @dev Users stake APIARY and earn APIARY rewards distributed pro rata.
 *      Based on the Synthetix StakingRewards pattern.
 *
 *      Yield flow:
 *      1. YieldManager swaps yield for APIARY
 *      2. YieldManager calls notifyRewardAmount(amount)
 *      3. Rewards stream to stakers over REWARDS_DURATION (7 days)
 *      4. Users call claim() or compound() to collect rewards
 */
contract ApiaryStaking is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable APIARY;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration over which rewards are distributed (7 days)
    uint256 public constant REWARDS_DURATION = 7 days;

    /*//////////////////////////////////////////////////////////////
                        REWARD STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp when current reward period ends
    uint256 public periodFinish;

    /// @notice APIARY distributed per second during active reward period
    uint256 public rewardRate;

    /// @notice Last time rewardPerTokenStored was updated
    uint256 public lastUpdateTime;

    /// @notice Accumulated reward per staked token (scaled by 1e18)
    uint256 public rewardPerTokenStored;

    /// @notice Snapshot of rewardPerToken for each user at last action
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Accumulated unclaimed rewards for each user
    mapping(address => uint256) public rewards;

    /*//////////////////////////////////////////////////////////////
                        STAKING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Total APIARY staked across all users
    uint256 public totalStaked;

    /// @notice Individual staked balance per user
    mapping(address => uint256) public balanceOf;

    /// @notice Address authorized to notify new rewards (yield manager)
    address public rewardsDistributor;

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event Compounded(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);
    event RewardsDistributorUpdated(address indexed distributor);

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__INVALID_ADDRESS();
    error APIARY__INVALID_AMOUNT();
    error APIARY__INSUFFICIENT_BALANCE();
    error APIARY__NOT_REWARDS_DISTRIBUTOR();
    error APIARY__REWARD_TOO_HIGH();

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the staking contract
     * @param _apiary Address of the APIARY token
     * @param _initialOwner Address of the initial owner
     */
    constructor(
        address _apiary,
        address _initialOwner
    ) Ownable(_initialOwner) {
        if (_apiary == address(0)) revert APIARY__INVALID_ADDRESS();
        APIARY = _apiary;
    }

    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake APIARY tokens to earn rewards
     * @param amount Amount of APIARY to stake
     */
    function stake(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        updateReward(msg.sender)
    {
        if (amount == 0) revert APIARY__INVALID_AMOUNT();

        IERC20(APIARY).safeTransferFrom(msg.sender, address(this), amount);

        totalStaked += amount;
        balanceOf[msg.sender] += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake APIARY tokens
     * @param amount Amount of APIARY to unstake
     */
    function unstake(uint256 amount)
        external
        whenNotPaused
        nonReentrant
        updateReward(msg.sender)
    {
        if (amount == 0) revert APIARY__INVALID_AMOUNT();
        if (balanceOf[msg.sender] < amount) revert APIARY__INSUFFICIENT_BALANCE();

        totalStaked -= amount;
        balanceOf[msg.sender] -= amount;

        IERC20(APIARY).safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claim accumulated APIARY rewards
     * @return reward Amount of APIARY claimed
     */
    function claim()
        external
        whenNotPaused
        nonReentrant
        updateReward(msg.sender)
        returns (uint256 reward)
    {
        reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(APIARY).safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }

    /**
     * @notice Compound rewards — claim and restake in one transaction
     * @return reward Amount of APIARY compounded
     */
    function compound()
        external
        whenNotPaused
        nonReentrant
        updateReward(msg.sender)
        returns (uint256 reward)
    {
        reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            totalStaked += reward;
            balanceOf[msg.sender] += reward;
            emit Compounded(msg.sender, reward);
        }
    }

    /**
     * @notice Unstake all and claim rewards in one transaction
     */
    function exit() external {
        // unstake and claim are both nonReentrant, so call internal versions
        _unstakeAll();
        _claimRewards();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Last timestamp where rewards are applicable
     * @return Minimum of current time and period end
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Current reward per staked token (scaled by 1e18)
     * @return Accumulated reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalStaked
        );
    }

    /**
     * @notice Calculate pending rewards for a user
     * @param account User address
     * @return Pending APIARY reward amount
     */
    function earned(address account) public view returns (uint256) {
        return (
            balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18
        ) + rewards[account];
    }

    /**
     * @notice Total rewards to be distributed in current period
     * @return Total APIARY for the full rewards duration
     */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * REWARDS_DURATION;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notify contract about new rewards to distribute
     * @dev Called by yield manager after transferring APIARY to this contract
     * @param reward Amount of APIARY to distribute over REWARDS_DURATION
     */
    function notifyRewardAmount(uint256 reward)
        external
        updateReward(address(0))
    {
        if (msg.sender != rewardsDistributor && msg.sender != owner()) {
            revert APIARY__NOT_REWARDS_DISTRIBUTOR();
        }

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / REWARDS_DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / REWARDS_DURATION;
        }

        // Prevent setting reward rate higher than balance can support
        uint256 balance = IERC20(APIARY).balanceOf(address(this)) - totalStaked;
        if (rewardRate > balance / REWARDS_DURATION) {
            revert APIARY__REWARD_TOO_HIGH();
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;

        emit RewardAdded(reward);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the rewards distributor address (yield manager)
     * @param _distributor Address of the yield manager
     */
    function setRewardsDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) revert APIARY__INVALID_ADDRESS();
        rewardsDistributor = _distributor;
        emit RewardsDistributorUpdated(_distributor);
    }

    /// @notice Pause the contract (emergency use only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to retrieve accidentally sent tokens
     * @dev Cannot withdraw staked APIARY or pending rewards
     * @param token Address of token to retrieve
     * @param amount Amount to retrieve
     */
    function retrieve(address token, uint256 amount) external onlyOwner {
        if (token == APIARY) {
            uint256 apiaryBalance = IERC20(APIARY).balanceOf(address(this));
            uint256 obligation = totalStaked;
            // Also protect unclaimed rewards in the contract
            if (block.timestamp < periodFinish) {
                obligation += (periodFinish - block.timestamp) * rewardRate;
            }
            uint256 excess = apiaryBalance > obligation ? apiaryBalance - obligation : 0;
            require(amount <= excess, "ApiaryStaking: cannot drain staked or reward funds");
        }

        if (token != address(0) && amount > 0) {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /// @notice Recover accidentally sent ETH
    function retrieveETH() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "ApiaryStaking: no ETH to retrieve");
        (bool success,) = payable(msg.sender).call{ value: ethBalance }("");
        require(success, "ApiaryStaking: ETH transfer failed");
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _unstakeAll() internal whenNotPaused nonReentrant updateReward(msg.sender) {
        uint256 amount = balanceOf[msg.sender];
        if (amount > 0) {
            totalStaked -= amount;
            balanceOf[msg.sender] = 0;
            IERC20(APIARY).safeTransfer(msg.sender, amount);
            emit Unstaked(msg.sender, amount);
        }
    }

    function _claimRewards() internal whenNotPaused updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(APIARY).safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }
}
