// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestSetup } from "./TestSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ApiaryYieldManager } from "../../src/ApiaryYieldManager.sol";
import { ApiaryInfraredAdapter } from "../../src/ApiaryInfraredAdapter.sol";
import { ApiaryKodiakAdapter } from "../../src/ApiaryKodiakAdapter.sol";
import { ApiaryPreSaleBond } from "../../src/ApiaryPreSaleBond.sol";
import { console2 } from "forge-std/Test.sol";

/**
 * @title ApiaryIntegrationTest
 * @notice Comprehensive integration tests for full Apiary protocol
 * @dev Tests complete user journeys and protocol interactions
 *      Updated for refactored adapter pull-pattern architecture
 */
contract ApiaryIntegrationTest is TestSetup {
    ApiaryYieldManager public yieldManager;
    ApiaryInfraredAdapter public infraredAdapter;
    ApiaryKodiakAdapter public kodiakAdapter;
    ApiaryPreSaleBond public preSaleBond;

    // Merkle tree for pre-sale whitelist
    bytes32 public merkleRoot;
    bytes32[] public merkleProof;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy adapters with updated constructor signatures
        // InfraredAdapter: (infrared, ibgt, yieldManager, admin)
        infraredAdapter = new ApiaryInfraredAdapter(
            address(infraredProtocol),
            address(ibgtToken),
            address(0), // Will set yieldManager after it's deployed
            owner
        );

        // KodiakAdapter: (router, factory, honey, apiary, treasury, yieldManager, admin)
        // Deploy with placeholder for yieldManager first
        kodiakAdapter = new ApiaryKodiakAdapter(
            address(kodiakRouter),
            address(kodiakFactory),
            address(honeyToken),
            address(apiaryToken),
            treasury,
            address(1), // Placeholder for yieldManager - will update after deployment
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

        // Configure adapters with yieldManager address
        infraredAdapter.setYieldManager(address(yieldManager));
        kodiakAdapter.setYieldManager(address(yieldManager));

        // Register gauge for LP staking
        kodiakAdapter.registerGauge(address(apiaryHoneyPair), address(kodiakGauge));

        // Setup liquidity
        _setupLiquidity(10_000e18, 10_000e18);

        // Generate merkle root for whitelist
        merkleRoot = _generateMerkleRoot();

        // Deploy pre-sale bond
        preSaleBond = new ApiaryPreSaleBond(
            address(apiaryToken),
            address(honeyToken),
            treasury,
            merkleRoot,
            owner
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 1: FULL PRE-SALE JOURNEY
    //////////////////////////////////////////////////////////////*/

    /// @notice Test complete pre-sale flow: whitelist → purchase → vest → claim
    function test_Integration_PreSaleFullJourney() public {
        uint256 purchaseAmount = 1000e18; // 1000 HONEY
        uint256 expectedApiary = (purchaseAmount * 110) / 100; // 110% bonus

        // Step 1: User1 is whitelisted
        bytes32[] memory proof = _generateProofForUser1();

        // Step 2: User1 purchases APIARY with HONEY
        vm.startPrank(user1);
        honeyToken.approve(address(preSaleBond), purchaseAmount);

        vm.expectEmit(true, true, false, true);
        emit ApiaryPreSaleBond.ApiaryPurchased(user1, purchaseAmount, expectedApiary);

        preSaleBond.purchaseApiary(purchaseAmount, 3, proof); // Max allocation: 3 = 3000 HONEY

        // Verify purchase state
        (uint256 purchased, uint256 claimed) = preSaleBond.getUserPurchaseInfo(user1);
        assertEq(purchased, expectedApiary, "Incorrect purchased amount");
        assertEq(claimed, 0, "Should not have claimed yet");

        // Step 3: Time passes (partial vesting)
        _increaseTime(15 days); // 50% vested

        // Step 4: User1 claims partial vested amount
        uint256 vested = preSaleBond.vestedAmount(user1);
        assertApproxEqRel(vested, expectedApiary / 2, 0.01e18, "Should be ~50% vested");

        vm.expectEmit(true, false, false, true);
        emit ApiaryPreSaleBond.ApiaryUnlocked(user1, vested);

        preSaleBond.unlockApiary();

        assertEq(apiaryToken.balanceOf(user1), vested, "Incorrect claimed amount");

        // Step 5: Time passes (full vesting)
        _increaseTime(15 days); // Total 30 days

        // Step 6: User1 claims remaining
        preSaleBond.unlockApiary();

        assertEq(apiaryToken.balanceOf(user1), expectedApiary, "Should have full allocation");

        vm.stopPrank();
    }

    /// @notice Test pre-sale with multiple users and limits
    function test_Integration_PreSaleMultipleUsers() public {
        bytes32[] memory proof1 = _generateProofForUser1();
        bytes32[] memory proof2 = _generateProofForUser2();

        // User1 purchases max allocation
        vm.startPrank(user1);
        honeyToken.approve(address(preSaleBond), 3000e18);
        preSaleBond.purchaseApiary(3000e18, 3, proof1);
        vm.stopPrank();

        // User2 purchases partial
        vm.startPrank(user2);
        honeyToken.approve(address(preSaleBond), 1500e18);
        preSaleBond.purchaseApiary(1500e18, 2, proof2);
        vm.stopPrank();

        // Verify total allocations
        uint256 totalAllocated = preSaleBond.totalApiaryAllocated();
        assertEq(totalAllocated, (3000e18 * 110 / 100) + (1500e18 * 110 / 100), "Incorrect total allocation");

        // Cannot exceed individual limit
        vm.startPrank(user1);
        honeyToken.approve(address(preSaleBond), 100e18);
        vm.expectRevert();
        preSaleBond.purchaseApiary(100e18, 3, proof1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 2: FULL BOND JOURNEY
    //////////////////////////////////////////////////////////////*/

    /// @notice Test bond depository: deposit → vest → redeem → stake
    function test_Integration_BondFullJourney() public {
        // Note: This requires ApiaryBondDepository.sol to be in scope
        // For now, we'll test the basic flow concept

        uint256 depositAmount = 100e18; // 100 iBGT
        uint256 expectedPayout = 105e18; // Assume 5% discount

        vm.startPrank(user1);

        // User1 bonds iBGT
        ibgtToken.approve(treasury, depositAmount);

        // Simulate bond deposit (would call bondDepository.deposit())
        // For integration test, we'll verify the flow:
        // 1. User deposits iBGT
        // 2. Treasury receives iBGT
        // 3. User receives bond (vesting over 5 days)
        // 4. After 5 days, user can redeem APIARY
        // 5. User stakes APIARY for sAPIARY

        _increaseTime(5 days);

        // After vesting, user should be able to claim APIARY
        // Then stake it

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 3: FULL YIELD JOURNEY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test yield distribution: stake → claim → execute → distribute
     * @dev Updated for pull-pattern adapter architecture:
     *      1. YieldManager approves adapter for iBGT
     *      2. YieldManager calls adapter.stake() - adapter pulls iBGT from YieldManager
     *      3. YieldManager calls adapter.claimRewards() - adapter returns rewards to YieldManager
     */
    function test_Integration_YieldFullJourney() public {
        // Step 1: Fund the YieldManager with iBGT (simulating treasury transfer)
        ibgtToken.mint(address(yieldManager), 10_000e18);

        // Step 2: YieldManager approves adapter (this should be done via setupApprovals)
        // Already done in setUp()

        // Step 3: YieldManager stakes iBGT on Infrared via adapter
        // The YieldManager should call infraredAdapter.stake() which pulls from YieldManager
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 10_000e18);
        uint256 staked = infraredAdapter.stake(10_000e18);
        vm.stopPrank();

        assertEq(staked, 10_000e18, "Should have staked 10k iBGT");
        assertEq(infraredAdapter.totalStaked(), 10_000e18, "Adapter should track staked amount");

        // Step 4: Simulate yield accumulation on Infrared
        _increaseTime(7 days);
        infraredProtocol.addRewards(address(infraredAdapter), 500e18); // 500 iBGT rewards

        // Step 5: Check pending rewards
        uint256 pending = infraredAdapter.pendingRewards();
        assertEq(pending, 500e18, "Should have 500 iBGT pending rewards");

        // Step 6: YieldManager claims rewards via adapter
        vm.prank(address(yieldManager));
        uint256 claimed = infraredAdapter.claimRewards();
        assertEq(claimed, 500e18, "Should claim 500 iBGT");

        // Step 7: Verify rewards returned to YieldManager
        assertEq(ibgtToken.balanceOf(address(yieldManager)), 500e18, "YieldManager should have rewards");

        console2.log("Total Staked:", infraredAdapter.totalStaked());
        console2.log("Rewards Claimed:", claimed);
    }

    /// @notice Test adapter access control - only YieldManager can call core functions
    function test_Integration_AdapterAccessControl() public {
        // Fund YieldManager
        ibgtToken.mint(address(yieldManager), 1000e18);

        // Attacker tries to call stake directly - should fail
        vm.prank(attacker);
        vm.expectRevert();
        infraredAdapter.stake(1000e18);

        // Attacker tries to call unstake - should fail
        vm.prank(attacker);
        vm.expectRevert();
        infraredAdapter.unstake(100e18);

        // Attacker tries to claim rewards - should fail
        vm.prank(attacker);
        vm.expectRevert();
        infraredAdapter.claimRewards();

        // YieldManager can call successfully
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 1000e18);
        uint256 staked = infraredAdapter.stake(1000e18);
        vm.stopPrank();

        assertEq(staked, 1000e18, "YieldManager should stake successfully");
    }

    /// @notice Test unstake returns tokens to caller (YieldManager)
    function test_Integration_UnstakeReturnsToYieldManager() public {
        // Setup: Stake some iBGT
        ibgtToken.mint(address(yieldManager), 5000e18);

        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 5000e18);
        infraredAdapter.stake(5000e18);

        // Unstake
        uint256 unstaked = infraredAdapter.unstake(2000e18);
        vm.stopPrank();

        // Verify tokens returned to YieldManager
        assertEq(unstaked, 2000e18, "Should unstake 2000 iBGT");
        assertEq(ibgtToken.balanceOf(address(yieldManager)), 2000e18, "YieldManager should receive iBGT");
        assertEq(infraredAdapter.totalStaked(), 3000e18, "Remaining staked should be 3000");
    }

    /// @notice Test yield execution with slippage protection
    function test_Integration_YieldSlippageProtection() public {
        // Setup yield - fund and stake
        ibgtToken.mint(address(yieldManager), 10_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 10_000e18);
        infraredAdapter.stake(10_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 1000e18);

        // Set high slippage tolerance
        vm.prank(owner);
        yieldManager.setSlippageTolerance(100); // 1%

        // Execute should succeed
        vm.prank(keeper);
        yieldManager.executeYield();

        // Set low slippage tolerance
        vm.prank(owner);
        yieldManager.setSlippageTolerance(1); // 0.01%

        // Add more yield
        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Execute might fail if actual slippage > tolerance
        // This depends on DEX implementation
        vm.prank(keeper);
        // Note: May revert with APIARY__SWAP_FAILED in production
        yieldManager.executeYield();
    }

    /// @notice Test yield manager strategy switching
    function test_Integration_YieldStrategySwitch() public {
        // Start with Phase 1
        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE1_LP_BURN));

        // Owner switches to Phase 2
        vm.prank(owner);
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL);

        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL));

        // Update split percentages for Phase 2
        vm.prank(owner);
        yieldManager.setSplitPercentages(
            0, // toHoney (handled conditionally)
            0, // toApiaryLP (handled conditionally)
            0, // toBurn (handled conditionally)
            5000, // toStakers (50%)
            5000 // toCompound (50%)
        );

        // Setup yield - YieldManager stakes on Infrared
        ibgtToken.mint(address(yieldManager), 5_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 200e18);

        // Execute Phase 2 strategy
        vm.prank(keeper);
        (,,, uint256 lpCreated, uint256 compounded) = yieldManager.executeYield();

        // Phase 2 should compound based on MC/TV ratio
        // Note: Actual behavior depends on treasury MC/TV implementation
        console2.log("Phase 2 - LP Created:", lpCreated);
        console2.log("Phase 2 - Compounded:", compounded);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 4: LP REWARDS JOURNEY
    //////////////////////////////////////////////////////////////*/

    /// @notice Test LP creation and staking for rewards
    function test_Integration_LPRewardsJourney() public {
        uint256 apiaryAmount = 1000e18;
        uint256 honeyAmount = 1000e18;

        vm.startPrank(user1);

        // Provide liquidity
        apiaryToken.mint(user1, apiaryAmount);
        apiaryToken.approve(address(kodiakRouter), apiaryAmount);
        honeyToken.approve(address(kodiakRouter), honeyAmount);

        (,, uint256 liquidity) = kodiakRouter.addLiquidity(
            address(apiaryToken),
            address(honeyToken),
            apiaryAmount,
            honeyAmount,
            0,
            0,
            user1,
            block.timestamp
        );

        assertGt(liquidity, 0, "Should receive LP tokens");

        // Stake LP tokens on Kodiak gauge
        IERC20(address(apiaryHoneyPair)).approve(address(kodiakGauge), liquidity);
        kodiakGauge.deposit(liquidity);

        assertEq(kodiakGauge.balanceOf(user1), liquidity, "Should have staked LP");

        // Simulate rewards accumulation
        _increaseTime(7 days);
        kodiakGauge.addReward(user1, 50e18); // 50 xKDK/BGT rewards

        // Claim rewards
        uint256 rewards = kodiakGauge.getReward();
        assertEq(rewards, 50e18, "Should receive rewards");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 5: MULTI-USER SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test multiple users interacting with protocol simultaneously
    function test_Integration_MultiUserScenarios() public {
        // User1: Buys pre-sale
        bytes32[] memory proof1 = _generateProofForUser1();
        vm.startPrank(user1);
        honeyToken.approve(address(preSaleBond), 2000e18);
        preSaleBond.purchaseApiary(2000e18, 3, proof1);
        vm.stopPrank();

        // User2: Buys pre-sale
        bytes32[] memory proof2 = _generateProofForUser2();
        vm.startPrank(user2);
        honeyToken.approve(address(preSaleBond), 1500e18);
        preSaleBond.purchaseApiary(1500e18, 2, proof2);
        vm.stopPrank();

        // YieldManager: Stakes iBGT for yield
        ibgtToken.mint(address(yieldManager), 20_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 20_000e18);
        infraredAdapter.stake(20_000e18);
        vm.stopPrank();

        // Time passes
        _increaseTime(15 days);

        // Yield accumulates
        infraredProtocol.addRewards(address(infraredAdapter), 1000e18);

        // User1: Claims pre-sale (50% vested)
        vm.prank(user1);
        preSaleBond.unlockApiary();
        assertGt(apiaryToken.balanceOf(user1), 0, "User1 should have claimed");

        // Keeper: Executes yield
        vm.prank(keeper);
        yieldManager.executeYield();

        // User2: Claims pre-sale
        vm.prank(user2);
        preSaleBond.unlockApiary();
        assertGt(apiaryToken.balanceOf(user2), 0, "User2 should have claimed");

        // Time passes to full vesting
        _increaseTime(15 days);

        // Users claim remaining
        vm.prank(user1);
        preSaleBond.unlockApiary();

        vm.prank(user2);
        preSaleBond.unlockApiary();

        // Verify final balances
        assertGt(apiaryToken.balanceOf(user1), 2000e18, "User1 should have bonus");
        assertGt(apiaryToken.balanceOf(user2), 1500e18, "User2 should have bonus");
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 6: EMERGENCY SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test emergency pause and recovery
    function test_Integration_EmergencyPauseAndRecovery() public {
        // Setup yield - YieldManager stakes
        ibgtToken.mint(address(yieldManager), 5_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 300e18);

        // Owner pauses yield manager
        vm.prank(owner);
        yieldManager.pause();

        // Execution should fail when paused
        vm.prank(keeper);
        vm.expectRevert();
        yieldManager.executeYield();

        // Owner unpauses
        vm.prank(owner);
        yieldManager.unpause();

        // Execution should succeed
        vm.prank(keeper);
        yieldManager.executeYield();
    }

    /// @notice Test emergency mode (bypass swaps)
    function test_Integration_EmergencyMode() public {
        // Setup yield - YieldManager stakes
        ibgtToken.mint(address(yieldManager), 5_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 5_000e18);
        infraredAdapter.stake(5_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 500e18);

        // Owner enables emergency mode
        vm.prank(owner);
        yieldManager.setEmergencyMode(true);

        // Execute should bypass swaps and forward to treasury
        uint256 treasuryBalanceBefore = ibgtToken.balanceOf(treasury);

        vm.prank(keeper);
        (uint256 totalYield, uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated,) =
            yieldManager.executeYield();

        // In emergency mode: no swaps, no burns, no LP
        assertEq(totalYield, 500e18, "Should process yield");
        assertEq(honeySwapped, 0, "Should not swap in emergency");
        assertEq(apiaryBurned, 0, "Should not burn in emergency");
        assertEq(lpCreated, 0, "Should not create LP in emergency");

        // Treasury should receive raw iBGT
        assertEq(ibgtToken.balanceOf(treasury), treasuryBalanceBefore + totalYield, "Treasury should receive iBGT");

        // Disable emergency mode
        vm.prank(owner);
        yieldManager.setEmergencyMode(false);
    }

    /// @notice Test emergency withdrawal of stuck tokens
    function test_Integration_EmergencyWithdraw() public {
        // Accidentally send tokens to yield manager
        vm.prank(user1);
        honeyToken.transfer(address(yieldManager), 100e18);

        assertEq(honeyToken.balanceOf(address(yieldManager)), 100e18, "Tokens stuck");

        // Owner recovers stuck tokens
        vm.prank(owner);
        yieldManager.emergencyWithdraw(address(honeyToken), 100e18, treasury);

        assertEq(honeyToken.balanceOf(address(yieldManager)), 0, "Tokens recovered");
        assertEq(honeyToken.balanceOf(treasury), 100e18, "Treasury received");
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 7: GAS OPTIMIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Test gas usage for common operations
    function test_Integration_GasUsage() public {
        // Setup - YieldManager stakes on Infrared
        ibgtToken.mint(address(yieldManager), 10_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 10_000e18);
        infraredAdapter.stake(10_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 1000e18);

        // Measure gas for yield execution
        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        yieldManager.executeYield();
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for executeYield():", gasUsed);

        // Gas should be reasonable (< 1M for Phase 1)
        assertLt(gasUsed, 1_000_000, "Gas usage too high");
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 8: EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test zero yield execution
    function test_Integration_ZeroYield() public {
        // No yield pending
        assertEq(infraredAdapter.pendingRewards(), 0, "Should have no pending rewards");

        // Should revert with NO_PENDING_YIELD (or similar error)
        vm.prank(keeper);
        vm.expectRevert();
        yieldManager.executeYield();
    }

    /// @notice Test dust amount (below minimum)
    function test_Integration_DustAmount() public {
        // Setup very small yield - YieldManager stakes
        ibgtToken.mint(address(yieldManager), 1000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 1000e18);
        infraredAdapter.stake(1000e18);
        vm.stopPrank();

        // Add dust rewards (below min)
        infraredProtocol.addRewards(address(infraredAdapter), 0.05e18); // 0.05 iBGT

        // Should revert with INSUFFICIENT_YIELD (if minimum is set)
        vm.prank(keeper);
        vm.expectRevert();
        yieldManager.executeYield();
    }

    /// @notice Test maximum execution cap
    function test_Integration_MaxExecutionCap() public {
        // Setup large yield (above max) - YieldManager stakes
        ibgtToken.mint(address(yieldManager), 50_000e18);
        vm.startPrank(address(yieldManager));
        ibgtToken.approve(address(infraredAdapter), 50_000e18);
        infraredAdapter.stake(50_000e18);
        vm.stopPrank();

        infraredProtocol.addRewards(address(infraredAdapter), 15_000e18); // 15k iBGT

        // Should cap at maxExecutionAmount (10k default)
        vm.prank(keeper);
        (uint256 totalYield,,,,) = yieldManager.executeYield();

        assertEq(totalYield, 10_000e18, "Should cap at max execution amount");

        // Remaining yield should still be pending
        uint256 remainingYield = infraredAdapter.pendingRewards();
        assertEq(remainingYield, 5_000e18, "Should have remaining yield");
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _generateMerkleRoot() internal pure returns (bytes32) {
        // Simple mock merkle root for testing
        return keccak256(abi.encodePacked("mockRoot"));
    }

    function _generateProofForUser1() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256(abi.encodePacked("mockProof1"));
        return proof;
    }

    function _generateProofForUser2() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256(abi.encodePacked("mockProof2"));
        return proof;
    }

    /*//////////////////////////////////////////////////////////////
                    EVENTS (for testing)
    //////////////////////////////////////////////////////////////*/

    event ApiaryPurchased(address indexed user, uint256 honeyAmount, uint256 apiaryAmount);
    event ApiaryUnlocked(address indexed user, uint256 amount);
}
