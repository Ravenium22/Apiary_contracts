//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { FixedPoint } from "../../src/utils/FixedPoint.sol";
import { UniswapV2OracleLibrary } from "../../src/utils/UniswapV2OracleLibrary.sol";
import { IApiaryUniswapV2TwapOracle } from "../../src/interfaces/IApiaryUniswapV2TwapOracle.sol";

/**
 * @title TestnetTwapOracle
 * @notice Testnet-only TWAP oracle with relaxed timing (1 min period, 1 update required)
 * @dev DO NOT use on mainnet — reduced security parameters for faster testing
 */
contract TestnetTwapOracle is IApiaryUniswapV2TwapOracle {
    using FixedPoint for *;

    uint256 public constant PERIOD = 1 minutes;

    IUniswapV2Pair public immutable APIARY_HONEY_PAIR;

    uint256 public price0CumulativeLast;
    uint32 public blockTimestampLast;

    FixedPoint.uq112x112 public price0Average;

    uint256 public updateCount;
    uint256 public constant MIN_UPDATES_REQUIRED = 1;

    error APIARY__ZERO_ADDRESS();
    error APIARY__NO_RESERVES();
    error APIARY__ORACLE_NOT_INITIALIZED();
    error APIARY__ORACLE_STALE();
    error APIARY__ORACLE_NOT_READY();

    constructor(address _apiaryHoneyPair) {
        if (_apiaryHoneyPair == address(0)) revert APIARY__ZERO_ADDRESS();

        APIARY_HONEY_PAIR = IUniswapV2Pair(_apiaryHoneyPair);

        price0CumulativeLast = APIARY_HONEY_PAIR.price0CumulativeLast();

        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = APIARY_HONEY_PAIR.getReserves();

        if (reserve0 == 0 && reserve1 == 0) revert APIARY__NO_RESERVES();
    }

    function update() public {
        (uint256 price0Cumulative, , uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(APIARY_HONEY_PAIR));

        if (price0Average._x == 0) {
            (uint112 reserve0, uint112 reserve1, ) = APIARY_HONEY_PAIR.getReserves();

            price0Average = FixedPoint.fraction(reserve1, reserve0);
            price0CumulativeLast = price0Cumulative;
            blockTimestampLast = blockTimestamp;
            return;
        }

        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed < PERIOD) return;

        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        blockTimestampLast = blockTimestamp;

        updateCount++;
    }

    function consult(uint256 amountIn) external returns (uint256 amountOut) {
        update();

        if (price0Average._x == 0) revert APIARY__ORACLE_NOT_INITIALIZED();

        if (updateCount < MIN_UPDATES_REQUIRED) revert APIARY__ORACLE_NOT_READY();

        // Relaxed staleness: 1 day for testnet (vs 2 hours on mainnet)
        if (block.timestamp - blockTimestampLast > 1 days) revert APIARY__ORACLE_STALE();

        amountOut = price0Average.mul(amountIn).decode144();
    }
}
