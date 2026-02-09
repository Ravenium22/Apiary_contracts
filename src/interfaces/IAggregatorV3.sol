// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IAggregatorV3
/// @notice Minimal Chainlink AggregatorV3 interface for price feed consumption
interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
