// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryStaking } from "../src/ApiaryStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApiaryStakingTest
 * @notice Test suite for the SynthetixRewards-style ApiaryStaking contract
 *
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Staking & Unstaking
 * 3. Reward Distribution & Earning
 * 4. Proportional Rewards (multi-user)
 * 5. Compound
 * 6. notifyRewardAmount (extend period)
 * 7. Access Control
 * 8. Retrieve (fund protection)
 * 9. Exit
 * 10. Edge Cases & Fuzz
 */

/*//////////////////////////////////////////////////////////////
                        MOCK ERC20
//////////////////////////////////////////////////////////////*/

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "MockERC20: insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "MockERC20: insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "MockERC20: insufficient allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        return true;
    }
}

/*//////////////////////////////////////////////////////////////
                        TEST CONTRACT
//////////////////////////////////////////////////////////////*/

contract ApiaryStakingTest is Test {
    ApiaryStaking public staking;
    MockERC20 public apiary;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public distributor = makeAddr("distributor");
    address public attacker = makeAddr("attacker");

    uint256 constant REWARDS_DURATION = 7 days;

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
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        apiary = new MockERC20("Apiary", "APIARY", 9);

        vm.prank(owner);
        staking = new ApiaryStaking(address(apiary), owner);

        // Set distributor
        vm.prank(owner);
        staking.setRewardsDistributor(distributor);

        // Mint tokens to users
        apiary.mint(user1, 100_000e9);
        apiary.mint(user2, 100_000e9);

        // Approve staking
        vm.prank(user1);
        apiary.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        apiary.approve(address(staking), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER: fund & notify rewards
    //////////////////////////////////////////////////////////////*/

    function _notifyReward(uint256 amount) internal {
        apiary.mint(address(staking), amount);
        vm.prank(distributor);
        staking.notifyRewardAmount(amount);
    }

    /*//////////////////////////////////////////////////////////////
                    1. DEPLOYMENT & INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_APIARYAddress() public view {
        assertEq(staking.APIARY(), address(apiary));
    }

    function test_Deployment_Owner() public view {
        assertEq(staking.owner(), owner);
    }

    function test_Deployment_RewardsDistributor() public view {
        assertEq(staking.rewardsDistributor(), distributor);
    }

    function test_Deployment_InitialStateZero() public view {
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.rewardRate(), 0);
        assertEq(staking.periodFinish(), 0);
        assertEq(staking.rewardPerTokenStored(), 0);
    }

    function testRevert_Deployment_ZeroAPIARY() public {
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_ADDRESS.selector);
        new ApiaryStaking(address(0), owner);
    }

    /*//////////////////////////////////////////////////////////////
                    2. BASIC STAKE & UNSTAKE
    //////////////////////////////////////////////////////////////*/

    function test_Stake_UpdatesBalanceAndTotal() public {
        uint256 amount = 10_000e9;

        vm.prank(user1);
        staking.stake(amount);

        assertEq(staking.balanceOf(user1), amount);
        assertEq(staking.totalStaked(), amount);
    }

    function test_Stake_TransfersTokens() public {
        uint256 amount = 10_000e9;
        uint256 before1 = apiary.balanceOf(user1);

        vm.prank(user1);
        staking.stake(amount);

        assertEq(apiary.balanceOf(user1), before1 - amount);
        assertEq(apiary.balanceOf(address(staking)), amount);
    }

    function test_Stake_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, 10_000e9);

        vm.prank(user1);
        staking.stake(10_000e9);
    }

    function testRevert_Stake_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_AMOUNT.selector);
        staking.stake(0);
    }

    function test_Unstake_ReturnsTokens() public {
        uint256 amount = 10_000e9;

        vm.prank(user1);
        staking.stake(amount);

        uint256 beforeBal = apiary.balanceOf(user1);

        vm.prank(user1);
        staking.unstake(amount);

        assertEq(apiary.balanceOf(user1), beforeBal + amount);
        assertEq(staking.balanceOf(user1), 0);
        assertEq(staking.totalStaked(), 0);
    }

    function test_Unstake_EmitsEvent() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, 10_000e9);

        vm.prank(user1);
        staking.unstake(10_000e9);
    }

    function testRevert_Unstake_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_AMOUNT.selector);
        staking.unstake(0);
    }

    function testRevert_Unstake_InsufficientBalance() public {
        vm.prank(user1);
        staking.stake(5_000e9);

        vm.prank(user1);
        vm.expectRevert(ApiaryStaking.APIARY__INSUFFICIENT_BALANCE.selector);
        staking.unstake(5_001e9);
    }

    /*//////////////////////////////////////////////////////////////
              3. STAKE -> NOTIFY -> WARP -> EARNED -> CLAIM
    //////////////////////////////////////////////////////////////*/

    function test_RewardFlow_SingleUser() public {
        uint256 stakeAmount = 10_000e9;
        uint256 rewardAmount = 7_000e9;

        // Stake
        vm.prank(user1);
        staking.stake(stakeAmount);

        // Notify rewards
        _notifyReward(rewardAmount);

        // Warp to end of period
        vm.warp(block.timestamp + REWARDS_DURATION);

        // Check earned (should be ~rewardAmount, minus dust from integer division)
        uint256 pending = staking.earned(user1);
        assertApproxEqAbs(pending, rewardAmount, 1e9); // within 1 token of rounding

        // Claim
        vm.prank(user1);
        uint256 claimed = staking.claim();

        assertApproxEqAbs(claimed, rewardAmount, 1e9);
        assertEq(staking.earned(user1), 0);
    }

    function test_RewardFlow_EarnedGrowsOverTime() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);

        // At halfway
        vm.warp(block.timestamp + REWARDS_DURATION / 2);
        uint256 halfway = staking.earned(user1);

        // At end
        vm.warp(block.timestamp + REWARDS_DURATION / 2);
        uint256 full = staking.earned(user1);

        assertApproxEqAbs(full, halfway * 2, 2e9);
    }

    function test_Claim_EmitsEvent() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 pending = staking.earned(user1);

        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(user1, pending);

        vm.prank(user1);
        staking.claim();
    }

    function test_Claim_ZeroReward_NoTransfer() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        // No rewards notified
        vm.prank(user1);
        uint256 claimed = staking.claim();

        assertEq(claimed, 0);
    }

    /*//////////////////////////////////////////////////////////////
          4. TWO USERS - PROPORTIONAL DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    function test_ProportionalRewards_EqualStakes() public {
        // Both stake equal amounts
        vm.prank(user1);
        staking.stake(10_000e9);

        vm.prank(user2);
        staking.stake(10_000e9);

        _notifyReward(14_000e9);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 earned1 = staking.earned(user1);
        uint256 earned2 = staking.earned(user2);

        // Each should get ~7_000e9
        assertApproxEqAbs(earned1, 7_000e9, 1e9);
        assertApproxEqAbs(earned2, 7_000e9, 1e9);
    }

    function test_ProportionalRewards_UnequalStakes() public {
        // user1 stakes 3x more than user2
        vm.prank(user1);
        staking.stake(30_000e9);

        vm.prank(user2);
        staking.stake(10_000e9);

        uint256 totalReward = 20_000e9;
        _notifyReward(totalReward);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 earned1 = staking.earned(user1);
        uint256 earned2 = staking.earned(user2);

        // user1 should get 75%, user2 25%
        assertApproxEqAbs(earned1, 15_000e9, 1e9);
        assertApproxEqAbs(earned2, 5_000e9, 1e9);
    }

    /*//////////////////////////////////////////////////////////////
                    5. COMPOUND
    //////////////////////////////////////////////////////////////*/

    function test_Compound_RestakesRewards() public {
        uint256 stakeAmount = 10_000e9;
        uint256 rewardAmount = 7_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount);

        _notifyReward(rewardAmount);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 pendingBefore = staking.earned(user1);

        vm.prank(user1);
        uint256 compounded = staking.compound();

        assertApproxEqAbs(compounded, pendingBefore, 1);
        // Balance should increase by compounded amount
        assertApproxEqAbs(staking.balanceOf(user1), stakeAmount + compounded, 1);
        // totalStaked should also increase
        assertApproxEqAbs(staking.totalStaked(), stakeAmount + compounded, 1);
        // Earned should be 0 after compound
        assertEq(staking.earned(user1), 0);
    }

    function test_Compound_EmitsEvent() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 pending = staking.earned(user1);

        vm.expectEmit(true, false, false, true);
        emit Compounded(user1, pending);

        vm.prank(user1);
        staking.compound();
    }

    /*//////////////////////////////////////////////////////////////
          6. NOTIFY REWARD AMOUNT TWICE (extend period)
    //////////////////////////////////////////////////////////////*/

    function test_NotifyReward_ExtendPeriod() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        // First notification
        _notifyReward(7_000e9);
        uint256 firstPeriodFinish = staking.periodFinish();

        // Warp halfway through
        vm.warp(block.timestamp + REWARDS_DURATION / 2);

        // Second notification adds leftover + new reward
        _notifyReward(7_000e9);
        uint256 secondPeriodFinish = staking.periodFinish();

        // Period should be extended from current time
        assertGt(secondPeriodFinish, firstPeriodFinish);

        // Warp to new end
        vm.warp(secondPeriodFinish);

        uint256 earned = staking.earned(user1);
        // Should be close to total 14_000e9 (minus integer rounding)
        assertApproxEqAbs(earned, 14_000e9, 2e9);
    }

    function test_NotifyReward_EmitsEvent() public {
        apiary.mint(address(staking), 7_000e9);

        vm.expectEmit(false, false, false, true);
        emit RewardAdded(7_000e9);

        vm.prank(distributor);
        staking.notifyRewardAmount(7_000e9);
    }

    function test_NotifyReward_OwnerCanCall() public {
        apiary.mint(address(staking), 7_000e9);

        vm.prank(owner);
        staking.notifyRewardAmount(7_000e9);

        assertGt(staking.rewardRate(), 0);
    }

    function test_NotifyReward_RewardTooHigh() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        // Notify more rewards than the contract has
        vm.prank(distributor);
        vm.expectRevert(ApiaryStaking.APIARY__REWARD_TOO_HIGH.selector);
        staking.notifyRewardAmount(999_999e9);
    }

    /*//////////////////////////////////////////////////////////////
                    7. ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function testRevert_NotifyReward_OnlyDistributorOrOwner() public {
        apiary.mint(address(staking), 7_000e9);

        vm.prank(attacker);
        vm.expectRevert(ApiaryStaking.APIARY__NOT_REWARDS_DISTRIBUTOR.selector);
        staking.notifyRewardAmount(7_000e9);
    }

    function testRevert_SetRewardsDistributor_OnlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        staking.setRewardsDistributor(attacker);
    }

    function testRevert_SetRewardsDistributor_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_ADDRESS.selector);
        staking.setRewardsDistributor(address(0));
    }

    function test_SetRewardsDistributor_EmitsEvent() public {
        address newDist = makeAddr("newDist");

        vm.expectEmit(true, false, false, false);
        emit RewardsDistributorUpdated(newDist);

        vm.prank(owner);
        staking.setRewardsDistributor(newDist);

        assertEq(staking.rewardsDistributor(), newDist);
    }

    function testRevert_Pause_OnlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        staking.pause();
    }

    function testRevert_Unpause_OnlyOwner() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(attacker);
        vm.expectRevert();
        staking.unpause();
    }

    function test_Pause_BlocksStake() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.stake(10_000e9);
    }

    function test_Pause_BlocksUnstake() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.unstake(10_000e9);
    }

    function test_Unpause_AllowsStake() public {
        vm.startPrank(owner);
        staking.pause();
        staking.unpause();
        vm.stopPrank();

        vm.prank(user1);
        staking.stake(10_000e9);
        assertEq(staking.balanceOf(user1), 10_000e9);
    }

    /*//////////////////////////////////////////////////////////////
              8. RETRIEVE (fund protection)
    //////////////////////////////////////////////////////////////*/

    function test_Retrieve_OtherToken() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        other.mint(address(staking), 500e18);

        vm.prank(owner);
        staking.retrieve(address(other), 500e18);

        assertEq(other.balanceOf(owner), 500e18);
    }

    function test_Retrieve_ProtectsStakedFunds() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        // Try to drain staked APIARY
        vm.prank(owner);
        vm.expectRevert("ApiaryStaking: cannot drain staked or reward funds");
        staking.retrieve(address(apiary), 10_000e9);
    }

    function test_Retrieve_ProtectsRewardFunds() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);

        // Try to drain reward APIARY
        vm.prank(owner);
        vm.expectRevert("ApiaryStaking: cannot drain staked or reward funds");
        staking.retrieve(address(apiary), 7_000e9);
    }

    function test_Retrieve_AllowsExcessAPIARY() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        // Send extra APIARY accidentally
        apiary.mint(address(staking), 5_000e9);

        vm.prank(owner);
        staking.retrieve(address(apiary), 5_000e9);

        assertEq(apiary.balanceOf(owner), 5_000e9);
    }

    function testRevert_Retrieve_OnlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        staking.retrieve(address(apiary), 1);
    }

    /*//////////////////////////////////////////////////////////////
                    9. EXIT (unstake all + claim)
    //////////////////////////////////////////////////////////////*/

    function test_Exit_UnstakesAndClaims() public {
        uint256 stakeAmount = 10_000e9;
        uint256 rewardAmount = 7_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount);

        _notifyReward(rewardAmount);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 pending = staking.earned(user1);
        uint256 balBefore = apiary.balanceOf(user1);

        vm.prank(user1);
        staking.exit();

        assertEq(staking.balanceOf(user1), 0);
        assertEq(staking.totalStaked(), 0);
        // User receives stake + rewards
        assertApproxEqAbs(apiary.balanceOf(user1), balBefore + stakeAmount + pending, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    10. VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_RewardPerToken_ZeroTotalStaked() public view {
        assertEq(staking.rewardPerToken(), 0);
    }

    function test_GetRewardForDuration() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);

        uint256 rewardForDuration = staking.getRewardForDuration();
        assertApproxEqAbs(rewardForDuration, 7_000e9, 1e9);
    }

    function test_LastTimeRewardApplicable_BeforePeriod() public view {
        // No rewards notified, periodFinish is 0
        assertEq(staking.lastTimeRewardApplicable(), 0);
    }

    function test_LastTimeRewardApplicable_DuringPeriod() public {
        vm.prank(user1);
        staking.stake(10_000e9);

        _notifyReward(7_000e9);

        uint256 ts = block.timestamp + 1 days;
        vm.warp(ts);

        assertEq(staking.lastTimeRewardApplicable(), ts);
    }

    /*//////////////////////////////////////////////////////////////
                    11. FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_StakeAndUnstake(uint256 stakeAmount, uint256 unstakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, 100_000e9);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        assertEq(staking.balanceOf(user1), stakeAmount - unstakeAmount);
        assertEq(staking.totalStaked(), stakeAmount - unstakeAmount);
    }

    function testFuzz_RewardDistribution(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, REWARDS_DURATION, 1_000_000e9); // at least 1 wei/sec

        vm.prank(user1);
        staking.stake(50_000e9);

        _notifyReward(rewardAmount);
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 earned = staking.earned(user1);
        // Allow rounding error up to REWARDS_DURATION (1 wei per second lost)
        assertApproxEqAbs(earned, rewardAmount, REWARDS_DURATION);
    }
}
