// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IApiaryBondingCalculator } from "./interfaces/IApiaryBondingCalculator.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPoint, Babylonian } from "./utils/FixedPoint.sol";

/**
 * @title ApiaryBondingCalculator
 * @author Apiary Protocol
 * @notice Calculates LP token valuations for bond pricing and treasury accounting
 * @dev Uses the "fair LP valuation" formula to prevent manipulation:
 *      value = 2 * sqrt(reserve0 * reserve1) * amount / totalSupply
 *
 *      This formula is manipulation-resistant because:
 *      - sqrt(k) is invariant under constant-product swaps
 *      - An attacker inflating one reserve must deflate the other
 *      - The geometric mean is always <= the arithmetic mean
 *
 *      Returns value in APIARY terms (9 decimals) to match protocol convention.
 *      Compatible with Uniswap V2 / Kodiak pairs.
 */
contract ApiaryBondingCalculator is IApiaryBondingCalculator {
    /// @notice APIARY token address (used to identify which reserve is APIARY)
    address public immutable APIARY;

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_PAIR();
    error APIARY__ZERO_SUPPLY();

    constructor(address _apiary) {
        if (_apiary == address(0)) revert APIARY__ZERO_ADDRESS();
        APIARY = _apiary;
    }

    /**
     * @notice Calculate the value of LP tokens in APIARY terms
     * @dev Uses fair LP valuation: value = 2 * sqrt(reserveA * reserveB) * amount / totalSupply
     *      Then normalizes to APIARY (9 decimal) terms.
     *
     *      The formula works as follows:
     *      1. Get reserves and total supply from the pair
     *      2. Compute sqrt(reserve0 * reserve1) using FixedPoint library
     *      3. Scale by 2 * amount / totalSupply
     *      4. Normalize to 9-decimal APIARY value
     *
     * @param pair_ LP pair address
     * @param amount_ Amount of LP tokens to value
     * @return _value Value in APIARY terms (9 decimals)
     */
    function valuation(address pair_, uint256 amount_) external view override returns (uint256 _value) {
        if (pair_ == address(0)) revert APIARY__ZERO_ADDRESS();

        uint256 totalSupply = IERC20(pair_).totalSupply();
        if (totalSupply == 0) revert APIARY__ZERO_SUPPLY();

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair_).getReserves();

        // Fair LP value = 2 * sqrt(reserve0 * reserve1) * amount / totalSupply
        // Using Babylonian sqrt for precision
        uint256 sqrtK = Babylonian.sqrt(uint256(reserve0) * uint256(reserve1));

        // Get token decimals to normalize to APIARY (9 decimals)
        address token0 = IUniswapV2Pair(pair_).token0();
        address token1 = IUniswapV2Pair(pair_).token1();
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        // sqrtK is in sqrt(decimals0 * decimals1) units
        // We want result in 9-decimal APIARY terms
        // Normalize: sqrtK is in 10^((decimals0 + decimals1)/2) units
        // We need to scale to 9 decimals

        // Calculate value = 2 * sqrtK * amount / totalSupply
        // Scale to 9 decimals from native units
        uint256 avgDecimals = (uint256(decimals0) + uint256(decimals1));

        // value_raw = 2 * sqrtK * amount / totalSupply
        // This is in 10^((d0+d1)/2) units
        // To convert to 9 decimals: multiply by 10^9 / 10^((d0+d1)/2)
        // = multiply by 10^(9 - (d0+d1)/2) if 9 > (d0+d1)/2
        // = divide by 10^((d0+d1)/2 - 9) if (d0+d1)/2 > 9

        // Compute 2 * sqrtK * amount / totalSupply with full precision
        _value = (2 * sqrtK * amount_) / totalSupply;

        // Scale to 9 decimals
        // sqrtK decimal precision = avgDecimals / 2
        // If avgDecimals is odd, we lose a bit of precision (acceptable)
        uint256 sqrtDecimals = avgDecimals / 2;

        if (sqrtDecimals > 9) {
            _value = _value / (10 ** (sqrtDecimals - 9));
        } else if (sqrtDecimals < 9) {
            _value = _value * (10 ** (9 - sqrtDecimals));
        }
        // If sqrtDecimals == 9, no scaling needed
    }
}
