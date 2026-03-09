// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";

/// @title MockPriceFeed
/// @notice Testnet-only mock Chainlink price feed for iBGT/USD
/// @dev Owner can update the price. DO NOT use in production.
contract MockPriceFeed is IAggregatorV3 {
    int256 private _price;
    uint8 private _decimals;
    uint80 private _roundId;
    address public owner;

    constructor(int256 initialPrice, uint8 feedDecimals) {
        _price = initialPrice;
        _decimals = feedDecimals;
        _roundId = 1;
        owner = msg.sender;
    }

    function setPrice(int256 newPrice) external {
        require(msg.sender == owner, "MockPriceFeed: not owner");
        _price = newPrice;
        _roundId++;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, block.timestamp, block.timestamp, _roundId);
    }
}
