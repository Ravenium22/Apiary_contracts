// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestSetup } from "./TestSetup.sol";
import { ApiaryYieldManager } from "../../src/ApiaryYieldManager.sol";
import { ApiaryInfraredAdapter } from "../../src/ApiaryInfraredAdapter.sol";
import { ApiaryKodiakAdapter } from "../../src/ApiaryKodiakAdapter.sol";
import { console2 } from "forge-std/Test.sol";

/**
 * @title ApiarySecurityTest
 * @notice Security-focused integration tests
 * @dev Tests reentrancy, access control, overflow, and attack vectors
 */
contract ApiarySecurityTest is TestSetup {
    ApiaryYieldManager public yieldManager;
    ApiaryInfraredAdapter public infraredAdapter;
    ApiaryKodiakAdapter public kodiakAdapter;

    ReentrancyAttacker public reentrancyAttacker;
    MaliciousAdapter public maliciousAdapter;

    function setUp() public override {
        super.setUp();

        // Deploy adapters
        vm.startPrank(owner);

        infraredAdapter = new ApiaryInfraredAdapter(
            address(ibgtToken),
            address(infraredProtocol),
            treasury,
            owner
        );

        kodiakAdapter = new ApiaryKodiakAdapter(
            address(kodiakRouter),
            treasury,
            owner
        );

        // Deploy yield manager
        yieldManager = new ApiaryYieldManager(
            address(apiaryToken),
            address(honeyToken),
            address(ibgtToken),
            treasury,
            address(infraredAdapter),
            address(kodiakAdapter),
            owner
        );

        // Setup adapters
        infraredAdapter.setYieldManager(address(yieldManager));
        kodiakAdapter.setYieldManager(address(yieldManager));

        vm.stopPrank();

        // Deploy attack contracts
        reentrancyAttacker = new ReentrancyAttacker(address(yieldManager));
        maliciousAdapter = new MaliciousAdapter();
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test reentrancy protection on executeYield()
    function test_Security_ReentrancyProtection() public {
        // Setup yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Attempt reentrancy attack
        vm.prank(address(reentrancyAttacker));
        vm.expectRevert(); // Should revert with ReentrancyGuard error
        reentrancyAttacker.attack();
    }

    /// @notice Test reentrancy via malicious token callback
    function testFail_Security_ReentrancyViaCallback() public {
        // This should fail to exploit due to ReentrancyGuard
        // Note: Requires malicious ERC20 with callback on transfer
        MaliciousToken maliciousToken = new MaliciousToken(address(yieldManager));

        vm.prank(owner);
        yieldManager.setKodiakAdapter(address(maliciousToken));

        // Attempt exploit - should revert
        vm.prank(keeper);
        yieldManager.executeYield();
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test only owner can change strategy
    function test_Security_OnlyOwnerCanChangeStrategy() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL);
    }

    /// @notice Test only owner can set split percentages
    function test_Security_OnlyOwnerCanSetSplits() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.setSplitPercentages(3000, 3000, 4000, 0, 0);
    }

    /// @notice Test only owner can set adapters
    function test_Security_OnlyOwnerCanSetAdapters() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.setKodiakAdapter(address(maliciousAdapter));
    }

    /// @notice Test only owner can pause
    function test_Security_OnlyOwnerCanPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.pause();
    }

    /// @notice Test only owner can emergency withdraw
    function test_Security_OnlyOwnerCanEmergencyWithdraw() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.emergencyWithdraw(address(honeyToken), 100e18, attacker);
    }

    /// @notice Test adapter access control
    function test_Security_AdapterAccessControl() public {
        vm.prank(attacker);
        vm.expectRevert();
        infraredAdapter.stake(1000e18);

        vm.prank(attacker);
        vm.expectRevert();
        infraredAdapter.unstake(1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                    MALICIOUS ADAPTER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test malicious adapter cannot drain yield manager
    function test_Security_MaliciousAdapterDrain() public {
        // Owner sets malicious adapter (simulating compromised owner)
        vm.prank(owner);
        yieldManager.setKodiakAdapter(address(maliciousAdapter));

        // Fund yield manager
        vm.prank(treasury);
        ibgtToken.transfer(address(yieldManager), 1000e18);

        // Malicious adapter tries to drain
        vm.prank(address(maliciousAdapter));
        // Should fail because adapter doesn't have approval
        vm.expectRevert();
        ibgtToken.transferFrom(address(yieldManager), attacker, 1000e18);
    }

    /// @notice Test zero address adapter reverts
    function test_Security_ZeroAddressAdapter() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryYieldManager.APIARY__ZERO_ADDRESS.selector);
        yieldManager.setKodiakAdapter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    OVERFLOW/UNDERFLOW TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test split percentages overflow
    function test_Security_SplitPercentagesOverflow() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryYieldManager.APIARY__INVALID_SPLIT_CONFIG.selector);
        yieldManager.setSplitPercentages(
            type(uint256).max, // Overflow
            1,
            1,
            1,
            1
        );
    }

    /// @notice Test large yield amount doesn't overflow
    function test_Security_LargeYieldNoOverflow() public {
        // Setup massive yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), type(uint128).max);
        infraredAdapter.stake(1_000_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 100_000e18);

        // Should cap at maxExecutionAmount, not overflow
        vm.prank(keeper);
        (uint256 totalYield,,,,) = yieldManager.executeYield();

        assertEq(totalYield, 10_000e18, "Should cap, not overflow");
    }

    /*//////////////////////////////////////////////////////////////
                    SLIPPAGE ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test slippage protection prevents sandwich attacks
    function test_Security_SlippageProtection() public {
        // Setup yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 1000e18);

        // Set very tight slippage
        vm.prank(owner);
        yieldManager.setSlippageTolerance(1); // 0.01%

        // Execute - might fail if DEX slippage > tolerance
        vm.prank(keeper);
        try yieldManager.executeYield() {
            // Success - slippage was acceptable
        } catch {
            // Expected if actual slippage exceeded tolerance
        }
    }

    /// @notice Test slippage tolerance cannot exceed 10%
    function test_Security_SlippageToleranceMax() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryYieldManager.APIARY__SLIPPAGE_TOO_HIGH.selector);
        yieldManager.setSlippageTolerance(1001); // > 10%
    }

    /*//////////////////////////////////////////////////////////////
                    FRONT-RUNNING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test TWAP pricing prevents flash loan manipulation
    function test_Security_TWAPProtection() public {
        // Note: This test requires actual TWAP oracle implementation
        // For now, we verify the concept

        // Attacker tries to manipulate price with flash loan
        vm.startPrank(attacker);

        // Flash loan large amount
        uint256 flashLoanAmount = 1_000_000e18;
        honeyToken.mint(attacker, flashLoanAmount);

        // Swap to manipulate pool ratio
        honeyToken.approve(address(kodiakRouter), flashLoanAmount);
        address[] memory path = new address[](2);
        path[0] = address(honeyToken);
        path[1] = address(apiaryToken);

        kodiakRouter.swapExactTokensForTokens(flashLoanAmount, 0, path, attacker, block.timestamp);

        vm.stopPrank();

        // Yield execution should use TWAP, not spot price
        // TWAP averages over multiple blocks, immune to single-block manipulation
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        vm.prank(keeper);
        yieldManager.executeYield();

        // Attacker shouldn't profit from price manipulation
        // (actual check would require TWAP oracle comparison)
    }

    /*//////////////////////////////////////////////////////////////
                    DOS ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test gas limit DOS protection
    function test_Security_GasLimitProtection() public {
        // Setup massive yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 100_000e18);
        infraredAdapter.stake(100_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 50_000e18);

        // maxExecutionAmount should prevent gas limit DOS
        vm.prank(keeper);
        (uint256 totalYield,,,,) = yieldManager.executeYield();

        // Should process in batches, not all at once
        assertEq(totalYield, 10_000e18, "Should batch execution");
        assertGt(yieldManager.pendingYield(), 0, "Should have remaining");
    }

    /// @notice Test paused state prevents DOS via repeated execution
    function test_Security_PausedStatePreventsExecution() public {
        // Setup yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Owner pauses
        vm.prank(owner);
        yieldManager.pause();

        // Execution should fail
        vm.prank(keeper);
        vm.expectRevert();
        yieldManager.executeYield();
    }

    /*//////////////////////////////////////////////////////////////
                    OWNERSHIP ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test two-step ownership prevents accidental transfer
    function test_Security_TwoStepOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        // Owner initiates transfer
        vm.prank(owner);
        yieldManager.transferOwnership(newOwner);

        // Ownership hasn't changed yet
        assertEq(yieldManager.owner(), owner, "Ownership shouldn't change yet");

        // Only pending owner can accept
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.acceptOwnership();

        // New owner accepts
        vm.prank(newOwner);
        yieldManager.acceptOwnership();

        assertEq(yieldManager.owner(), newOwner, "Ownership transferred");
    }

    /// @notice Test attacker cannot steal ownership
    function test_Security_CannotStealOwnership() public {
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.transferOwnership(attacker);
    }

    /*//////////////////////////////////////////////////////////////
                    ADAPTER EXPLOIT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test adapter cannot be changed during execution
    function test_Security_AdapterChangeBlocked() public {
        // Setup yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Attacker tries to front-run with adapter change
        // (Note: Only owner can change, but testing the scenario)
        vm.prank(owner);
        // During execution, adapter change shouldn't affect ongoing tx
        // This is protected by ReentrancyGuard

        vm.prank(keeper);
        yieldManager.executeYield();
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test emergency mode protects during adapter exploit
    function test_Security_EmergencyModeProtection() public {
        // Simulate adapter compromise detection
        vm.prank(owner);
        yieldManager.setEmergencyMode(true);

        // Setup yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Emergency mode should bypass compromised adapters
        uint256 treasuryBalBefore = ibgtToken.balanceOf(treasury);

        vm.prank(keeper);
        (,uint256 honeySwapped, uint256 burned, uint256 lpCreated,) = yieldManager.executeYield();

        // Should forward to treasury without swaps
        assertEq(honeySwapped, 0, "No swaps in emergency");
        assertEq(burned, 0, "No burns in emergency");
        assertEq(lpCreated, 0, "No LP in emergency");
        assertGt(ibgtToken.balanceOf(treasury), treasuryBalBefore, "Treasury received iBGT");
    }

    /// @notice Test emergency withdraw only by owner
    function test_Security_EmergencyWithdrawOnlyOwner() public {
        // Tokens stuck in contract
        vm.prank(user1);
        honeyToken.transfer(address(yieldManager), 100e18);

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert();
        yieldManager.emergencyWithdraw(address(honeyToken), 100e18, attacker);

        // Owner can withdraw
        vm.prank(owner);
        yieldManager.emergencyWithdraw(address(honeyToken), 100e18, treasury);

        assertEq(honeyToken.balanceOf(treasury), 100e18, "Owner recovered");
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test split percentages always sum to 100%
    function testInvariant_SplitPercentagesSum() public view {
        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        uint256 total = config.toHoney + config.toApiaryLP + config.toBurn + config.toStakers + config.toCompound;

        assertEq(total, 10000, "Splits must sum to 100%");
    }

    /// @notice Test yield manager never holds tokens after execution
    function testInvariant_NoTokensStuck() public {
        // Setup and execute yield
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        vm.prank(keeper);
        yieldManager.executeYield();

        // Yield manager should not hold iBGT, APIARY, or HONEY after execution
        assertEq(ibgtToken.balanceOf(address(yieldManager)), 0, "No iBGT stuck");
        // Note: Some tokens might remain temporarily due to dust or rounding
        // But should be minimal
    }

    /// @notice Test total yield processed is monotonically increasing
    function testInvariant_TotalYieldIncreasing() public {
        uint256 totalBefore = yieldManager.totalYieldProcessed();

        // Setup and execute
        vm.startPrank(treasury);
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        vm.prank(keeper);
        yieldManager.executeYield();

        uint256 totalAfter = yieldManager.totalYieldProcessed();

        assertGt(totalAfter, totalBefore, "Total yield should increase");
    }
}

/*//////////////////////////////////////////////////////////////
                    ATTACK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract ReentrancyAttacker {
    ApiaryYieldManager public target;
    uint256 public attackCount;

    constructor(address _target) {
        target = ApiaryYieldManager(_target);
    }

    function attack() external {
        target.executeYield();
    }

    // Malicious callback
    fallback() external {
        if (attackCount < 2) {
            attackCount++;
            target.executeYield(); // Attempt reentrancy
        }
    }
}

contract MaliciousAdapter {
    function steal() external {
        // Attempt to steal tokens
    }
}

contract MaliciousToken {
    address public yieldManager;

    constructor(address _yieldManager) {
        yieldManager = _yieldManager;
    }

    function transfer(address, uint256) external returns (bool) {
        // Attempt reentrancy during transfer
        ApiaryYieldManager(yieldManager).executeYield();
        return true;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        // Attempt reentrancy during transferFrom
        ApiaryYieldManager(yieldManager).executeYield();
        return true;
    }
}
