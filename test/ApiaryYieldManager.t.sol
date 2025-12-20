// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryYieldManager } from "../src/ApiaryYieldManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApiaryYieldManagerTest
 * @notice Comprehensive test suite for yield manager
 * @dev Tests all strategies, edge cases, and security scenarios
 */
contract ApiaryYieldManagerTest is Test {
    ApiaryYieldManager public yieldManager;

    // Mock addresses (replace with actual deployments)
    address public constant APIARY_TOKEN = address(0x1);
    address public constant HONEY_TOKEN = address(0x2);
    address public constant IBGT_TOKEN = address(0x3);
    address public constant TREASURY = address(0x4);
    address public constant INFRARED_ADAPTER = address(0x5);
    address public constant KODIAK_ADAPTER = address(0x6);
    address public constant OWNER = address(0x7);

    // Test accounts
    address public keeper = makeAddr("keeper");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy yield manager
        yieldManager = new ApiaryYieldManager(
            APIARY_TOKEN,
            HONEY_TOKEN,
            IBGT_TOKEN,
            TREASURY,
            INFRARED_ADAPTER,
            KODIAK_ADAPTER,
            OWNER
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        // Verify immutables
        assertEq(address(yieldManager.apiaryToken()), APIARY_TOKEN);
        assertEq(address(yieldManager.honeyToken()), HONEY_TOKEN);
        assertEq(address(yieldManager.ibgtToken()), IBGT_TOKEN);

        // Verify state variables
        assertEq(yieldManager.treasury(), TREASURY);
        assertEq(yieldManager.infraredAdapter(), INFRARED_ADAPTER);
        assertEq(yieldManager.kodiakAdapter(), KODIAK_ADAPTER);
        assertEq(yieldManager.owner(), OWNER);

        // Verify default strategy
        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE1_LP_BURN));

        // Verify default split config
        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        assertEq(config.toHoney, 2500);
        assertEq(config.toApiaryLP, 5000);
        assertEq(config.toBurn, 2500);
        assertEq(config.toStakers, 0);
        assertEq(config.toCompound, 0);

        // Verify default parameters
        assertEq(yieldManager.slippageTolerance(), 50);
        assertEq(yieldManager.minYieldAmount(), 0.1e18);
        assertEq(yieldManager.maxExecutionAmount(), 10000e18);
    }

    function testRevert_DeploymentZeroAddress() public {
        vm.expectRevert(ApiaryYieldManager.APIARY__ZERO_ADDRESS.selector);
        new ApiaryYieldManager(
            address(0), // Zero address
            HONEY_TOKEN,
            IBGT_TOKEN,
            TREASURY,
            INFRARED_ADAPTER,
            KODIAK_ADAPTER,
            OWNER
        );
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetStrategy() public {
        vm.startPrank(OWNER);

        // Change to Phase 2
        vm.expectEmit(true, true, false, false);
        emit ApiaryYieldManager.StrategyChanged(
            ApiaryYieldManager.Strategy.PHASE1_LP_BURN, ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL
        );

        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL);

        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL));

        vm.stopPrank();
    }

    function testRevert_SetStrategyNotOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SPLIT CONFIG TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSplitPercentages() public {
        vm.startPrank(OWNER);

        // Valid config: 30/30/40/0/0 = 100%
        vm.expectEmit(false, false, false, true);
        emit ApiaryYieldManager.SplitConfigUpdated(3000, 3000, 4000, 0, 0);

        yieldManager.setSplitPercentages(3000, 3000, 4000, 0, 0);

        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        assertEq(config.toHoney, 3000);
        assertEq(config.toApiaryLP, 3000);
        assertEq(config.toBurn, 4000);

        vm.stopPrank();
    }

    function testRevert_SetSplitPercentages_InvalidTotal() public {
        vm.startPrank(OWNER);

        // Invalid: 30/30/30 = 90% (not 100%)
        vm.expectRevert(ApiaryYieldManager.APIARY__INVALID_SPLIT_CONFIG.selector);
        yieldManager.setSplitPercentages(3000, 3000, 3000, 0, 0);

        vm.stopPrank();
    }

    function testRevert_SetSplitPercentages_NotOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        yieldManager.setSplitPercentages(3000, 3000, 4000, 0, 0);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSlippageTolerance() public {
        vm.startPrank(OWNER);

        vm.expectEmit(false, false, false, true);
        emit ApiaryYieldManager.SlippageToleranceUpdated(50, 100);

        yieldManager.setSlippageTolerance(100);

        assertEq(yieldManager.slippageTolerance(), 100);

        vm.stopPrank();
    }

    function testRevert_SetSlippageTolerance_TooHigh() public {
        vm.startPrank(OWNER);

        // Max is 10% (1000 BPS)
        vm.expectRevert(ApiaryYieldManager.APIARY__SLIPPAGE_TOO_HIGH.selector);
        yieldManager.setSlippageTolerance(1001);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ADAPTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetInfraredAdapter() public {
        address newAdapter = makeAddr("newInfrared");

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, false);
        emit ApiaryYieldManager.AdapterUpdated("infrared", INFRARED_ADAPTER, newAdapter);

        yieldManager.setInfraredAdapter(newAdapter);

        assertEq(yieldManager.infraredAdapter(), newAdapter);

        vm.stopPrank();
    }

    function testRevert_SetInfraredAdapter_ZeroAddress() public {
        vm.startPrank(OWNER);

        vm.expectRevert(ApiaryYieldManager.APIARY__ZERO_ADDRESS.selector);
        yieldManager.setInfraredAdapter(address(0));

        vm.stopPrank();
    }

    function test_SetKodiakAdapter() public {
        address newAdapter = makeAddr("newKodiak");

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, false);
        emit ApiaryYieldManager.AdapterUpdated("kodiak", KODIAK_ADAPTER, newAdapter);

        yieldManager.setKodiakAdapter(newAdapter);

        assertEq(yieldManager.kodiakAdapter(), newAdapter);

        vm.stopPrank();
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, false, false);
        emit ApiaryYieldManager.TreasuryUpdated(TREASURY, newTreasury);

        yieldManager.setTreasury(newTreasury);

        assertEq(yieldManager.treasury(), newTreasury);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        PARAMETER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMinYieldAmount() public {
        vm.startPrank(OWNER);

        yieldManager.setMinYieldAmount(1e18);

        assertEq(yieldManager.minYieldAmount(), 1e18);

        vm.stopPrank();
    }

    function test_SetMaxExecutionAmount() public {
        vm.startPrank(OWNER);

        yieldManager.setMaxExecutionAmount(5000e18);

        assertEq(yieldManager.maxExecutionAmount(), 5000e18);

        vm.stopPrank();
    }

    function test_SetMCThresholdMultiplier() public {
        vm.startPrank(OWNER);

        yieldManager.setMCThresholdMultiplier(15000); // 150%

        assertEq(yieldManager.mcThresholdMultiplier(), 15000);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetEmergencyMode() public {
        vm.startPrank(OWNER);

        assertEq(yieldManager.emergencyMode(), false);

        vm.expectEmit(false, false, false, true);
        emit ApiaryYieldManager.EmergencyModeToggled(true);

        yieldManager.setEmergencyMode(true);

        assertEq(yieldManager.emergencyMode(), true);

        vm.stopPrank();
    }

    function test_Pause() public {
        vm.startPrank(OWNER);

        yieldManager.pause();

        assertEq(yieldManager.paused(), true);

        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(OWNER);

        yieldManager.pause();
        yieldManager.unpause();

        assertEq(yieldManager.paused(), false);

        vm.stopPrank();
    }

    function testRevert_PauseNotOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        yieldManager.pause();

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetSplitPercentages() public view {
        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();

        assertEq(config.toHoney, 2500);
        assertEq(config.toApiaryLP, 5000);
        assertEq(config.toBurn, 2500);
        assertEq(config.toStakers, 0);
        assertEq(config.toCompound, 0);
    }

    function test_GetStatistics() public {
        (
            uint256 totalYieldProcessed,
            uint256 totalApiaryBurned,
            uint256 totalLPCreated,
            uint256 lastExecutionTime,
            uint256 lastExecutionBlock
        ) = yieldManager.getStatistics();

        // Initially all should be 0
        assertEq(totalYieldProcessed, 0);
        assertEq(totalApiaryBurned, 0);
        assertEq(totalLPCreated, 0);
        assertEq(lastExecutionTime, 0);
        assertEq(lastExecutionBlock, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(OWNER);

        // Step 1: Transfer ownership
        yieldManager.transferOwnership(newOwner);

        // Owner hasn't changed yet
        assertEq(yieldManager.owner(), OWNER);

        vm.stopPrank();

        // Step 2: New owner accepts
        vm.startPrank(newOwner);

        yieldManager.acceptOwnership();

        assertEq(yieldManager.owner(), newOwner);

        vm.stopPrank();
    }

    function testRevert_TransferOwnership_NotOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        yieldManager.transferOwnership(attacker);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    // Note: Full integration tests require mock adapters
    // See separate integration test file for end-to-end scenarios

    function test_PendingYieldCallsAdapter() public view {
        // This will call infraredAdapter.pendingRewards()
        // In production, mock adapter should return value
        uint256 pending = yieldManager.pendingYield();

        // With mock adapter returning 0
        assertEq(pending, 0);
    }

    function test_CanExecuteYield() public view {
        (bool canExecute, uint256 pending, ) = yieldManager.canExecuteYield();

        // Initially false (no pending yield)
        assertEq(canExecute, false);
        assertEq(pending, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetStakingContract() public {
        address staking = makeAddr("staking");

        vm.startPrank(OWNER);

        yieldManager.setStakingContract(staking);

        assertEq(yieldManager.stakingContract(), staking);

        vm.stopPrank();
    }

    function test_MultipleStrategyChanges() public {
        vm.startPrank(OWNER);

        // Phase 1 → Phase 2
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL);
        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE2_CONDITIONAL));

        // Phase 2 → Phase 3
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE3_VBGT);
        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE3_VBGT));

        // Phase 3 → Phase 1
        yieldManager.setStrategy(ApiaryYieldManager.Strategy.PHASE1_LP_BURN);
        assertEq(uint256(yieldManager.currentStrategy()), uint256(ApiaryYieldManager.Strategy.PHASE1_LP_BURN));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetSlippageTolerance(uint256 slippage) public {
        vm.startPrank(OWNER);

        if (slippage > 1000) {
            vm.expectRevert(ApiaryYieldManager.APIARY__SLIPPAGE_TOO_HIGH.selector);
            yieldManager.setSlippageTolerance(slippage);
        } else {
            yieldManager.setSlippageTolerance(slippage);
            assertEq(yieldManager.slippageTolerance(), slippage);
        }

        vm.stopPrank();
    }

    function testFuzz_SetSplitPercentages(
        uint256 toHoney,
        uint256 toApiaryLP,
        uint256 toBurn,
        uint256 toStakers,
        uint256 toCompound
    ) public {
        vm.startPrank(OWNER);

        uint256 total = toHoney + toApiaryLP + toBurn + toStakers + toCompound;

        if (total != 10000) {
            vm.expectRevert(ApiaryYieldManager.APIARY__INVALID_SPLIT_CONFIG.selector);
            yieldManager.setSplitPercentages(toHoney, toApiaryLP, toBurn, toStakers, toCompound);
        } else {
            yieldManager.setSplitPercentages(toHoney, toApiaryLP, toBurn, toStakers, toCompound);

            ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
            assertEq(config.toHoney, toHoney);
            assertEq(config.toApiaryLP, toApiaryLP);
            assertEq(config.toBurn, toBurn);
            assertEq(config.toStakers, toStakers);
            assertEq(config.toCompound, toCompound);
        }

        vm.stopPrank();
    }
}
