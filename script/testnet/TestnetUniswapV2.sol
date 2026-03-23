// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title TestnetUniswapV2
 * @notice Minimal UniswapV2 Factory + Pair + Router for Bepolia testnet deployment.
 * @dev Implements the exact interface our KodiakAdapter and TWAP Oracle expect:
 *      - Factory: getPair(), createPair(), allPairsLength()
 *      - Router:  swapExactTokensForTokens(), addLiquidity(), removeLiquidity(), getAmountsOut()
 *      - Pair:    getReserves(), token0(), token1(), price0CumulativeLast(), price1CumulativeLast()
 *
 *      DO NOT USE IN PRODUCTION. This is for testnet only.
 */

// ============================================================================
// PAIR
// ============================================================================

contract TestnetUniswapV2Pair is ERC20 {
    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32  private _blockTimestampLast;

    address public token0;
    address public token1;
    address public factory;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint256 private constant MINIMUM_LIQUIDITY = 1000;

    uint256 private _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1, "LOCKED");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor() ERC20("Testnet UniV2 LP", "UNI-V2") {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function _update(uint256 balance0, uint256 balance1, uint112 prevReserve0, uint112 prevReserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - _blockTimestampLast;
        }

        if (timeElapsed > 0 && prevReserve0 != 0 && prevReserve1 != 0) {
            unchecked {
                price0CumulativeLast += uint256(uint224((uint256(prevReserve1) << 112) / prevReserve0)) * timeElapsed;
                price1CumulativeLast += uint256(uint224((uint256(prevReserve0) << 112) / prevReserve1)) * timeElapsed;
            }
        }

        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = blockTimestamp;
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 r0, uint112 r1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - r0;
        uint256 amount1 = balance1 - r1;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // lock minimum
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / r0,
                (amount1 * _totalSupply) / r1
            );
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1, r0, r1);
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liquidity);
        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1, uint112(balance0 + amount0), uint112(balance1 + amount1));
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external lock {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(amount0Out < r0 && amount1Out < r1, "INSUFFICIENT_LIQUIDITY");

        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Verify k invariant (with 0.3% fee)
        uint256 balance0Adjusted = balance0 * 1000 - (balance0 - (r0 - amount0Out)) * 3;
        uint256 balance1Adjusted = balance1 * 1000 - (balance1 - (r1 - amount1Out)) * 3;
        require(balance0Adjusted * balance1Adjusted >= uint256(r0) * uint256(r1) * 1000000, "K");

        _update(balance0, balance1, r0, r1);
    }

    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            _reserve0,
            _reserve1
        );
    }
}

// ============================================================================
// FACTORY
// ============================================================================

contract TestnetUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(t0 != address(0), "ZERO_ADDRESS");
        require(getPair[t0][t1] == address(0), "PAIR_EXISTS");

        TestnetUniswapV2Pair newPair = new TestnetUniswapV2Pair();
        newPair.initialize(t0, t1);
        pair = address(newPair);

        getPair[t0][t1] = pair;
        getPair[t1][t0] = pair;
        allPairs.push(pair);

        emit PairCreated(t0, t1, pair, allPairs.length);
    }

    // Compatibility stubs
    function feeTo() external pure returns (address) { return address(0); }
    function feeToSetter() external pure returns (address) { return address(0); }
}

// ============================================================================
// ROUTER
// ============================================================================

contract TestnetUniswapV2Router {
    address public immutable factory;
    address public immutable WETH; // not used but required by interface

    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }

    // --- Swap ---
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "EXPIRED");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer input tokens to first pair
        address firstPair = TestnetUniswapV2Factory(factory).getPair(path[0], path[1]);
        IERC20(path[0]).transferFrom(msg.sender, firstPair, amounts[0]);

        // Execute swaps along path
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            address pair = TestnetUniswapV2Factory(factory).getPair(input, output);
            (address token0,) = _sortTokens(input, output);

            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address recipient = i < path.length - 2
                ? TestnetUniswapV2Factory(factory).getPair(path[i + 1], path[i + 2])
                : to;

            TestnetUniswapV2Pair(pair).swap(amount0Out, amount1Out, recipient, "");
        }
    }

    // Fee-on-transfer support (same as above for standard tokens)
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(block.timestamp <= deadline, "EXPIRED");
        address firstPair = TestnetUniswapV2Factory(factory).getPair(path[0], path[1]);
        IERC20(path[0]).transferFrom(msg.sender, firstPair, amountIn);

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = TestnetUniswapV2Factory(factory).getPair(path[i], path[i + 1]);
            (address token0,) = _sortTokens(path[i], path[i + 1]);

            (uint112 r0, uint112 r1,) = TestnetUniswapV2Pair(pair).getReserves();
            uint256 amountInput = IERC20(path[i]).balanceOf(pair) - (path[i] == token0 ? r0 : r1);
            uint256 amountOutput = _getAmountOut(amountInput, path[i] == token0 ? r0 : r1, path[i] == token0 ? r1 : r0);

            (uint256 a0Out, uint256 a1Out) = path[i] == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address recipient = i < path.length - 2
                ? TestnetUniswapV2Factory(factory).getPair(path[i + 1], path[i + 2])
                : to;
            TestnetUniswapV2Pair(pair).swap(a0Out, a1Out, recipient, "");
        }

        require(IERC20(path[path.length - 1]).balanceOf(to) >= amountOutMin, "INSUFFICIENT_OUTPUT");
    }

    // --- Liquidity ---
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "EXPIRED");

        address pair = TestnetUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = TestnetUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }

        (uint112 r0, uint112 r1,) = TestnetUniswapV2Pair(pair).getReserves();
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint256 reserveA, uint256 reserveB) = tokenA == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, "INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        liquidity = TestnetUniswapV2Pair(pair).mint(to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "EXPIRED");

        address pair = TestnetUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");

        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = TestnetUniswapV2Pair(pair).burn(to);

        (address token0,) = _sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");
    }

    // --- View ---
    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = TestnetUniswapV2Factory(factory).getPair(path[i], path[i + 1]);
            require(pair != address(0), "PAIR_NOT_FOUND");
            (uint112 r0, uint112 r1,) = TestnetUniswapV2Pair(pair).getReserves();
            (address token0,) = _sortTokens(path[i], path[i + 1]);
            (uint256 reserveIn, uint256 reserveOut) = path[i] == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            address pair = TestnetUniswapV2Factory(factory).getPair(path[i - 1], path[i]);
            require(pair != address(0), "PAIR_NOT_FOUND");
            (uint112 r0, uint112 r1,) = TestnetUniswapV2Pair(pair).getReserves();
            (address token0,) = _sortTokens(path[i - 1], path[i]);
            (uint256 reserveIn, uint256 reserveOut) = path[i - 1] == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        require(amountA > 0 && reserveA > 0, "INSUFFICIENT_AMOUNT");
        return (amountA * reserveB) / reserveA;
    }

    // --- Internal ---
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "INSUFFICIENT");
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > 0, "INSUFFICIENT");
        return (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1;
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
