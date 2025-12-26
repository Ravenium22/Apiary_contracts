// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { sApiary } from "../src/sApiary.sol";

/**
 * @title sApiaryTest
 * @notice Comprehensive test suite for rebasing staked APIARY token
 * @dev Tests deployment, rebasing mechanism, balance calculations, and transfers
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Rebase Mechanism
 * 3. Balance Functions (gonsForBalance, balanceForGons)
 * 4. Transfers with Rebasing Math
 * 5. Circulating Supply Tracking
 * 6. Approval Functions
 * 7. Access Control
 * 8. Edge Cases
 */
contract sApiaryTest is Test {
    sApiary public sToken;

    // Test accounts
    address public owner = makeAddr("owner");
    address public stakingContract = makeAddr("staking");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    // Constants from sApiary contract
    uint256 public constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10 ** 9;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LogSupply(uint256 indexed epoch, uint256 timestamp, uint256 totalSupply);
    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
    event LogStakingContractUpdated(address stakingContract);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(owner);
        sToken = new sApiary(owner);

        // Initialize with staking contract (must be called by initializer = deployer = owner)
        sToken.initialize(stakingContract);

        // Set initial index
        sToken.setIndex(1e9);
        vm.stopPrank();

        // Create circulating supply by transferring from staking contract to user
        // This is necessary for rebase tests to work (avoid division by zero)
        vm.prank(stakingContract);
        sToken.transfer(user1, 1_000_000e9);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_Name() public view {
        assertEq(sToken.name(), "Staked Apiary");
    }

    function test_Deployment_Symbol() public view {
        assertEq(sToken.symbol(), "sAPIARY");
    }

    function test_Deployment_Decimals() public view {
        assertEq(sToken.decimals(), 9);
    }

    function test_Deployment_InitialSupply() public view {
        assertEq(sToken.totalSupply(), INITIAL_FRAGMENTS_SUPPLY);
    }

    function test_Deployment_Owner() public view {
        assertEq(sToken.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_SetsStakingContract() public {
        // Deploy fresh contract
        sApiary freshToken = new sApiary(owner);

        freshToken.initialize(stakingContract);

        assertEq(freshToken.stakingContract(), stakingContract);
    }

    function test_Initialize_MintsToStaking() public {
        sApiary freshToken = new sApiary(owner);

        freshToken.initialize(stakingContract);

        assertEq(freshToken.balanceOf(stakingContract), INITIAL_FRAGMENTS_SUPPLY);
    }

    function test_Initialize_EmitsEvents() public {
        sApiary freshToken = new sApiary(owner);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), stakingContract, INITIAL_FRAGMENTS_SUPPLY);

        vm.expectEmit(true, false, false, false);
        emit LogStakingContractUpdated(stakingContract);

        freshToken.initialize(stakingContract);
    }

    function testRevert_Initialize_NotInitializer() public {
        sApiary freshToken = new sApiary(owner);

        vm.prank(attacker);
        vm.expectRevert("sApiary: caller is not initializer");
        freshToken.initialize(stakingContract);
    }

    function testRevert_Initialize_ZeroAddress() public {
        sApiary freshToken = new sApiary(owner);

        vm.expectRevert("sApiary: invalid staking contract");
        freshToken.initialize(address(0));
    }

    function test_SetIndex_Success() public {
        sApiary freshToken = new sApiary(owner);
        freshToken.initialize(stakingContract);

        vm.prank(owner);
        bool success = freshToken.setIndex(2e9);

        assertTrue(success);
    }

    function testRevert_SetIndex_AlreadySet() public {
        // Index already set in setUp
        vm.prank(owner);
        vm.expectRevert("sApiary: index already set");
        sToken.setIndex(2e9);
    }

    function testRevert_SetIndex_NotOwner() public {
        sApiary freshToken = new sApiary(owner);
        freshToken.initialize(stakingContract);

        vm.prank(attacker);
        vm.expectRevert();
        freshToken.setIndex(2e9);
    }

    /*//////////////////////////////////////////////////////////////
                        REBASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Rebase_OnlyStakingContract() public {
        vm.prank(stakingContract);
        uint256 newSupply = sToken.rebase(1000e9, 1);

        assertGt(newSupply, INITIAL_FRAGMENTS_SUPPLY);
    }

    function test_Rebase_UpdatesSupply() public {
        uint256 profit = 1000e9;

        vm.prank(stakingContract);
        sToken.rebase(profit, 1);

        assertGt(sToken.totalSupply(), INITIAL_FRAGMENTS_SUPPLY);
    }

    function test_Rebase_ZeroProfit() public {
        uint256 supplyBefore = sToken.totalSupply();

        vm.prank(stakingContract);
        uint256 newSupply = sToken.rebase(0, 1);

        assertEq(newSupply, supplyBefore);
    }

    function test_Rebase_EmitsEvents() public {
        uint256 profit = 1000e9;

        // Just verify that events are emitted (checking indexed params only)
        vm.expectEmit(true, false, false, false);
        emit LogSupply(1, 0, 0);

        vm.prank(stakingContract);
        sToken.rebase(profit, 1);
    }

    function test_Rebase_StoresRebaseData() public {
        uint256 profit = 1000e9;

        vm.prank(stakingContract);
        sToken.rebase(profit, 1);

        assertEq(sToken.getRebasesLength(), 1);
    }

    function test_Rebase_MultipleRebases() public {
        vm.startPrank(stakingContract);

        sToken.rebase(1000e9, 1);
        sToken.rebase(500e9, 2);
        sToken.rebase(250e9, 3);

        vm.stopPrank();

        assertEq(sToken.getRebasesLength(), 3);
    }

    function testRevert_Rebase_NotStakingContract() public {
        vm.prank(attacker);
        vm.expectRevert("sApiary: caller is not staking contract");
        sToken.rebase(1000e9, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    BALANCE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GonsForBalance() public view {
        uint256 amount = 1000e9;
        uint256 gons = sToken.gonsForBalance(amount);

        // gons should be amount * _gonsPerFragment
        assertGt(gons, 0);
    }

    function test_BalanceForGons() public view {
        uint256 amount = 1000e9;
        uint256 gons = sToken.gonsForBalance(amount);
        uint256 balance = sToken.balanceForGons(gons);

        // Should round-trip correctly (may have minor precision loss)
        assertApproxEqAbs(balance, amount, 1);
    }

    function test_BalanceIncreasesAfterRebase() public {
        // Transfer some sAPIARY to user1 from staking contract
        vm.prank(stakingContract);
        sToken.transfer(user1, 10_000e9);

        uint256 balanceBefore = sToken.balanceOf(user1);

        // Rebase
        vm.prank(stakingContract);
        sToken.rebase(1_000_000e9, 1);

        uint256 balanceAfter = sToken.balanceOf(user1);

        // Balance should increase after positive rebase
        assertGt(balanceAfter, balanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    // Note: setUp() transfers 1_000_000e9 to user1 for rebase testing

    function test_Transfer_Success() public {
        uint256 amount = 1000e9;
        uint256 user1BalanceBefore = sToken.balanceOf(user1);

        // Transfer from staking to user1
        vm.prank(stakingContract);
        bool success = sToken.transfer(user1, amount);

        assertTrue(success);
        assertEq(sToken.balanceOf(user1), user1BalanceBefore + amount);
    }

    function test_Transfer_EmitsEvent() public {
        uint256 amount = 1000e9;

        vm.expectEmit(true, true, false, true);
        emit Transfer(stakingContract, user2, amount);

        vm.prank(stakingContract);
        sToken.transfer(user2, amount);
    }

    function test_Transfer_UpdatesBalances() public {
        uint256 amount = 1000e9;

        uint256 stakingBalanceBefore = sToken.balanceOf(stakingContract);
        uint256 user2BalanceBefore = sToken.balanceOf(user2);

        vm.prank(stakingContract);
        sToken.transfer(user2, amount);

        assertEq(sToken.balanceOf(stakingContract), stakingBalanceBefore - amount);
        assertEq(sToken.balanceOf(user2), user2BalanceBefore + amount);
    }

    function testRevert_Transfer_InsufficientBalance() public {
        // user2 has 0 balance (user1 has the initial circulating tokens)
        vm.prank(user2);

        vm.expectRevert("sApiary: insufficient balance");
        sToken.transfer(attacker, 100e9);
    }

    function test_TransferFrom_Success() public {
        uint256 amount = 1000e9;
        uint256 user2BalanceBefore = sToken.balanceOf(user2);

        // user1 already has tokens from setUp, user1 approves user2
        vm.prank(user1);
        sToken.approve(user2, amount);

        // user2 transfers from user1 to themselves
        vm.prank(user2);
        bool success = sToken.transferFrom(user1, user2, amount);

        assertTrue(success);
        assertEq(sToken.balanceOf(user2), user2BalanceBefore + amount);
    }

    function test_TransferFrom_UpdatesAllowance() public {
        uint256 amount = 1000e9;

        // user1 already has tokens from setUp
        vm.prank(user1);
        sToken.approve(user2, amount);

        vm.prank(user2);
        sToken.transferFrom(user1, user2, amount / 2);

        assertEq(sToken.allowance(user1, user2), amount / 2);
    }

    /*//////////////////////////////////////////////////////////////
                    CIRCULATING SUPPLY TESTS
    //////////////////////////////////////////////////////////////*/

    // Note: setUp() transfers 1_000_000e9 to user1 to enable rebase testing
    uint256 internal constant INITIAL_CIRCULATING = 1_000_000e9;

    function test_CirculatingSupply_InitiallyZero() public {
        // Deploy fresh contract to test initial state
        vm.startPrank(owner);
        sApiary freshToken = new sApiary(owner);
        freshToken.initialize(stakingContract);
        vm.stopPrank();

        // All supply is in staking contract initially
        assertEq(freshToken.circulatingSupply(), 0);
    }

    function test_CirculatingSupply_IncreasesOnTransfer() public {
        uint256 amount = 1000e9;

        vm.prank(stakingContract);
        sToken.transfer(user2, amount);

        // Circulating should increase by amount
        assertEq(sToken.circulatingSupply(), INITIAL_CIRCULATING + amount);
    }

    function test_CirculatingSupply_DecreasesOnReturnToStaking() public {
        // Transfer some from user1 back to staking
        uint256 amount = 500e9;

        vm.prank(user1);
        sToken.transfer(stakingContract, amount);

        assertEq(sToken.circulatingSupply(), INITIAL_CIRCULATING - amount);
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_Success() public {
        uint256 amount = 1000e9;

        vm.expectEmit(true, true, false, true);
        emit Approval(user1, user2, amount);

        vm.prank(user1);
        bool success = sToken.approve(user2, amount);

        assertTrue(success);
        assertEq(sToken.allowance(user1, user2), amount);
    }

    function test_IncreaseAllowance() public {
        uint256 initial = 1000e9;
        uint256 increase = 500e9;

        vm.startPrank(user1);
        sToken.approve(user2, initial);
        sToken.increaseAllowance(user2, increase);
        vm.stopPrank();

        assertEq(sToken.allowance(user1, user2), initial + increase);
    }

    function test_DecreaseAllowance() public {
        uint256 initial = 1000e9;
        uint256 decrease = 500e9;

        vm.startPrank(user1);
        sToken.approve(user2, initial);
        sToken.decreaseAllowance(user2, decrease);
        vm.stopPrank();

        assertEq(sToken.allowance(user1, user2), initial - decrease);
    }

    function test_DecreaseAllowance_ToZero() public {
        uint256 initial = 1000e9;

        vm.startPrank(user1);
        sToken.approve(user2, initial);
        sToken.decreaseAllowance(user2, initial + 100e9); // More than allowance
        vm.stopPrank();

        assertEq(sToken.allowance(user1, user2), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        INDEX TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Index_ReturnsCorrectValue() public view {
        // Index was set to 1e9 in setUp
        assertGt(sToken.index(), 0);
    }

    function test_Index_IncreasesAfterRebase() public {
        uint256 indexBefore = sToken.index();

        vm.prank(stakingContract);
        sToken.rebase(1_000_000e9, 1);

        uint256 indexAfter = sToken.index();

        // Index should increase after positive rebase
        assertGt(indexAfter, indexBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Rebase_LargeProfit() public {
        // Large profit shouldn't overflow
        uint256 largeProfit = 100_000_000e9; // 100 million tokens

        vm.prank(stakingContract);
        uint256 newSupply = sToken.rebase(largeProfit, 1);

        assertGt(newSupply, INITIAL_FRAGMENTS_SUPPLY);
    }

    function test_Transfer_AfterMultipleRebases() public {
        // Transfer some to user
        vm.prank(stakingContract);
        sToken.transfer(user1, 10_000e9);

        // Multiple rebases
        vm.startPrank(stakingContract);
        sToken.rebase(1_000_000e9, 1);
        sToken.rebase(500_000e9, 2);
        vm.stopPrank();

        // User should still be able to transfer
        uint256 userBalance = sToken.balanceOf(user1);

        vm.prank(user1);
        bool success = sToken.transfer(user2, userBalance / 2);

        assertTrue(success);
        assertApproxEqAbs(sToken.balanceOf(user2), userBalance / 2, 1);
    }

    function test_GetRebasesLength() public {
        assertEq(sToken.getRebasesLength(), 0);

        vm.prank(stakingContract);
        sToken.rebase(1000e9, 1);

        assertEq(sToken.getRebasesLength(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Rebase(uint256 profit) public {
        // Bound profit to reasonable amount to avoid overflow
        profit = bound(profit, 0, 1_000_000_000e9);

        uint256 supplyBefore = sToken.totalSupply();

        vm.prank(stakingContract);
        sToken.rebase(profit, 1);

        if (profit == 0) {
            assertEq(sToken.totalSupply(), supplyBefore);
        } else {
            assertGt(sToken.totalSupply(), supplyBefore);
        }
    }

    function testFuzz_Transfer(uint256 amount) public {
        // Bound to staking balance (staking balance = INITIAL - user1 balance from setUp)
        uint256 stakingBalance = sToken.balanceOf(stakingContract);
        amount = bound(amount, 0, stakingBalance);

        if (amount == 0) return;

        uint256 user2BalanceBefore = sToken.balanceOf(user2);
        uint256 circulatingBefore = sToken.circulatingSupply();

        vm.prank(stakingContract);
        sToken.transfer(user2, amount);

        assertEq(sToken.balanceOf(user2), user2BalanceBefore + amount);
        assertEq(sToken.circulatingSupply(), circulatingBefore + amount);
    }

    function testFuzz_GonsRoundTrip(uint256 amount) public view {
        // Bound to reasonable amounts
        amount = bound(amount, 1, INITIAL_FRAGMENTS_SUPPLY);

        uint256 gons = sToken.gonsForBalance(amount);
        uint256 balance = sToken.balanceForGons(gons);

        // Should round-trip with minimal precision loss
        assertApproxEqAbs(balance, amount, 1);
    }
}
