// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ApiaryInfraredAdapter Test Cases
 * @notice Comprehensive test coverage for Infrared adapter (MultiRewards interface)
 *
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Stake Operations
 * 3. Unstake Operations
 * 4. Claim Rewards (Multi-Token)
 * 5. Access Control
 * 6. Edge Cases
 * 7. Emergency Functions
 * 8. View Functions
 * 9. Integration Tests
 */

import { Test } from "forge-std/Test.sol";
import { ApiaryInfraredAdapter } from "../src/ApiaryInfraredAdapter.sol";
import { IInfrared } from "../src/interfaces/IInfrared.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private totalSupplyAmount;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupplyAmount += amount;
    }

    function totalSupply() external view returns (uint256) {
        return totalSupplyAmount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");

        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;

        return true;
    }
}

/**
 * @notice Mock InfraredVault implementing the real MultiRewards interface
 */
contract MockInfraredVault is IInfrared {
    address public stakingTokenAddr;
    address[] public rewardTokenList;

    mapping(address => uint256) public stakedBalances;
    uint256 public totalStakedAmount;

    // reward token => user => earned amount
    mapping(address => mapping(address => uint256)) public earnedRewards;
    // reward token => reward per token value
    mapping(address => uint256) public rewardPerTokenStored;

    // For simulating reward accrual
    uint256 public rewardRate;
    uint256 public lastUpdateBlock;

    constructor(address _stakingToken, address[] memory _rewardTokens) {
        stakingTokenAddr = _stakingToken;
        rewardTokenList = _rewardTokens;
    }

    function stake(uint256 amount) external {
        IERC20(stakingTokenAddr).transferFrom(msg.sender, address(this), amount);
        stakedBalances[msg.sender] += amount;
        totalStakedAmount += amount;
        lastUpdateBlock = block.number;
    }

    function withdraw(uint256 amount) external {
        require(stakedBalances[msg.sender] >= amount, "Insufficient stake");
        stakedBalances[msg.sender] -= amount;
        totalStakedAmount -= amount;
        IERC20(stakingTokenAddr).transfer(msg.sender, amount);
    }

    function getReward() external {
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address token = rewardTokenList[i];
            uint256 reward = earnedRewards[token][msg.sender];
            if (reward > 0) {
                earnedRewards[token][msg.sender] = 0;
                IERC20(token).transfer(msg.sender, reward);
            }
        }
    }

    function exit() external {
        uint256 staked = stakedBalances[msg.sender];
        if (staked > 0) {
            stakedBalances[msg.sender] = 0;
            totalStakedAmount -= staked;
            IERC20(stakingTokenAddr).transfer(msg.sender, staked);
        }
        // Claim all rewards
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address token = rewardTokenList[i];
            uint256 reward = earnedRewards[token][msg.sender];
            if (reward > 0) {
                earnedRewards[token][msg.sender] = 0;
                IERC20(token).transfer(msg.sender, reward);
            }
        }
    }

    function balanceOf(address account) external view returns (uint256) {
        return stakedBalances[account];
    }

    function totalSupply() external view returns (uint256) {
        return totalStakedAmount;
    }

    function stakingToken() external view returns (address) {
        return stakingTokenAddr;
    }

    function getAllRewardTokens() external view returns (address[] memory) {
        return rewardTokenList;
    }

    function getAllRewardsForUser(address user) external view returns (RewardData[] memory rewards) {
        rewards = new RewardData[](rewardTokenList.length);
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            rewards[i] = RewardData({
                token: rewardTokenList[i],
                amount: earnedRewards[rewardTokenList[i]][user]
            });
        }
    }

    function earned(address account, address rewardToken) external view returns (uint256) {
        return earnedRewards[rewardToken][account];
    }

    function rewardPerToken(address rewardToken) external view returns (uint256) {
        return rewardPerTokenStored[rewardToken];
    }

    // Test helpers

    function setEarnedRewards(address user, address rewardToken, uint256 amount) external {
        earnedRewards[rewardToken][user] = amount;
    }

    function setRewardRate(uint256 _rate) external {
        rewardRate = _rate;
    }
}

contract ApiaryInfraredAdapterTest is Test {
    ApiaryInfraredAdapter public adapter;
    MockInfraredVault public infrared;
    MockERC20 public ibgt;
    MockERC20 public rewardToken1; // HONEY
    MockERC20 public rewardToken2; // wBERA

    address public owner = address(1);
    address public yieldManager = address(2);
    address public user = address(4);

    function setUp() public {
        // Deploy mock tokens
        ibgt = new MockERC20("Infrared BGT", "iBGT", 18);
        rewardToken1 = new MockERC20("HONEY", "HONEY", 18);
        rewardToken2 = new MockERC20("Wrapped BERA", "wBERA", 18);

        // Deploy mock Infrared vault with multi-token rewards
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken1);
        rewardTokens[1] = address(rewardToken2);
        infrared = new MockInfraredVault(address(ibgt), rewardTokens);

        // Deploy adapter with new constructor (infrared, ibgt, yieldManager, owner)
        vm.prank(owner);
        adapter = new ApiaryInfraredAdapter(
            address(infrared),
            address(ibgt),
            yieldManager,
            owner
        );

        // Setup approvals (must call setupApprovals after deployment)
        vm.prank(owner);
        adapter.setupApprovals();

        // Mint iBGT to yield manager
        ibgt.mint(yieldManager, 10000e18);

        // YieldManager approves adapter to pull tokens
        vm.prank(yieldManager);
        ibgt.approve(address(adapter), type(uint256).max);

        // Mint reward tokens to Infrared vault
        rewardToken1.mint(address(infrared), 10000e18);
        rewardToken2.mint(address(infrared), 5000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        1. DEPLOYMENT & INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public view {
        assertEq(address(adapter.infrared()), address(infrared));
        assertEq(address(adapter.ibgt()), address(ibgt));
        assertEq(adapter.yieldManager(), yieldManager);
        assertEq(adapter.owner(), owner);
    }

    function testDeploymentRevertsZeroAddress() public {
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__ZERO_ADDRESS.selector);
        new ApiaryInfraredAdapter(address(0), address(ibgt), yieldManager, owner);

        vm.expectRevert(ApiaryInfraredAdapter.APIARY__ZERO_ADDRESS.selector);
        new ApiaryInfraredAdapter(address(infrared), address(0), yieldManager, owner);

        vm.expectRevert(ApiaryInfraredAdapter.APIARY__ZERO_ADDRESS.selector);
        new ApiaryInfraredAdapter(address(infrared), address(ibgt), address(0), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            2. STAKE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function testStake() public {
        uint256 stakeAmount = 100e18;

        vm.prank(yieldManager);
        uint256 staked = adapter.stake(stakeAmount);

        assertEq(adapter.totalStaked(), stakeAmount);
        assertEq(staked, stakeAmount);
        assertEq(ibgt.balanceOf(yieldManager), 10000e18 - stakeAmount);
    }

    function testStakeRevertsNonYieldManager() public {
        vm.prank(user);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__ONLY_YIELD_MANAGER.selector);
        adapter.stake(100e18);
    }

    function testStakeRevertsZeroAmount() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__INVALID_AMOUNT.selector);
        adapter.stake(0);
    }

    function testStakeRevertsBelowMinimum() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__BELOW_MINIMUM.selector);
        adapter.stake(0.001e18); // Below 0.01 default minimum
    }

    function testStakeWhenPaused() public {
        vm.prank(owner);
        adapter.pause();

        vm.prank(yieldManager);
        vm.expectRevert();
        adapter.stake(100e18);
    }

    function testFuzzStake(uint256 amount) public {
        amount = bound(amount, adapter.minStakeAmount(), 1000e18);

        vm.prank(yieldManager);
        adapter.stake(amount);

        assertEq(adapter.totalStaked(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            3. UNSTAKE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function testUnstake() public {
        // First stake
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);

        // Then unstake
        uint256 unstakeAmount = 50e18;
        uint256 yieldManagerBalanceBefore = ibgt.balanceOf(yieldManager);

        vm.prank(yieldManager);
        uint256 withdrawn = adapter.unstake(unstakeAmount);

        assertEq(adapter.totalStaked(), stakeAmount - unstakeAmount);
        assertEq(ibgt.balanceOf(yieldManager), yieldManagerBalanceBefore + withdrawn);
    }

    function testUnstakeRevertsInsufficientStaked() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__INSUFFICIENT_STAKED.selector);
        adapter.unstake(100e18);
    }

    function testUnstakeRevertsZeroAmount() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__INVALID_AMOUNT.selector);
        adapter.unstake(0);
    }

    /*//////////////////////////////////////////////////////////////
                    4. CLAIM REWARDS (Multi-Token)
    //////////////////////////////////////////////////////////////*/

    function testClaimRewardsMultiToken() public {
        // Stake first
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);

        // Set rewards for the adapter (simulating accrual)
        uint256 honeyReward = 50e18;
        uint256 wberaReward = 25e18;
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), honeyReward);
        infrared.setEarnedRewards(address(adapter), address(rewardToken2), wberaReward);

        // Claim rewards
        uint256 ymHoneyBefore = rewardToken1.balanceOf(yieldManager);
        uint256 ymWberaBefore = rewardToken2.balanceOf(yieldManager);

        vm.prank(yieldManager);
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimRewards();

        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(rewardToken1));
        assertEq(tokens[1], address(rewardToken2));
        assertEq(amounts[0], honeyReward);
        assertEq(amounts[1], wberaReward);

        // Verify tokens transferred to yieldManager
        assertEq(rewardToken1.balanceOf(yieldManager), ymHoneyBefore + honeyReward);
        assertEq(rewardToken2.balanceOf(yieldManager), ymWberaBefore + wberaReward);

        // Verify tracking
        assertEq(adapter.totalRewardsClaimedPerToken(address(rewardToken1)), honeyReward);
        assertEq(adapter.totalRewardsClaimedPerToken(address(rewardToken2)), wberaReward);
    }

    function testClaimRewardsReturnsZeroWhenNoRewards() public {
        vm.prank(yieldManager);
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimRewards();

        assertEq(tokens.length, 2);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
    }

    function testClaimRewardsPartialRewards() public {
        // Stake first
        vm.prank(yieldManager);
        adapter.stake(100e18);

        // Only set HONEY reward, not wBERA
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 10e18);

        vm.prank(yieldManager);
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimRewards();

        assertEq(amounts[0], 10e18);
        assertEq(amounts[1], 0);
        assertEq(adapter.totalRewardsClaimedPerToken(address(rewardToken1)), 10e18);
        assertEq(adapter.totalRewardsClaimedPerToken(address(rewardToken2)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            5. ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function testSetYieldManager() public {
        address newManager = address(5);

        vm.prank(owner);
        adapter.setYieldManager(newManager);

        assertEq(adapter.yieldManager(), newManager);
    }

    function testSetYieldManagerRevertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.setYieldManager(address(5));
    }

    function testSetYieldManagerRevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryInfraredAdapter.APIARY__ZERO_ADDRESS.selector);
        adapter.setYieldManager(address(0));
    }

    function testSetupApprovals() public {
        vm.prank(owner);
        ApiaryInfraredAdapter newAdapter = new ApiaryInfraredAdapter(
            address(infrared),
            address(ibgt),
            yieldManager,
            owner
        );

        vm.prank(owner);
        newAdapter.setupApprovals();

        assertEq(ibgt.allowance(address(newAdapter), address(infrared)), type(uint256).max);
    }

    function testSyncAccounting() public {
        vm.prank(yieldManager);
        adapter.stake(100e18);

        vm.prank(owner);
        adapter.syncAccounting();

        assertEq(adapter.totalStaked(), adapter.getStakedBalance());
    }

    function testOwnershipTransfer() public {
        address newOwner = address(7);

        vm.prank(owner);
        adapter.transferOwnership(newOwner);

        vm.prank(newOwner);
        adapter.acceptOwnership();

        assertEq(adapter.owner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            6. EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testStakeUnstakeMultipleTimes() public {
        vm.startPrank(yieldManager);
        adapter.stake(100e18);
        adapter.stake(50e18);
        adapter.stake(75e18);

        assertEq(adapter.totalStaked(), 225e18);

        adapter.unstake(50e18);
        assertEq(adapter.totalStaked(), 175e18);

        adapter.unstake(75e18);
        assertEq(adapter.totalStaked(), 100e18);

        vm.stopPrank();
    }

    function testClaimRewardsMultipleTimes() public {
        vm.prank(yieldManager);
        adapter.stake(100e18);

        // First claim
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 10e18);
        vm.prank(yieldManager);
        adapter.claimRewards();

        // Second claim
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 20e18);
        vm.prank(yieldManager);
        adapter.claimRewards();

        // Third claim
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 15e18);
        vm.prank(yieldManager);
        adapter.claimRewards();

        assertEq(adapter.totalRewardsClaimedPerToken(address(rewardToken1)), 45e18);
    }

    /*//////////////////////////////////////////////////////////////
                            7. EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testEmergencyUnstakeAll() public {
        // Stake first
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);

        // Set some rewards
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 5e18);

        // Emergency unstake - returns everything to owner
        uint256 ownerIBGTBefore = ibgt.balanceOf(owner);
        uint256 ownerHoneyBefore = rewardToken1.balanceOf(owner);

        vm.prank(owner);
        adapter.emergencyUnstakeAll();

        assertEq(adapter.totalStaked(), 0);
        assertEq(ibgt.balanceOf(owner), ownerIBGTBefore + stakeAmount);
        assertEq(rewardToken1.balanceOf(owner), ownerHoneyBefore + 5e18);
    }

    function testEmergencyWithdrawToken() public {
        // Send some random tokens to adapter
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(adapter), 100e18);

        address recipient = address(0x999);
        uint256 recipientBalanceBefore = randomToken.balanceOf(recipient);

        vm.prank(owner);
        adapter.emergencyWithdrawToken(address(randomToken), 100e18, recipient);

        assertEq(randomToken.balanceOf(recipient), recipientBalanceBefore + 100e18);
        assertEq(randomToken.balanceOf(address(adapter)), 0);
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);

        adapter.pause();
        assertTrue(adapter.paused());

        adapter.unpause();
        assertFalse(adapter.paused());

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            8. VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testPendingRewards() public {
        vm.prank(yieldManager);
        adapter.stake(100e18);

        // Set some pending rewards
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 10e18);
        infrared.setEarnedRewards(address(adapter), address(rewardToken2), 5e18);

        (address[] memory tokens, uint256[] memory amounts) = adapter.pendingRewards();
        assertEq(tokens.length, 2);
        assertEq(amounts[0], 10e18);
        assertEq(amounts[1], 5e18);
    }

    function testGetStakedBalance() public {
        vm.prank(yieldManager);
        adapter.stake(100e18);

        uint256 staked = adapter.getStakedBalance();
        assertEq(staked, 100e18);
    }

    function testGetIBGTBalance() public {
        uint256 balance = adapter.getIBGTBalance();
        assertEq(balance, 0);

        ibgt.mint(address(adapter), 50e18);
        balance = adapter.getIBGTBalance();
        assertEq(balance, 50e18);
    }

    function testCanStake() public view {
        assertTrue(adapter.canStake(1e18));
        assertFalse(adapter.canStake(0.001e18)); // Below minimum
    }

    function testCanUnstake() public {
        assertFalse(adapter.canUnstake(1e18));

        vm.prank(yieldManager);
        adapter.stake(100e18);

        assertTrue(adapter.canUnstake(50e18));
        assertFalse(adapter.canUnstake(150e18)); // More than staked
    }

    function testGetInfraredInfo() public {
        (address stakingTokenAddr, uint256 totalInVault, address[] memory rewardTokens) = adapter.getInfraredInfo();
        assertEq(stakingTokenAddr, address(ibgt));
        assertEq(totalInVault, 0);
        assertEq(rewardTokens.length, 2);
    }

    function testGetAdapterInfo() public {
        (address ymAddr, uint256 totalStakedAmount, uint256 minStake, uint256 minUnstake) = adapter.getAdapterInfo();
        assertEq(ymAddr, yieldManager);
        assertEq(totalStakedAmount, 0);
        assertEq(minStake, 0.01e18);
        assertEq(minUnstake, 0.01e18);
    }

    /*//////////////////////////////////////////////////////////////
                            9. INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullCycle() public {
        // 1. Stake
        vm.prank(yieldManager);
        adapter.stake(100e18);

        // 2. Accumulate rewards
        infrared.setEarnedRewards(address(adapter), address(rewardToken1), 50e18);
        infrared.setEarnedRewards(address(adapter), address(rewardToken2), 25e18);

        // 3. Claim rewards
        uint256 ymHoneyBefore = rewardToken1.balanceOf(yieldManager);
        uint256 ymWberaBefore = rewardToken2.balanceOf(yieldManager);

        vm.prank(yieldManager);
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimRewards();
        assertEq(amounts[0], 50e18);
        assertEq(amounts[1], 25e18);
        assertEq(rewardToken1.balanceOf(yieldManager), ymHoneyBefore + 50e18);
        assertEq(rewardToken2.balanceOf(yieldManager), ymWberaBefore + 25e18);

        // 4. Unstake partial
        uint256 ymIBGTBefore = ibgt.balanceOf(yieldManager);
        vm.prank(yieldManager);
        adapter.unstake(50e18);

        assertEq(adapter.totalStaked(), 50e18);
        assertGt(ibgt.balanceOf(yieldManager), ymIBGTBefore);
    }
}
