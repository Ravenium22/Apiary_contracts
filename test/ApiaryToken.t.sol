// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryToken } from "../src/ApiaryToken.sol";

/**
 * @title ApiaryTokenTest
 * @notice Comprehensive test suite for APIARY token
 * @dev Tests deployment, transfers, minting, burning, and access control
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Initial Supply
 * 3. Transfers
 * 4. Minter Management
 * 5. Allocation Limits
 * 6. Minting
 * 7. Burning
 * 8. Staking Time Updates
 * 9. Fuzz Tests
 */
contract ApiaryTokenTest is Test {
    ApiaryToken public token;

    // Test accounts
    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public stakingContract = makeAddr("staking");
    address public attacker = makeAddr("attacker");

    // Constants from token contract
    uint256 public constant INITIAL_SUPPLY = 200_000e9; // 200,000 APIARY with 9 decimals
    uint256 public constant PRE_BONDS_ALLOCATION = 110_000e9;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MinterAllocationSet(address indexed minter, uint256 indexed maxNumberOfTokens);
    event MinterAllocationIncreased(address indexed minter, uint256 indexed additionalTokens);
    event InitialSupplyMinted(address indexed recipient, uint256 indexed amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(admin);
        token = new ApiaryToken(admin);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_Name() public view {
        assertEq(token.name(), "Apiary");
    }

    function test_Deployment_Symbol() public view {
        assertEq(token.symbol(), "APIARY");
    }

    function test_Deployment_Decimals() public view {
        assertEq(token.decimals(), 9);
    }

    function test_Deployment_AdminHasDefaultAdminRole() public view {
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function test_Deployment_Owner() public view {
        assertEq(token.owner(), admin);
    }

    function testRevert_Deployment_ZeroAddress() public {
        // OpenZeppelin's Ownable constructor checks for zero address first
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new ApiaryToken(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL SUPPLY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialSupply_MintedToDeployer() public view {
        // Admin deployed the contract, so admin should have the initial supply
        assertEq(token.balanceOf(admin), INITIAL_SUPPLY);
    }

    function test_InitialSupply_TotalSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_InitialSupply_TotalMintedSupply() public view {
        assertEq(token.totalMintedSupply(), INITIAL_SUPPLY);
    }

    function test_InitialSupply_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit InitialSupplyMinted(address(this), INITIAL_SUPPLY);

        // Deploy from test contract (this)
        new ApiaryToken(admin);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer_Success() public {
        uint256 amount = 1000e9;

        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true);
        emit Transfer(admin, user1, amount);

        bool success = token.transfer(user1, amount);

        assertTrue(success);
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(admin), INITIAL_SUPPLY - amount);

        vm.stopPrank();
    }

    function test_Transfer_NoFeesDeducted() public {
        uint256 amount = 1000e9;

        vm.startPrank(admin);
        token.transfer(user1, amount);
        vm.stopPrank();

        // User1 receives exact amount (no fees)
        assertEq(token.balanceOf(user1), amount);
        // Total supply unchanged (no burns)
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_Transfer_MultipleTransfers() public {
        uint256 amount1 = 1000e9;
        uint256 amount2 = 500e9;

        vm.startPrank(admin);
        token.transfer(user1, amount1);
        token.transfer(user2, amount2);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount1);
        assertEq(token.balanceOf(user2), amount2);
        assertEq(token.balanceOf(admin), INITIAL_SUPPLY - amount1 - amount2);
    }

    function testRevert_Transfer_ToZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(ApiaryToken.APIARY__INVALID_ADDRESS.selector);
        token.transfer(address(0), 100e9);

        vm.stopPrank();
    }

    function testRevert_Transfer_InsufficientBalance() public {
        vm.startPrank(user1); // user1 has 0 balance

        vm.expectRevert(ApiaryToken.APIARY__TRANSFER_AMOUNT_EXCEEDS_BALANCE.selector);
        token.transfer(user2, 100e9);

        vm.stopPrank();
    }

    function test_TransferFrom_Success() public {
        uint256 amount = 1000e9;

        vm.prank(admin);
        token.approve(user1, amount);

        vm.prank(user1);
        token.transferFrom(admin, user2, amount);

        assertEq(token.balanceOf(user2), amount);
        assertEq(token.allowance(admin, user1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    MINTER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetAllocationLimit_GrantsMinterRole() public {
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");

        vm.startPrank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);
        vm.stopPrank();

        assertTrue(token.hasRole(MINTER_ROLE, minter));
    }

    function test_SetAllocationLimit_SetsLimit() public {
        vm.startPrank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);
        vm.stopPrank();

        assertEq(token.allocationLimits(minter), PRE_BONDS_ALLOCATION);
    }

    function test_SetAllocationLimit_EmitsEvent() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, false, false);
        emit MinterAllocationSet(minter, PRE_BONDS_ALLOCATION);

        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.stopPrank();
    }

    function testRevert_SetAllocationLimit_AlreadySet() public {
        vm.startPrank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.expectRevert(ApiaryToken.APIARY__ALLOCATION_LIMIT_ALREADY_SET.selector);
        token.setAllocationLimit(minter, 50_000e9);

        vm.stopPrank();
    }

    function testRevert_SetAllocationLimit_NotAdmin() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    ALLOCATION LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IncreaseAllocationLimit_Success() public {
        uint256 additional = 50_000e9;

        vm.startPrank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);
        
        vm.expectEmit(true, true, false, false);
        emit MinterAllocationIncreased(minter, additional);

        token.increaseAllocationLimit(minter, additional);
        vm.stopPrank();

        assertEq(token.allocationLimits(minter), PRE_BONDS_ALLOCATION + additional);
    }

    function testRevert_IncreaseAllocationLimit_NotMinter() public {
        vm.startPrank(admin);

        vm.expectRevert(ApiaryToken.APIARY__NOT_A_MINTER.selector);
        token.increaseAllocationLimit(user1, 50_000e9);

        vm.stopPrank();
    }

    function testRevert_IncreaseAllocationLimit_NotAdmin() public {
        vm.startPrank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);
        vm.stopPrank();

        vm.startPrank(attacker);

        vm.expectRevert();
        token.increaseAllocationLimit(minter, 50_000e9);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        uint256 mintAmount = 10_000e9;

        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.prank(minter);
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.allocationLimits(minter), PRE_BONDS_ALLOCATION - mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
        assertEq(token.totalMintedSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_Mint_DecreasesAllocation() public {
        uint256 mintAmount = 10_000e9;

        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        uint256 allocationBefore = token.allocationLimits(minter);

        vm.prank(minter);
        token.mint(user1, mintAmount);

        assertEq(token.allocationLimits(minter), allocationBefore - mintAmount);
    }

    function test_Mint_MultipleMints() public {
        uint256 mint1 = 10_000e9;
        uint256 mint2 = 20_000e9;
        uint256 mint3 = 30_000e9;

        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.startPrank(minter);
        token.mint(user1, mint1);
        token.mint(user1, mint2);
        token.mint(user2, mint3);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), mint1 + mint2);
        assertEq(token.balanceOf(user2), mint3);
        assertEq(token.allocationLimits(minter), PRE_BONDS_ALLOCATION - mint1 - mint2 - mint3);
    }

    function test_Mint_UpToExactLimit() public {
        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.prank(minter);
        token.mint(user1, PRE_BONDS_ALLOCATION);

        assertEq(token.balanceOf(user1), PRE_BONDS_ALLOCATION);
        assertEq(token.allocationLimits(minter), 0);
    }

    function testRevert_Mint_ExceedsAllocation() public {
        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.startPrank(minter);

        vm.expectRevert(ApiaryToken.APIARY__MAX_MINT_ALLOC_EXCEEDED.selector);
        token.mint(user1, PRE_BONDS_ALLOCATION + 1);

        vm.stopPrank();
    }

    function testRevert_Mint_NotMinter() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        token.mint(user1, 1000e9);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BURNING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn_OwnTokens() public {
        uint256 burnAmount = 1000e9;

        vm.startPrank(admin);

        uint256 balanceBefore = token.balanceOf(admin);
        uint256 supplyBefore = token.totalSupply();

        token.burn(burnAmount);

        assertEq(token.balanceOf(admin), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), supplyBefore - burnAmount);
        // totalMintedSupply should NOT decrease on burn
        assertEq(token.totalMintedSupply(), INITIAL_SUPPLY);

        vm.stopPrank();
    }

    function test_BurnFrom_WithAllowance() public {
        uint256 burnAmount = 1000e9;

        // Admin transfers to user1, then user1 approves admin to burn
        vm.prank(admin);
        token.transfer(user1, burnAmount * 2);

        vm.prank(user1);
        token.approve(admin, burnAmount);

        vm.prank(admin);
        token.burnFrom(user1, burnAmount);

        assertEq(token.balanceOf(user1), burnAmount);
        assertEq(token.allowance(user1, admin), 0);
    }

    function testRevert_BurnFrom_InsufficientAllowance() public {
        uint256 burnAmount = 1000e9;

        vm.prank(admin);
        token.transfer(user1, burnAmount);

        vm.prank(user1);
        token.approve(admin, burnAmount - 1);

        vm.startPrank(admin);

        vm.expectRevert(ApiaryToken.APIARY__BURN_AMOUNT_EXCEEDS_ALLOWANCE.selector);
        token.burnFrom(user1, burnAmount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    STAKING TIME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateLastStakedTime_Success() public {
        // L-06 Fix: Two-step pattern for setting staking contract
        vm.prank(admin);
        token.setStaking(stakingContract);

        vm.prank(stakingContract);
        token.acceptStaking();

        // Update staked time
        vm.prank(stakingContract);
        token.updateLastStakedTime(user1);

        assertEq(token.lastTimeStaked(user1), uint48(block.timestamp));
    }

    function testRevert_UpdateLastStakedTime_NotStaking() public {
        // L-06 Fix: Two-step pattern for setting staking contract
        vm.prank(admin);
        token.setStaking(stakingContract);

        vm.prank(stakingContract);
        token.acceptStaking();

        vm.startPrank(attacker);

        // LOW-02 Fix: Now uses custom error instead of require string
        vm.expectRevert(abi.encodeWithSignature("VAULT_OWNED__NOT_STAKING()"));
        token.updateLastStakedTime(user1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT OWNED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetVault() public {
        address vault = makeAddr("vault");

        // L-06 Fix: Two-step pattern — set pending, then accept
        vm.prank(admin);
        token.setVault(vault);

        vm.prank(vault);
        token.acceptVault();

        assertEq(token.vault(), vault);
    }

    function test_SetStaking() public {
        // L-06 Fix: Two-step pattern — set pending, then accept
        vm.prank(admin);
        token.setStaking(stakingContract);

        vm.prank(stakingContract);
        token.acceptStaking();

        assertEq(token.staking(), stakingContract);
    }

    function test_SetLockUp() public {
        address lockup = makeAddr("lockup");

        // L-06 Fix: Two-step pattern — set pending, then accept
        vm.prank(admin);
        token.setLockUp(lockup);

        vm.prank(lockup);
        token.acceptLockUp();

        assertEq(token.lockUp(), lockup);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Transfer(uint256 amount) public {
        // Bound amount to valid range
        amount = bound(amount, 0, INITIAL_SUPPLY);

        vm.prank(admin);
        
        if (amount == 0) {
            // Zero amount transfers should still work
            token.transfer(user1, amount);
            assertEq(token.balanceOf(user1), 0);
        } else {
            token.transfer(user1, amount);
            assertEq(token.balanceOf(user1), amount);
            assertEq(token.balanceOf(admin), INITIAL_SUPPLY - amount);
        }
    }

    function testFuzz_Mint(uint256 amount) public {
        // Bound amount to valid allocation
        amount = bound(amount, 0, PRE_BONDS_ALLOCATION);

        vm.prank(admin);
        token.setAllocationLimit(minter, PRE_BONDS_ALLOCATION);

        vm.prank(minter);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.allocationLimits(minter), PRE_BONDS_ALLOCATION - amount);
    }

    function testFuzz_Burn(uint256 amount) public {
        // Bound amount to valid range
        amount = bound(amount, 0, INITIAL_SUPPLY);

        vm.prank(admin);
        token.burn(amount);

        assertEq(token.balanceOf(admin), INITIAL_SUPPLY - amount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - amount);
    }

    function testFuzz_SetAllocationLimit(uint256 allocation) public {
        vm.prank(admin);
        token.setAllocationLimit(minter, allocation);

        assertEq(token.allocationLimits(minter), allocation);
    }
}
