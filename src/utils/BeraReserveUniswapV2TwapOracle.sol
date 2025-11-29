//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { FixedPoint } from "./FixedPoint.sol";
import { UniswapV2OracleLibrary } from "./UniswapV2OracleLibrary.sol";
import { IBeraReserveUniswapV2TwapOracle } from "../interfaces/IBeraReserveUniswapV2TwapOracle.sol";
contract BeraReserveUniswapV2TwapOracle is IBeraReserveUniswapV2TwapOracle {
    using FixedPoint for *;

    uint256 public constant PERIOD = 1 hours;

    IUniswapV2Pair public immutable BRR_HONEY_PAIR;

    uint256 public price0CumulativeLast;
    uint32 public blockTimestampLast;

    FixedPoint.uq112x112 public price0Average;

    error ZERO_ADDRESS();
    error NO_RESERVES();

    constructor(address _brrHoneyPair) {
        if (_brrHoneyPair == address(0)) revert ZERO_ADDRESS();

        BRR_HONEY_PAIR = IUniswapV2Pair(_brrHoneyPair);

        price0CumulativeLast = BRR_HONEY_PAIR.price0CumulativeLast();

        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = BRR_HONEY_PAIR.getReserves();

        if (reserve0 == 0 && reserve1 == 0) revert NO_RESERVES();
    }

    function update() public {
        (uint256 price0Cumulative, , uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(BRR_HONEY_PAIR));

        // If no TWAP exists yet, bootstrap using the spot price
        if (price0Average._x == 0) {
            (uint112 reserve0, uint112 reserve1, ) = BRR_HONEY_PAIR.getReserves();

            price0Average = FixedPoint.fraction(reserve1, reserve0);
            price0CumulativeLast = price0Cumulative;
            blockTimestampLast = blockTimestamp;
            return;
        }

        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed < PERIOD) return;

        // Standard TWAP calculation
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function consult(uint256 amountIn) external returns (uint256 amountOut) {
        update();

        amountOut = price0Average.mul(amountIn).decode144();
    }
}
