// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IBeraReserveUniswapV2TwapOracle {
    function update() external;

    function consult(uint256 amountIn) external returns (uint256 amountOut);
}
