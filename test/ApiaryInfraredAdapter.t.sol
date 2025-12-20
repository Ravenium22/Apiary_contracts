// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ApiaryInfraredAdapter Test Cases
 * @notice Comprehensive test coverage for Infrared adapter
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Stake Operations
 * 3. Unstake Operations
 * 4. Claim Rewards
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

contract MockInfrared is IInfrared {
    address public ibgtToken;
    IERC20 public rewardTokenContract;
    
    mapping(address => StakeInfo) public stakes;
    uint256 public totalStakedAmount;
    uint256 public totalSharesAmount;
    uint256 public lockupPeriodValue;
    uint256 public unstakeFeeValue;
    uint256 public rewardPerBlockValue;
    
    constructor(address _ibgt, address _rewardToken) {
        ibgtToken = _ibgt;
        rewardTokenContract = IERC20(_rewardToken);
        lockupPeriodValue = 0; // No lockup
        unstakeFeeValue = 0; // No fee
    }
    
    function stake(uint256 amount) external returns (uint256 shares) {
        IERC20(ibgtToken).transferFrom(msg.sender, address(this), amount);
        
        shares = totalSharesAmount == 0 ? amount : (amount * totalSharesAmount) / totalStakedAmount;
        
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].shares += shares;
        stakes[msg.sender].lastRewardBlock = block.number;
        
        totalStakedAmount += amount;
        totalSharesAmount += shares;
        
        emit Staked(msg.sender, amount, shares);
    }
    
    function unstake(uint256 amount) external returns (uint256 withdrawn) {
        require(stakes[msg.sender].amount >= amount, "Insufficient stake");
        
        uint256 shares = (amount * stakes[msg.sender].shares) / stakes[msg.sender].amount;
        
        stakes[msg.sender].amount -= amount;
        stakes[msg.sender].shares -= shares;
        
        totalStakedAmount -= amount;
        totalSharesAmount -= shares;
        
        // Apply fee if any
        uint256 fee = (amount * unstakeFeeValue) / 10000;
        withdrawn = amount - fee;
        
        IERC20(ibgtToken).transfer(msg.sender, withdrawn);
        
        emit Unstaked(msg.sender, amount, shares);
    }
    
    function claimRewards() external returns (uint256 rewardAmount) {
        uint256 pending = pendingRewards(msg.sender);
        
        if (pending > 0) {
            stakes[msg.sender].rewardDebt += pending;
            stakes[msg.sender].lastRewardBlock = block.number;
            
            rewardTokenContract.transfer(msg.sender, pending);
            emit RewardsClaimed(msg.sender, pending, address(rewardTokenContract));
        }
        
        rewardAmount = pending;
    }
    
    function emergencyWithdraw() external {
        uint256 amount = stakes[msg.sender].amount;
        
        delete stakes[msg.sender];
        totalStakedAmount -= amount;
        
        IERC20(ibgtToken).transfer(msg.sender, amount);
    }
    
    function pendingRewards(address user) public view returns (uint256) {
        if (stakes[user].amount == 0) return 0;
        
        uint256 blocksSinceLastClaim = block.number - stakes[user].lastRewardBlock;
        return (stakes[user].amount * rewardPerBlockValue * blocksSinceLastClaim) / 1e18;
    }
    
    function stakedBalance(address user) external view returns (uint256) {
        return stakes[user].amount;
    }
    
    function sharesOf(address user) external view returns (uint256) {
        return stakes[user].shares;
    }
    
    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakes[user];
    }
    
    function totalStaked() external view returns (uint256) {
        return totalStakedAmount;
    }
    
    function totalShares() external view returns (uint256) {
        return totalSharesAmount;
    }
    
    function rewardToken() external view returns (address) {
        return address(rewardTokenContract);
    }
    
    function ibgt() external view returns (address) {
        return address(ibgtToken);
    }
    
    function lockupPeriod() external view returns (uint256) {
        return lockupPeriodValue;
    }
    
    function unstakeFee() external view returns (uint256) {
        return unstakeFeeValue;
    }
    
    function rewardPerBlock() external view returns (uint256) {
        return rewardPerBlockValue;
    }
    
    function sharesToAmount(uint256 shares) external view returns (uint256) {
        if (totalSharesAmount == 0) return 0;
        return (shares * totalStakedAmount) / totalSharesAmount;
    }
    
    function amountToShares(uint256 amount) external view returns (uint256) {
        if (totalStakedAmount == 0) return amount;
        return (amount * totalSharesAmount) / totalStakedAmount;
    }
    
    // Test helpers
    function setLockupPeriod(uint256 period) external {
        lockupPeriodValue = period;
    }
    
    function setUnstakeFee(uint256 fee) external {
        unstakeFeeValue = fee;
    }
    
    function setRewardPerBlock(uint256 reward) external {
        rewardPerBlockValue = reward;
    }
}

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

contract ApiaryInfraredAdapterTest is Test {
    ApiaryInfraredAdapter public adapter;
    MockInfrared public infrared;
    MockERC20 public ibgt;
    MockERC20 public rewardToken;
    
    address public owner = address(1);
    address public yieldManager = address(2);
    address public user = address(4);
    
    function setUp() public {
        // Deploy mock tokens
        ibgt = new MockERC20("Infrared BGT", "iBGT", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);
        
        // Deploy mock Infrared
        infrared = new MockInfrared(address(ibgt), address(rewardToken));
        
        // Deploy adapter with new constructor (infrared, ibgt, yieldManager, owner)
        vm.prank(owner);
        adapter = new ApiaryInfraredAdapter(
            address(infrared),
            address(ibgt),
            yieldManager,
            owner
        );
        
        // Setup approvals (NEW: must call setupApprovals after deployment)
        vm.prank(owner);
        adapter.setupApprovals();
        
        // Mint iBGT to yield manager (NEW: YieldManager holds tokens and approves adapter)
        ibgt.mint(yieldManager, 10000e18);
        
        // YieldManager approves adapter to pull tokens
        vm.prank(yieldManager);
        ibgt.approve(address(adapter), type(uint256).max);
        
        // Mint reward tokens to Infrared
        rewardToken.mint(address(infrared), 10000e18);
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
    
    /// @notice Test stake with pull pattern (adapter pulls from YieldManager)
    function testStake() public {
        uint256 stakeAmount = 100e18;
        
        // Stake (adapter pulls from yieldManager)
        vm.prank(yieldManager);
        uint256 staked = adapter.stake(stakeAmount);
        
        assertEq(adapter.totalStaked(), stakeAmount);
        assertEq(staked, stakeAmount);
        // YieldManager should have less balance now
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
    
    /// @notice Test unstake returns tokens to caller (YieldManager)
    function testUnstake() public {
        // First stake
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);
        
        // Then unstake - tokens should return to yieldManager (caller)
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
    
    function testUnstakeWithFee() public {
        // Set 5% unstake fee
        infrared.setUnstakeFee(500);
        
        // Stake
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);
        
        // Unstake - tokens return to yieldManager
        uint256 yieldManagerBalanceBefore = ibgt.balanceOf(yieldManager);
        vm.prank(yieldManager);
        uint256 withdrawn = adapter.unstake(stakeAmount);
        
        // Should receive 95% (5% fee)
        assertEq(withdrawn, stakeAmount * 95 / 100);
        assertEq(ibgt.balanceOf(yieldManager), yieldManagerBalanceBefore + withdrawn);
    }
    
    /*//////////////////////////////////////////////////////////////
                            4. CLAIM REWARDS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test claimRewards returns rewards to caller (YieldManager)
    function testClaimRewards() public {
        // Stake first
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);
        
        // Set reward rate and advance blocks
        infrared.setRewardPerBlock(1e18);
        vm.roll(block.number + 100);
        
        // Claim rewards - should return to yieldManager (caller)
        uint256 yieldManagerBalanceBefore = rewardToken.balanceOf(yieldManager);
        
        vm.prank(yieldManager);
        uint256 rewardAmount = adapter.claimRewards();
        
        assertGt(rewardAmount, 0);
        assertEq(rewardToken.balanceOf(yieldManager), yieldManagerBalanceBefore + rewardAmount);
        assertEq(adapter.totalRewardsClaimed(), rewardAmount);
    }
    
    function testClaimRewardsReturnsZeroWhenNoRewards() public {
        // The contract doesn't revert on zero rewards - it just returns 0
        vm.prank(yieldManager);
        uint256 claimed = adapter.claimRewards();
        assertEq(claimed, 0);
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
        // Deploy new adapter without approvals
        vm.prank(owner);
        ApiaryInfraredAdapter newAdapter = new ApiaryInfraredAdapter(
            address(infrared),
            address(ibgt),
            yieldManager,
            owner
        );
        
        // Setup approvals
        vm.prank(owner);
        newAdapter.setupApprovals();
        
        // Now adapter should be able to transfer to Infrared
        // (approval check via allowance)
        assertEq(ibgt.allowance(address(newAdapter), address(infrared)), type(uint256).max);
    }
    
    function testSyncAccounting() public {
        // Stake some tokens
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        // Manually manipulate accounting (simulate drift)
        // This would require accessing internal state, so we test the happy path
        
        uint256 oldStaked = adapter.totalStaked();
        
        vm.prank(owner);
        adapter.syncAccounting();
        
        // After sync, totalStaked should match actual balance
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
        // Stake multiple times
        vm.startPrank(yieldManager);
        adapter.stake(100e18);
        adapter.stake(50e18);
        adapter.stake(75e18);
        
        assertEq(adapter.totalStaked(), 225e18);
        
        // Unstake partially
        adapter.unstake(50e18);
        assertEq(adapter.totalStaked(), 175e18);
        
        adapter.unstake(75e18);
        assertEq(adapter.totalStaked(), 100e18);
        
        vm.stopPrank();
    }
    
    function testClaimRewardsMultipleTimes() public {
        // Stake
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        // Set reward rate
        infrared.setRewardPerBlock(1e18);
        
        // Claim multiple times
        vm.startPrank(yieldManager);
        
        vm.roll(block.number + 10);
        uint256 reward1 = adapter.claimRewards();
        
        vm.roll(block.number + 10);
        uint256 reward2 = adapter.claimRewards();
        
        vm.roll(block.number + 10);
        uint256 reward3 = adapter.claimRewards();
        
        vm.stopPrank();
        
        assertEq(adapter.totalRewardsClaimed(), reward1 + reward2 + reward3);
    }
    
    /*//////////////////////////////////////////////////////////////
                            7. EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function testEmergencyUnstakeAll() public {
        // Stake first
        uint256 stakeAmount = 100e18;
        vm.prank(yieldManager);
        adapter.stake(stakeAmount);
        
        // Emergency unstake - returns to owner
        uint256 ownerBalanceBefore = ibgt.balanceOf(owner);
        
        vm.prank(owner);
        adapter.emergencyUnstakeAll();
        
        assertEq(adapter.totalStaked(), 0);
        assertEq(ibgt.balanceOf(owner), ownerBalanceBefore + stakeAmount);
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
        // Stake
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        // Set reward rate
        infrared.setRewardPerBlock(1e18);
        vm.roll(block.number + 10);
        
        uint256 pending = adapter.pendingRewards();
        assertGt(pending, 0);
    }
    
    function testGetStakedBalance() public {
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        uint256 staked = adapter.getStakedBalance();
        assertEq(staked, 100e18);
    }
    
    function testGetIBGTBalance() public {
        // Adapter should normally have 0 iBGT (all staked on Infrared)
        uint256 balance = adapter.getIBGTBalance();
        assertEq(balance, 0);
        
        // Mint some iBGT directly to adapter (simulating stuck tokens)
        ibgt.mint(address(adapter), 50e18);
        balance = adapter.getIBGTBalance();
        assertEq(balance, 50e18);
    }
    
    function testCanStake() public view {
        assertTrue(adapter.canStake(1e18));
        assertFalse(adapter.canStake(0.001e18)); // Below minimum
    }
    
    function testCanUnstake() public {
        // Can't unstake if nothing staked
        assertFalse(adapter.canUnstake(1e18));
        
        // Stake first
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        assertTrue(adapter.canUnstake(50e18));
        assertFalse(adapter.canUnstake(150e18)); // More than staked
    }
    
    /*//////////////////////////////////////////////////////////////
                            9. INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFullCycle() public {
        // 1. Stake (uses pull pattern)
        vm.prank(yieldManager);
        adapter.stake(100e18);
        
        // 2. Earn rewards
        infrared.setRewardPerBlock(1e18);
        vm.roll(block.number + 100);
        
        // 3. Claim rewards - returns to yieldManager
        uint256 ymBalanceBefore = rewardToken.balanceOf(yieldManager);
        vm.prank(yieldManager);
        uint256 claimed = adapter.claimRewards();
        assertGt(claimed, 0);
        assertEq(rewardToken.balanceOf(yieldManager), ymBalanceBefore + claimed);
        
        // 4. Unstake - returns to yieldManager
        uint256 ymIBGTBefore = ibgt.balanceOf(yieldManager);
        vm.prank(yieldManager);
        adapter.unstake(50e18);
        
        // Verify final state
        assertEq(adapter.totalStaked(), 50e18);
        assertGt(adapter.totalRewardsClaimed(), 0);
        assertGt(ibgt.balanceOf(yieldManager), ymIBGTBefore);
    }
}
