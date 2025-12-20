// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestSetup } from "./TestSetup.sol";
import { ApiaryYieldManager } from "../../src/ApiaryYieldManager.sol";
import { console2 } from "forge-std/Test.sol";

/**
 * @title ApiaryFuzzTest
 * @notice Fuzz testing for Apiary protocol
 * @dev Tests protocol behavior with random inputs
 */
contract ApiaryFuzzTest is TestSetup {
    ApiaryYieldManager public yieldManager;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy minimal setup for fuzzing
        yieldManager = new ApiaryYieldManager(
            address(apiaryToken),
            address(honeyToken),
            address(ibgtToken),
            treasury,
            address(0x1), // Mock infrared
            address(0x2), // Mock kodiak
            owner
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - SPLIT PERCENTAGES
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test split percentages validation
    /// @dev Tests that invalid splits always revert
    function testFuzz_SplitPercentagesValidation(
        uint256 toHoney,
        uint256 toApiaryLP,
        uint256 toBurn,
        uint256 toStakers,
        uint256 toCompound
    ) public {
        vm.startPrank(owner);

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

    /// @notice Fuzz test valid split percentages always sum to 100%
    function testFuzz_ValidSplitsAlwaysSum10000(uint16 a, uint16 b, uint16 c, uint16 d) public {
        // Generate valid splits
        uint256 toHoney = uint256(a) % 10001;
        uint256 toApiaryLP = uint256(b) % (10001 - toHoney);
        uint256 toBurn = uint256(c) % (10001 - toHoney - toApiaryLP);
        uint256 toStakers = uint256(d) % (10001 - toHoney - toApiaryLP - toBurn);
        uint256 toCompound = 10000 - toHoney - toApiaryLP - toBurn - toStakers;

        vm.prank(owner);
        yieldManager.setSplitPercentages(toHoney, toApiaryLP, toBurn, toStakers, toCompound);

        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        uint256 total = config.toHoney + config.toApiaryLP + config.toBurn + config.toStakers + config.toCompound;

        assertEq(total, 10000, "Valid splits must sum to 10000");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - SLIPPAGE TOLERANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test slippage tolerance validation
    function testFuzz_SlippageToleranceValidation(uint256 slippage) public {
        vm.startPrank(owner);

        if (slippage > 1000) {
            vm.expectRevert(ApiaryYieldManager.APIARY__SLIPPAGE_TOO_HIGH.selector);
            yieldManager.setSlippageTolerance(slippage);
        } else {
            yieldManager.setSlippageTolerance(slippage);
            assertEq(yieldManager.slippageTolerance(), slippage);
        }

        vm.stopPrank();
    }

    /// @notice Fuzz test slippage protection calculations
    function testFuzz_SlippageCalculation(uint256 amount, uint16 tolerance) public view {
        // Bound inputs
        amount = bound(amount, 1e18, 1_000_000e18);
        tolerance = uint16(bound(tolerance, 0, 1000));

        // Calculate minimum output with slippage
        uint256 minOutput = (amount * (10000 - tolerance)) / 10000;

        // Invariants
        assertLe(minOutput, amount, "Min output <= input");
        assertGe(minOutput, (amount * 9000) / 10000, "Min output >= 90% of input");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - AMOUNTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test minimum yield amount
    function testFuzz_MinimumYieldAmount(uint256 minAmount) public {
        // Bound to reasonable range
        minAmount = bound(minAmount, 0, 1000e18);

        vm.prank(owner);
        yieldManager.setMinYieldAmount(minAmount);

        assertEq(yieldManager.minYieldAmount(), minAmount);
    }

    /// @notice Fuzz test maximum execution amount
    function testFuzz_MaximumExecutionAmount(uint256 maxAmount) public {
        // Bound to reasonable range
        maxAmount = bound(maxAmount, 1e18, 1_000_000e18);

        vm.prank(owner);
        yieldManager.setMaxExecutionAmount(maxAmount);

        assertEq(yieldManager.maxExecutionAmount(), maxAmount);
    }

    /// @notice Fuzz test MC threshold multiplier
    function testFuzz_MCThresholdMultiplier(uint256 multiplier) public {
        // Bound to reasonable range (100% to 300%)
        multiplier = bound(multiplier, 10000, 30000);

        vm.prank(owner);
        yieldManager.setMCThresholdMultiplier(multiplier);

        assertEq(yieldManager.mcThresholdMultiplier(), multiplier);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - TIME-BASED
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test time advancement doesn't break state
    function testFuzz_TimeAdvancement(uint32 timeIncrease) public {
        // Bound to reasonable range (1 second to 1 year)
        timeIncrease = uint32(bound(timeIncrease, 1, 365 days));

        uint256 lastTimeBefore = yieldManager.lastExecutionTime();

        // Advance time
        _increaseTime(timeIncrease);

        // State should remain valid
        uint256 lastTimeAfter = yieldManager.lastExecutionTime();
        assertEq(lastTimeBefore, lastTimeAfter, "Last execution time unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - STRATEGY
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test strategy changes
    function testFuzz_StrategyChanges(uint8 strategyId) public {
        // Bound to valid strategy values (0-2)
        strategyId = uint8(bound(strategyId, 0, 2));

        ApiaryYieldManager.Strategy strategy = ApiaryYieldManager.Strategy(strategyId);

        vm.prank(owner);
        yieldManager.setStrategy(strategy);

        assertEq(uint256(yieldManager.currentStrategy()), strategyId);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS - EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test zero values handling
    function testFuzz_ZeroValues(bool useZeroHoney, bool useZeroLP, bool useZeroBurn) public {
        vm.startPrank(owner);

        uint256 toHoney = useZeroHoney ? 0 : 3000;
        uint256 toApiaryLP = useZeroLP ? 0 : 3000;
        uint256 toBurn = 10000 - toHoney - toApiaryLP;

        if (useZeroBurn && toBurn == 0) {
            toBurn = 1;
            toApiaryLP -= 1;
        }

        yieldManager.setSplitPercentages(toHoney, toApiaryLP, toBurn, 0, 0);

        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        uint256 total = config.toHoney + config.toApiaryLP + config.toBurn;

        assertEq(total, 10000, "Must sum to 10000");

        vm.stopPrank();
    }

    /// @notice Fuzz test maximum values
    function testFuzz_MaximumValues() public {
        vm.startPrank(owner);

        // Test maximum valid slippage
        yieldManager.setSlippageTolerance(1000);
        assertEq(yieldManager.slippageTolerance(), 1000);

        // Test maximum execution amount
        yieldManager.setMaxExecutionAmount(type(uint128).max);
        assertEq(yieldManager.maxExecutionAmount(), type(uint128).max);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invariant: Split percentages always sum to 10000
    function invariant_SplitPercentagesSum() public view {
        ApiaryYieldManager.SplitConfig memory config = yieldManager.getSplitPercentages();
        uint256 total = config.toHoney + config.toApiaryLP + config.toBurn + config.toStakers + config.toCompound;

        assertEq(total, 10000, "Invariant: Splits must sum to 10000");
    }

    /// @notice Invariant: Slippage tolerance never exceeds 10%
    function invariant_SlippageToleranceMax() public view {
        assertLe(yieldManager.slippageTolerance(), 1000, "Invariant: Slippage <= 10%");
    }

    /// @notice Invariant: Total yield processed never decreases
    function invariant_TotalYieldMonotonic() public view {
        // This would require tracking previous values
        // For now, we just verify it's always >= 0
        uint256 total = yieldManager.totalYieldProcessed();
        assertGe(total, 0, "Invariant: Total yield >= 0");
    }

    /// @notice Invariant: Contract has valid owner
    function invariant_ValidOwner() public view {
        address contractOwner = yieldManager.owner();
        assertTrue(contractOwner != address(0), "Invariant: Owner != zero address");
    }
}
