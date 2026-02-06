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

    /// @notice M-01 Fix: Number of full TWAP updates completed
    uint256 public updateCount;
    /// @notice M-01 Fix: Minimum real TWAP updates before oracle can be consulted
    /// @dev MEDIUM-01 Fix: Increased from 2 to 3 to reduce bootstrap manipulation window
    uint256 public constant MIN_UPDATES_REQUIRED = 3;

    error APIARY__ZERO_ADDRESS();
    error APIARY__NO_RESERVES();
    error APIARY__ORACLE_NOT_INITIALIZED();
    error APIARY__ORACLE_STALE();
    /// @notice M-01 Fix: Oracle needs more TWAP updates before it's reliable
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

        // M-01 Fix: Increment update count after real TWAP calculation (not bootstrap)
        updateCount++;
    }

    function consult(uint256 amountIn) external returns (uint256 amountOut) {
        update();

        // C-01 Fix: Ensure oracle has been updated at least once with real TWAP data
        if (price0Average._x == 0) revert APIARY__ORACLE_NOT_INITIALIZED();

        // M-01 Fix: Require multiple TWAP updates to prevent spot price manipulation at bootstrap
        if (updateCount < MIN_UPDATES_REQUIRED) revert APIARY__ORACLE_NOT_READY();
        
        // C-01 Fix: Ensure we're not using stale data (max 2 hours old)
        if (block.timestamp - blockTimestampLast > 2 hours) revert APIARY__ORACLE_STALE();

        amountOut = price0Average.mul(amountIn).decode144();
    }
}
