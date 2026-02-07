// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { ApiaryBondingCalculator } from "../src/ApiaryBondingCalculator.sol";
import { IUniswapV2Pair } from "../src/interfaces/IUniswapV2Pair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Mock ERC20 with configurable decimals
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/**
 * @title Mock Uniswap V2 Pair
 */
contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function setReserves(uint112 reserve0_, uint112 reserve1_) external {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function setTotalSupply(uint256 supply) external {
        totalSupply = supply;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract ApiaryBondingCalculatorTest is Test {
    ApiaryBondingCalculator public calculator;
    MockERC20 public apiary;
    MockERC20 public honey;
    MockUniswapV2Pair public pair;

    function setUp() public {
        // APIARY has 9 decimals
        apiary = new MockERC20("APIARY", "APIARY", 9);
        // HONEY has 18 decimals
        honey = new MockERC20("HONEY", "HONEY", 18);

        // Deploy pair (order matters: token0 < token1 by address)
        if (address(apiary) < address(honey)) {
            pair = new MockUniswapV2Pair(address(apiary), address(honey));
        } else {
            pair = new MockUniswapV2Pair(address(honey), address(apiary));
        }

        // Deploy calculator
        calculator = new ApiaryBondingCalculator(address(apiary));
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public view {
        assertEq(calculator.APIARY(), address(apiary));
    }

    function testConstructorRevertsZeroAddress() public {
        vm.expectRevert(ApiaryBondingCalculator.APIARY__ZERO_ADDRESS.selector);
        new ApiaryBondingCalculator(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        VALUATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testBasicValuation() public {
        // Set up pair with balanced reserves
        // APIARY (9 decimals): 1_000_000 * 1e9 = 1e15
        // HONEY (18 decimals): 1_000_000 * 1e18 = 1e24
        // Total LP supply: 1_000_000e18
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1_000_000e9), uint112(1_000_000e18));
        } else {
            pair.setReserves(uint112(1_000_000e18), uint112(1_000_000e9));
        }
        pair.setTotalSupply(1_000_000e18);

        // Value 1 LP token (1e18)
        uint256 value = calculator.valuation(address(pair), 1e18);

        // Fair value = 2 * sqrt(1e15 * 1e24) * 1e18 / 1_000_000e18
        // = 2 * sqrt(1e39) * 1e18 / 1e24
        // = 2 * ~31.623e18 * 1e18 / 1e24
        // = 2 * 31.623e12 (approx)
        // Then scaled to 9 decimals
        // Value should be > 0
        assertGt(value, 0, "Value should be positive");
    }

    function testValuationProportionalToAmount() public {
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1_000_000e9), uint112(1_000_000e18));
        } else {
            pair.setReserves(uint112(1_000_000e18), uint112(1_000_000e9));
        }
        pair.setTotalSupply(1_000_000e18);

        uint256 value1 = calculator.valuation(address(pair), 1e18);
        uint256 value10 = calculator.valuation(address(pair), 10e18);

        // 10x amount should give ~10x value (allow 1 wei rounding per multiplication)
        assertApproxEqAbs(value10, value1 * 10, 10, "Value should scale linearly with amount");
    }

    function testValuationZeroAmount() public {
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1_000_000e9), uint112(1_000_000e18));
        } else {
            pair.setReserves(uint112(1_000_000e18), uint112(1_000_000e9));
        }
        pair.setTotalSupply(1_000_000e18);

        uint256 value = calculator.valuation(address(pair), 0);
        assertEq(value, 0, "Zero amount should give zero value");
    }

    function testValuationRevertsZeroAddress() public {
        vm.expectRevert(ApiaryBondingCalculator.APIARY__ZERO_ADDRESS.selector);
        calculator.valuation(address(0), 1e18);
    }

    function testValuationRevertsZeroSupply() public {
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1_000_000e9), uint112(1_000_000e18));
        } else {
            pair.setReserves(uint112(1_000_000e18), uint112(1_000_000e9));
        }
        // totalSupply = 0

        vm.expectRevert(ApiaryBondingCalculator.APIARY__ZERO_SUPPLY.selector);
        calculator.valuation(address(pair), 1e18);
    }

    function testValuationWithEqualDecimals() public {
        // Both tokens 18 decimals
        MockERC20 token0 = new MockERC20("Token0", "T0", 18);
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);

        MockUniswapV2Pair equalPair;
        if (address(token0) < address(token1)) {
            equalPair = new MockUniswapV2Pair(address(token0), address(token1));
        } else {
            equalPair = new MockUniswapV2Pair(address(token1), address(token0));
        }

        // Set reserves: 100_000 tokens each
        equalPair.setReserves(uint112(100_000e18), uint112(100_000e18));
        equalPair.setTotalSupply(100_000e18);

        uint256 value = calculator.valuation(address(equalPair), 1e18);
        // sqrt(100_000e18 * 100_000e18) = 100_000e18
        // 2 * 100_000e18 * 1e18 / 100_000e18 = 2e18
        // Scale from 18 decimals to 9 decimals: 2e18 / 1e9 = 2e9
        assertEq(value, 2e9, "1 LP = 2 tokens worth (in 9-decimal APIARY terms)");
    }

    function testValuationSmallReserves() public {
        // Small reserves
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(100e9), uint112(100e18));
        } else {
            pair.setReserves(uint112(100e18), uint112(100e9));
        }
        pair.setTotalSupply(100e18);

        uint256 value = calculator.valuation(address(pair), 1e18);
        assertGt(value, 0, "Small reserves should still produce value");
    }

    function testValuationLargeReserves() public {
        // Large reserves (close to uint112 max)
        // uint112 max ≈ 5.19e33
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1e30), uint112(1e30));
        } else {
            pair.setReserves(uint112(1e30), uint112(1e30));
        }
        pair.setTotalSupply(1e30);

        // Compute valuation for a large amount too
        uint256 value = calculator.valuation(address(pair), 1e18);
        assertGt(value, 0, "Large reserves should produce value");
    }

    function testValuationImbalancedReserves() public {
        // Imbalanced reserves: 10:1 ratio
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(10_000e9), uint112(1_000e18));
        } else {
            pair.setReserves(uint112(1_000e18), uint112(10_000e9));
        }
        pair.setTotalSupply(3_162e18); // sqrt(10_000 * 1_000) ≈ 3162

        uint256 value = calculator.valuation(address(pair), 1e18);
        assertGt(value, 0, "Imbalanced reserves should produce value");
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzValuationNonNegative(uint112 reserve0, uint112 reserve1, uint256 amount, uint256 supply) public {
        reserve0 = uint112(bound(reserve0, 1e6, type(uint112).max / 2));
        reserve1 = uint112(bound(reserve1, 1e6, type(uint112).max / 2));
        supply = bound(supply, 1e6, type(uint128).max);
        amount = bound(amount, 0, supply);

        MockERC20 t0 = new MockERC20("T0", "T0", 18);
        MockERC20 t1 = new MockERC20("T1", "T1", 18);
        MockUniswapV2Pair fuzzPair;
        if (address(t0) < address(t1)) {
            fuzzPair = new MockUniswapV2Pair(address(t0), address(t1));
        } else {
            fuzzPair = new MockUniswapV2Pair(address(t1), address(t0));
        }

        fuzzPair.setReserves(reserve0, reserve1);
        fuzzPair.setTotalSupply(supply);

        uint256 value = calculator.valuation(address(fuzzPair), amount);
        // Value should never be negative (uint, so this just ensures no revert)
        assertTrue(value >= 0);
    }

    function testFuzzValuationMonotonic(uint256 amount1, uint256 amount2) public {
        if (pair.token0() == address(apiary)) {
            pair.setReserves(uint112(1_000_000e9), uint112(1_000_000e18));
        } else {
            pair.setReserves(uint112(1_000_000e18), uint112(1_000_000e9));
        }
        pair.setTotalSupply(1_000_000e18);

        amount1 = bound(amount1, 0, 500_000e18);
        amount2 = bound(amount2, amount1, 1_000_000e18);

        uint256 value1 = calculator.valuation(address(pair), amount1);
        uint256 value2 = calculator.valuation(address(pair), amount2);

        assertTrue(value2 >= value1, "Larger amount should have >= value");
    }
}
