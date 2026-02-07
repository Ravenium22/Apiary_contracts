// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryStaking } from "../src/ApiaryStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApiaryStakingTest
 * @notice Comprehensive test suite for staking contract
 * @dev Tests instant staking, rebasing, Phase 1 behavior, and access control
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Staking (Instant sAPIARY receipt)
 * 3. Unstaking
 * 4. Rebasing
 * 5. Phase 1 Behavior
 * 6. Locker Functions
 * 7. Admin Functions
 * 8. Access Control
 * 9. Edge Cases
 */

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockAPIARY is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    // Track last staked time updates
    mapping(address => uint48) public lastTimeStaked;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        return true;
    }

    function updateLastStakedTime(address _staker) external {
        lastTimeStaked[_staker] = uint48(block.timestamp);
    }
}

contract MocksAPIARY is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint256 public currentIndex = 1e9; // Initial index
    uint256 public rebaseCount;
    uint256 public lastRebaseProfit;
    uint256 public lastRebaseEpoch;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function setBalance(address account, uint256 amount) external {
        _totalSupply = _totalSupply - _balances[account] + amount;
        _balances[account] = amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        return true;
    }

    // sAPIARY specific functions
    function rebase(uint256 profit_, uint256 epoch_) external returns (uint256) {
        rebaseCount++;
        lastRebaseProfit = profit_;
        lastRebaseEpoch = epoch_;

        if (profit_ > 0) {
            _totalSupply += profit_;
        }

        return _totalSupply;
    }

    function circulatingSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function index() external view returns (uint256) {
        return currentIndex;
    }

    function setIndex(uint256 _index) external {
        currentIndex = _index;
    }

    function gonsForBalance(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function balanceForGons(uint256 gons) external pure returns (uint256) {
        return gons;
    }
}

contract MockDistributor {
    uint256 public distributeCount;

    function distribute() external returns (bool) {
        distributeCount++;
        return true;
    }
}

contract ApiaryStakingTest is Test {
    ApiaryStaking public staking;
    MockAPIARY public apiary;
    MocksAPIARY public sApiary;
    MockDistributor public distributor;

    // Test accounts
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public locker = makeAddr("locker");
    address public attacker = makeAddr("attacker");

    // Epoch config
    uint256 public constant EPOCH_LENGTH = 2200; // ~3 hours in blocks
    uint256 public constant FIRST_EPOCH_NUMBER = 1;
    uint256 public firstEpochBlock;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount, address indexed recipient);
    event Unstaked(address indexed user, uint256 amount);
    event Rebased(uint256 indexed epoch, uint256 distribute);
    event DistributorSet(address indexed distributor);
    event LockerSet(address indexed locker);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mocks
        apiary = new MockAPIARY();
        sApiary = new MocksAPIARY();
        distributor = new MockDistributor();

        // Set first epoch block
        firstEpochBlock = block.number + EPOCH_LENGTH;

        // Deploy staking
        vm.prank(owner);
        staking = new ApiaryStaking(
            address(apiary),
            address(sApiary),
            EPOCH_LENGTH,
            FIRST_EPOCH_NUMBER,
            firstEpochBlock,
            owner
        );

        // Give staking contract sAPIARY to distribute
        sApiary.mint(address(staking), 1_000_000e9);

        // Give users APIARY to stake
        apiary.mint(user1, 100_000e9);
        apiary.mint(user2, 100_000e9);

        // Approve staking contract
        vm.prank(user1);
        apiary.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        apiary.approve(address(staking), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_APIARYAddress() public view {
        assertEq(staking.APIARY(), address(apiary));
    }

    function test_Deployment_sAPIARYAddress() public view {
        assertEq(staking.sAPIARY(), address(sApiary));
    }

    function test_Deployment_EpochConfig() public view {
        (uint256 length, uint256 number, uint256 endBlock, uint256 distribute) = staking.epoch();

        assertEq(length, EPOCH_LENGTH);
        assertEq(number, FIRST_EPOCH_NUMBER);
        assertEq(endBlock, firstEpochBlock);
        assertEq(distribute, 0); // Phase 1: no distribution
    }

    function test_Deployment_Owner() public view {
        assertEq(staking.owner(), owner);
    }

    function testRevert_Deployment_ZeroAPIARY() public {
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_ADDRESS.selector);
        new ApiaryStaking(
            address(0),
            address(sApiary),
            EPOCH_LENGTH,
            FIRST_EPOCH_NUMBER,
            firstEpochBlock,
            owner
        );
    }

    function testRevert_Deployment_ZerosAPIARY() public {
        vm.expectRevert(ApiaryStaking.APIARY__INVALID_ADDRESS.selector);
        new ApiaryStaking(
            address(apiary),
            address(0),
            EPOCH_LENGTH,
            FIRST_EPOCH_NUMBER,
            firstEpochBlock,
            owner
        );
    }

    /*//////////////////////////////////////////////////////////////
                        STAKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Stake_InstantReceipt() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        bool success = staking.stake(stakeAmount, user1);

        assertTrue(success);
        // User receives sAPIARY instantly (no warmup)
        assertEq(sApiary.balanceOf(user1), stakeAmount);
    }

    function test_Stake_UpdatesTotalStaked() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        assertEq(staking.totalStaked(), stakeAmount);
    }

    function test_Stake_TransfersAPIARY() public {
        uint256 stakeAmount = 10_000e9;
        uint256 balanceBefore = apiary.balanceOf(user1);

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        assertEq(apiary.balanceOf(user1), balanceBefore - stakeAmount);
        assertEq(apiary.balanceOf(address(staking)), stakeAmount);
    }

    function test_Stake_EmitsEvent() public {
        uint256 stakeAmount = 10_000e9;

        vm.expectEmit(true, false, true, true);
        emit Staked(user1, stakeAmount, user1);

        vm.prank(user1);
        staking.stake(stakeAmount, user1);
    }

    function test_Stake_DifferentRecipient() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user2);

        // sAPIARY goes to user2
        assertEq(sApiary.balanceOf(user2), stakeAmount);
        // APIARY taken from user1
        assertEq(apiary.balanceOf(user1), 100_000e9 - stakeAmount);
    }

    function test_Stake_UpdatesLastStakedTime() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        assertEq(apiary.lastTimeStaked(user1), uint48(block.timestamp));
    }

    function test_Stake_MultipleStakes() public {
        uint256 stake1 = 10_000e9;
        uint256 stake2 = 20_000e9;

        vm.startPrank(user1);
        staking.stake(stake1, user1);
        staking.stake(stake2, user1);
        vm.stopPrank();

        assertEq(sApiary.balanceOf(user1), stake1 + stake2);
        assertEq(staking.totalStaked(), stake1 + stake2);
    }

    /*//////////////////////////////////////////////////////////////
                        UNSTAKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Unstake_ReturnsAPIARY() public {
        uint256 stakeAmount = 10_000e9;

        // First stake
        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        // Give user sAPIARY and approve
        vm.prank(user1);
        sApiary.approve(address(staking), stakeAmount);

        uint256 apiaryBefore = apiary.balanceOf(user1);

        vm.prank(user1);
        staking.unstake(stakeAmount, false);

        // User gets APIARY back 1:1
        assertEq(apiary.balanceOf(user1), apiaryBefore + stakeAmount);
    }

    function test_Unstake_DecreasesTotalStaked() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(user1);
        sApiary.approve(address(staking), stakeAmount);

        vm.prank(user1);
        staking.unstake(stakeAmount, false);

        assertEq(staking.totalStaked(), 0);
    }

    function test_Unstake_EmitsEvent() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(user1);
        sApiary.approve(address(staking), stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, stakeAmount);

        vm.prank(user1);
        staking.unstake(stakeAmount, false);
    }

    function test_Unstake_WithRebaseTrigger() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(user1);
        sApiary.approve(address(staking), stakeAmount);

        // Move past epoch end
        vm.roll(firstEpochBlock + 1);

        vm.prank(user1);
        staking.unstake(stakeAmount, true); // trigger = true

        // Check rebase was called
        assertGt(sApiary.rebaseCount(), 0);
    }

    function test_Unstake_WithoutRebaseTrigger() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(user1);
        sApiary.approve(address(staking), stakeAmount);

        uint256 rebaseCountBefore = sApiary.rebaseCount();

        vm.prank(user1);
        staking.unstake(stakeAmount, false); // trigger = false

        // Rebase should not be called if epoch hasn't ended
        assertEq(sApiary.rebaseCount(), rebaseCountBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        REBASING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Rebase_TriggersWhenEpochEnds() public {
        // Move past epoch end
        vm.roll(firstEpochBlock + 1);

        // HIGH-04 Fix: rebase() now restricted to owner/distributor
        vm.prank(owner);
        staking.rebase();

        assertGt(sApiary.rebaseCount(), 0);
    }

    function test_Rebase_UpdatesEpochNumber() public {
        vm.roll(firstEpochBlock + 1);

        vm.prank(owner);
        staking.rebase();

        (, uint256 number,,) = staking.epoch();
        assertEq(number, FIRST_EPOCH_NUMBER + 1);
    }

    function test_Rebase_UpdatesEndBlock() public {
        vm.roll(firstEpochBlock + 1);

        vm.prank(owner);
        staking.rebase();

        (,, uint256 endBlock,) = staking.epoch();
        assertEq(endBlock, firstEpochBlock + EPOCH_LENGTH);
    }

    function test_Rebase_CallsDistributor() public {
        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.DISTRIBUTOR, address(distributor));

        vm.roll(firstEpochBlock + 1);

        vm.prank(owner);
        staking.rebase();

        assertGt(distributor.distributeCount(), 0);
    }

    function test_Rebase_EmitsEvent() public {
        vm.roll(firstEpochBlock + 1);

        vm.expectEmit(true, false, false, true);
        emit Rebased(FIRST_EPOCH_NUMBER + 1, 0); // distribute = 0 in Phase 1

        vm.prank(owner);
        staking.rebase();
    }

    function test_Rebase_NoOpBeforeEpochEnd() public {
        // Don't move past epoch end

        uint256 rebaseCountBefore = sApiary.rebaseCount();

        vm.prank(owner);
        staking.rebase();

        assertEq(sApiary.rebaseCount(), rebaseCountBefore);
    }

    /*//////////////////////////////////////////////////////////////
                    PHASE 1 BEHAVIOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Phase1_DistributeAlwaysZero() public {
        // In Phase 1, distribute should always be 0
        // because contractBalance <= staked

        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.roll(firstEpochBlock + 1);

        // HIGH-04 Fix: rebase() now restricted to owner/distributor
        vm.prank(owner);
        staking.rebase();

        (,,, uint256 distribute) = staking.epoch();
        assertEq(distribute, 0);
    }

    function test_Phase1_NoYieldDistribution() public {
        uint256 stakeAmount = 10_000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.roll(firstEpochBlock + 1);

        // HIGH-04 Fix: rebase() now restricted to owner/distributor
        vm.prank(owner);
        staking.rebase();

        // Check that lastRebaseProfit was 0
        assertEq(sApiary.lastRebaseProfit(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    LOCKER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GiveLockBonus() public {
        uint256 bonusAmount = 1000e9;

        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        vm.prank(locker);
        staking.giveLockBonus(bonusAmount);

        assertEq(staking.totalBonus(), bonusAmount);
        assertEq(sApiary.balanceOf(locker), bonusAmount);
    }

    function test_ReturnLockBonus() public {
        uint256 bonusAmount = 1000e9;

        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        // Give bonus first
        vm.prank(locker);
        staking.giveLockBonus(bonusAmount);

        // Approve and return
        vm.prank(locker);
        sApiary.approve(address(staking), bonusAmount);

        vm.prank(locker);
        staking.returnLockBonus(bonusAmount);

        assertEq(staking.totalBonus(), 0);
    }

    function testRevert_GiveLockBonus_OnlyLocker() public {
        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        vm.startPrank(attacker);

        vm.expectRevert(ApiaryStaking.APIARY__ONLY_LOCKER.selector);
        staking.giveLockBonus(1000e9);

        vm.stopPrank();
    }

    function testRevert_ReturnLockBonus_OnlyLocker() public {
        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        vm.startPrank(attacker);

        vm.expectRevert(ApiaryStaking.APIARY__ONLY_LOCKER.selector);
        staking.returnLockBonus(1000e9);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause() public {
        vm.prank(owner);
        staking.pause();

        assertTrue(staking.paused());
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        staking.pause();
        staking.unpause();
        vm.stopPrank();

        assertFalse(staking.paused());
    }

    function test_SetContract_Distributor() public {
        vm.expectEmit(true, false, false, false);
        emit DistributorSet(address(distributor));

        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.DISTRIBUTOR, address(distributor));

        assertEq(staking.distributor(), address(distributor));
    }

    function test_SetContract_Locker() public {
        vm.expectEmit(true, false, false, false);
        emit LockerSet(locker);

        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        assertEq(staking.locker(), locker);
    }

    function testRevert_SetContract_LockerAlreadySet() public {
        vm.startPrank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        vm.expectRevert(ApiaryStaking.APIARY__LOCKER_ALREADY_SET.selector);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, makeAddr("newLocker"));

        vm.stopPrank();
    }

    function testRevert_SetContract_ZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(ApiaryStaking.APIARY__INVALID_ADDRESS.selector);
        staking.setContract(ApiaryStaking.CONTRACTS.DISTRIBUTOR, address(0));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_Pause_OnlyOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        staking.pause();

        vm.stopPrank();
    }

    function testRevert_Unpause_OnlyOwner() public {
        vm.prank(owner);
        staking.pause();

        vm.startPrank(attacker);

        vm.expectRevert();
        staking.unpause();

        vm.stopPrank();
    }

    function testRevert_SetContract_OnlyOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        staking.setContract(ApiaryStaking.CONTRACTS.DISTRIBUTOR, address(distributor));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_Stake_WhenPaused() public {
        vm.prank(owner);
        staking.pause();

        vm.startPrank(user1);

        vm.expectRevert();
        staking.stake(10_000e9, user1);

        vm.stopPrank();
    }

    function testRevert_Unstake_WhenPaused() public {
        // Stake first
        vm.prank(user1);
        staking.stake(10_000e9, user1);

        // Pause
        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        sApiary.approve(address(staking), 10_000e9);

        vm.startPrank(user1);

        vm.expectRevert();
        staking.unstake(10_000e9, false);

        vm.stopPrank();
    }

    function test_Index_ReturnsCorrectValue() public view {
        assertEq(staking.index(), sApiary.index());
    }

    function test_ContractBalance_IncludesBonus() public {
        uint256 stakeAmount = 10_000e9;
        uint256 bonusAmount = 1000e9;

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(owner);
        staking.setContract(ApiaryStaking.CONTRACTS.LOCKER, locker);

        vm.prank(locker);
        staking.giveLockBonus(bonusAmount);

        // contractBalance = APIARY balance + totalBonus
        assertEq(staking.contractBalance(), stakeAmount + bonusAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Stake(uint256 amount) public {
        // Bound to user1's balance
        amount = bound(amount, 1, 100_000e9);

        vm.prank(user1);
        staking.stake(amount, user1);

        assertEq(sApiary.balanceOf(user1), amount);
        assertEq(staking.totalStaked(), amount);
    }

    function testFuzz_StakeAndUnstake(uint256 stakeAmount, uint256 unstakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, 100_000e9);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.prank(user1);
        staking.stake(stakeAmount, user1);

        vm.prank(user1);
        sApiary.approve(address(staking), unstakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount, false);

        assertEq(staking.totalStaked(), stakeAmount - unstakeAmount);
    }
}
