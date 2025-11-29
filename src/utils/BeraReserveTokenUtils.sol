// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { TreasuryValueData } from "src/types/BeraReserveTypes.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IUniswapV2Router02 } from "src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "src/interfaces/IUniswapV2Pair.sol";

library BeraReserveTokenUtils {
    using Math for uint256;
    using Math for uint48;

    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant DECAY_PERIOD = 365 * 24 * 60 * 60 seconds; // 1 year

    function beraReservePrice(address BERA, address USDC, IUniswapV2Router02 uniswapV2Router)
        public
        view
        returns (uint256 tokenPriceValueInUSDC)
    {
        address[] memory path = new address[](2);
        path[0] = address(this); //BRR token
        path[1] = BERA;

        uint256 priceInBERA = uniswapV2Router.getAmountsOut(1e9, path)[1];

        //usdc to bera
        address[] memory path2 = new address[](2);
        path2[0] = BERA;
        path2[1] = USDC;

        tokenPriceValueInUSDC = uniswapV2Router.getAmountsOut(priceInBERA, path2)[1];
    }

    function calculateSlidingScaleFee(
        uint256 mCap,
        uint256 treasuryValue,
        uint256 sellFee,
        uint256 tenPercentBelowTreasuryFees,
        uint256 twentyFivePercentBelowTreasuryFees,
        uint256 belowTreasuryValueFees
    ) public pure returns (TreasuryValueData memory rvfData) {
        if (mCap > treasuryValue) {
            rvfData.fee = sellFee;

            return rvfData;
        }

        uint256 tenPercentBelowTreasury = treasuryValue.mulDiv(9_000, BASIS_POINTS);
        uint256 twentyFivePercentBelowTreasury = treasuryValue.mulDiv(7_500, BASIS_POINTS);

        uint256 burn_treasuryFee_25Perc = twentyFivePercentBelowTreasury / 2;
        uint256 burn_treasuryFee_10Perc = tenPercentBelowTreasury / 2;
        uint256 burn_treasuryFee_belowTreasury = belowTreasuryValueFees / 2;

        if (mCap <= twentyFivePercentBelowTreasury) {
            rvfData.fee = twentyFivePercentBelowTreasuryFees; // 16%
            rvfData.treasuryPercentage = burn_treasuryFee_25Perc;
            rvfData.burnPercentage = burn_treasuryFee_25Perc;
            return rvfData; // 16%
        } else if (mCap <= tenPercentBelowTreasury) {
            rvfData.fee = tenPercentBelowTreasuryFees; // 12%
            rvfData.treasuryPercentage = burn_treasuryFee_10Perc;
            rvfData.burnPercentage = burn_treasuryFee_10Perc;
            return rvfData;
        } else if (mCap <= treasuryValue) {
            rvfData.fee = belowTreasuryValueFees; // 10%
            rvfData.treasuryPercentage = burn_treasuryFee_belowTreasury;
            rvfData.burnPercentage = burn_treasuryFee_belowTreasury;
            return rvfData;
        }
    }

    function applyDecay(
        uint256 decayRatio,
        uint256 balance,
        uint48 lastTimeBurnt,
        uint48 lastTimeReceived,
        uint48 lastTimeStaked,
        uint256 decayInterval // Configurable decay interval in seconds
    ) public view returns (uint256 tokensToBurn) {
        // Calculate the time elapsed since the last time the caller burnt tokens
        uint256 elapsedTimeSinceLastBurn = block.timestamp - lastTimeBurnt;

        // Only proceed if enough time has passed for at least one decay interval
        if (elapsedTimeSinceLastBurn < decayInterval) return 0;

        // Calculate the time elapsed since the last time the caller staked or received tokens
        uint256 elapsedTime;
        uint256 elapsedTimeSinceReceived = block.timestamp - lastTimeReceived;
        uint256 elapsedTimeSinceStaked = block.timestamp - lastTimeStaked;

        if (lastTimeStaked == 0 || elapsedTimeSinceReceived < elapsedTimeSinceStaked) {
            elapsedTime = elapsedTimeSinceReceived;
        } else {
            elapsedTime = elapsedTimeSinceStaked;
        }

        if (elapsedTime < decayInterval) return 0;

        //ex. decayRatio = 20000, elapsed time = 11 hours, decayInterval = 8 hours, DECAY_PERIOD = 31536000
        // elapsedEpoch = 11 / 8 = 1.375 = 1 epoch
        uint256 elapsedEpoch = elapsedTime / decayInterval; // Number of decay intervals elapsed

        // ex: decayRatio = 2_0000, decayInterval = 8 hours, DECAY_PERIOD = 31536000
        // decayRatePerEpoch = 2_0000 * 8 hours * 1e18 / (10_000 * 31536000) = 1.826.
        uint256 decayRatePerEpoch = (decayRatio * decayInterval * 1e18) / (BASIS_POINTS * DECAY_PERIOD);

        uint256 decayAmountPerPeriod = balance.mulDiv(decayRatePerEpoch, 1e18);

        uint256 decayAmount = decayAmountPerPeriod * elapsedEpoch;

        // Cap the decay amount to the balance
        if (decayAmount > balance) decayAmount = balance;

        // The tokens to burn is the calculated decay amount
        tokensToBurn = decayAmount;
    }

    function applySlidingScaleFee(
        uint256 mCap,
        uint256 treasuryValue,
        uint256 sellFee,
        uint256 tenPercentBelowTreasuryFees,
        uint256 twentyFivePercentBelowTreasuryFees,
        uint256 belowTreasuryValueFees
    ) public pure returns (uint256 fee, uint256 treasuryFee, uint256 burnFee) {
        TreasuryValueData memory rvfData = calculateSlidingScaleFee(
            mCap,
            treasuryValue,
            sellFee,
            tenPercentBelowTreasuryFees,
            twentyFivePercentBelowTreasuryFees,
            belowTreasuryValueFees
        );
        fee = rvfData.fee;

        treasuryFee = fee.mulDiv(rvfData.treasuryPercentage, BASIS_POINTS);
        burnFee = fee.mulDiv(rvfData.burnPercentage, BASIS_POINTS);
    }
}
