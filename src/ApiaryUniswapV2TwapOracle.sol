//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { FixedPoint } from "./utils/FixedPoint.sol";
import { UniswapV2OracleLibrary } from "./utils/UniswapV2OracleLibrary.sol";
import { IApiaryUniswapV2TwapOracle } from "./interfaces/IApiaryUniswapV2TwapOracle.sol";

/**
 * @title ApiaryUniswapV2TwapOracle
 * @notice TWAP oracle for APIARY/HONEY pair pricing
 * @dev Uses time-weighted average prices from Uniswap V2 style pairs
 */
contract ApiaryUniswapV2TwapOracle is IApiaryUniswapV2TwapOracle {
    using FixedPoint for *;

    uint256 public constant PERIOD = 1 hours;

    IUniswapV2Pair public immutable APIARY_HONEY_PAIR;

    uint256 public price0CumulativeLast;
    uint32 public blockTimestampLast;

    FixedPoint.uq112x112 public price0Average;

    error ZERO_ADDRESS();
    error NO_RESERVES();

    constructor(address _apiaryHoneyPair) {
        if (_apiaryHoneyPair == address(0)) revert ZERO_ADDRESS();

        APIARY_HONEY_PAIR = IUniswapV2Pair(_apiaryHoneyPair);

        price0CumulativeLast = APIARY_HONEY_PAIR.price0CumulativeLast();

        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = APIARY_HONEY_PAIR.getReserves();

        if (reserve0 == 0 && reserve1 == 0) revert NO_RESERVES();
    }

    function update() public {
        (uint256 price0Cumulative, , uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(APIARY_HONEY_PAIR));

        // If no TWAP exists yet, bootstrap using the spot price
        if (price0Average._x == 0) {
            (uint112 reserve0, uint112 reserve1, ) = APIARY_HONEY_PAIR.getReserves();

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
