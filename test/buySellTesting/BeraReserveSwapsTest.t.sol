// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { BeraReserveBaseTestV2 } from "../setup/BeraReserveBaseV2.t.sol";
import { BeraReserveToken } from "../../src/BeraReserveToken.sol";
import { IUniswapV2Router02 } from "src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "src/interfaces/IUniswapV2Factory.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

contract BeraReserveSwapsTest is BeraReserveBaseTestV2 {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.setTreasuryValue(40_000e6);
        vm.stopPrank();
    }

    function testSwapHoneyForBRR() public {
        updateTwapPrices();
        // Fund worker with Honey
        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_WORKER, 1_000e18);

        vm.prank(BERA_RESERVE_WORKER);
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        // Record initial balances
        uint256 feeDistBalanceBefore = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 brrBalanceBefore = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_WORKER);
        uint256 honeyBalanceBefore = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_WORKER);
        uint256 priceBeforeFirstSwap = simpleTwap.consult(1e9);

        console2.log("priceBeforeFirstSwap", priceBeforeFirstSwap);

        console2.log("BUY BRR");
        vm.startPrank(BERA_RESERVE_WORKER);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            100e18,
            10e9,
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        uint256 feeDistBalanceAfterBuy = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 brrBalanceAfterBuy = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_WORKER);
        uint256 honeyBalanceAfterBuy = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_WORKER);
        assertGt(feeDistBalanceAfterBuy, feeDistBalanceBefore, "fee dist balance should increase");
        assertLt(honeyBalanceAfterBuy, honeyBalanceBefore, "Honey should decrease after buying BRR");
        assertGt(brrBalanceAfterBuy, brrBalanceBefore, "BRR should increase after buying");

        // Prepare to sell BRR
        address[] memory buyPath = new address[](2);

        buyPath[0] = address(beraReserveToken);
        buyPath[1] = HONEY_TOKEN;

        IERC20(address(beraReserveToken)).approve(address(uniswapRouter), 90e9);

        // Advance time for TWAP update
        skip(1 hours);
        uint256 priceAfterFirstSwap = simpleTwap.consult(1e9);
        console2.log("priceAfterFirstSwap", priceAfterFirstSwap);

        assertGt(priceAfterFirstSwap, priceBeforeFirstSwap, "Price should increase after buying");

        console2.log("SELL BRR");

        uint256 amountOut = uniswapRouter.getAmountsOut(90e9, buyPath)[1];
        uint256 minAmountOut = (95 * amountOut) / 100;

        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            90e9,
            minAmountOut,
            buyPath,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        skip(1 hours);
        simpleTwap.update();

        uint256 priceSecondSwap = simpleTwap.consult(1e9);

        uint256 brrBalanceAfterSell = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_WORKER);
        uint256 honeyBalanceAfterSell = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_WORKER);

        assertLt(brrBalanceAfterSell, brrBalanceAfterBuy, "BRR should decrease after selling");
        assertGt(honeyBalanceAfterSell, honeyBalanceAfterBuy, "Honey should increase after selling");
        assertLt(priceSecondSwap, priceAfterFirstSwap, "Price should decrease after selling");

        // Optional feeDistributor assertion (if applicable)
        uint256 feeDistBalanceAfterSell = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        assertGe(feeDistBalanceAfterSell, feeDistBalanceAfterBuy, "Fee distributor BRR balance should not decrease");
    }

    /* TEST SELLING BELOW TREASURY VALUE */
    function testSelling10PercentBelowTreasuryValue() public {
        buyBeraTokens(BERA_RESERVE_WORKER);

        uint256 beraReserveBalanceBefore = beraReserveToken.balanceOf(BERA_RESERVE_WORKER);

        address[] memory addresses = new address[](1);
        addresses[0] = BERA_RESERVE_WORKER;
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.excludeMultipleAccountsFromDecay(addresses, true);
        vm.stopPrank();

        uint256 _10PercentBelowTreasuryValue = (beraReserveToken.getTreasuryValue() * 9_000) / 10_000;

        console2.log("10% below treasury value: ", _10PercentBelowTreasuryValue);

        /**
         * Setting market cap to 10% below treasury value
         */
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.setMarketCap(_10PercentBelowTreasuryValue);

        vm.stopPrank();

        address[] memory buyPath = new address[](2);
        buyPath[0] = address(beraReserveToken);
        buyPath[1] = HONEY_TOKEN;

        uint256 balanceOfTreasuryPrior = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        vm.startPrank(BERA_RESERVE_WORKER);

        IERC20(address(beraReserveToken)).approve(address(uniswapRouter), 90e9);

        //5% slippage
        uint256 amountOut = uniswapRouter.getAmountsOut(90e9, buyPath)[1];
        uint256 slippage = (95 * amountOut) / 100;
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            90e9,
            slippage,
            buyPath,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        vm.stopPrank();

        uint256 balanceOfTreasuryAfter = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        assertLt(
            beraReserveToken.balanceOf(BERA_RESERVE_WORKER),
            beraReserveBalanceBefore,
            "beraReserve balance should be less than beraReserveBalanceBefore"
        );

        console2.log("FeeDistributor balance: ", beraReserveToken.balanceOf(address(feeDistributor)));

        console2.log(
            "BERA_RESERVE_WORKER beraReserve balance: ",
            beraReserveBalanceBefore - beraReserveToken.balanceOf(BERA_RESERVE_WORKER)
        );

        assertGt(balanceOfTreasuryAfter, balanceOfTreasuryPrior);
    }

    function testSelling25PercentBelowTreasuryValue() public {
        buyBeraTokens(BERA_RESERVE_WORKER);
        uint256 beraReserveBalanceBefore = beraReserveToken.balanceOf(BERA_RESERVE_WORKER);

        address[] memory addresses = new address[](1);
        addresses[0] = BERA_RESERVE_WORKER;

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.excludeMultipleAccountsFromDecay(addresses, true);
        vm.stopPrank();

        uint256 _25PercentBelowTreasuryValue = (beraReserveToken.getTreasuryValue() * 75_000) / 100_000;

        /**
         * Setting market cap to 25% below treasury value
         */
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.setMarketCap(_25PercentBelowTreasuryValue - 100e6);

        vm.stopPrank();

        address[] memory path = new address[](2);
        path[0] = address(beraReserveToken);
        path[1] = HONEY_TOKEN;

        vm.startPrank(BERA_RESERVE_WORKER);
        uint256 balanceOfTreasuryPrior = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        IERC20(address(beraReserveToken)).approve(address(uniswapRouter), 90e9);

        //5% slippage
        uint256 amountOut = uniswapRouter.getAmountsOut(90e9, path)[1];
        uint256 slippage = (95 * amountOut) / 100;
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            90e9,
            slippage,
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        vm.stopPrank();

        uint256 balanceOfTreasuryAfter = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        assertLt(
            beraReserveToken.balanceOf(BERA_RESERVE_WORKER),
            beraReserveBalanceBefore,
            "beraReserve balance should be less than beraReserveBalanceBefore"
        );

        console2.log("FeeDistributor balance: ", beraReserveToken.balanceOf(address(feeDistributor)));

        console2.log(
            "BERA_RESERVE_WORKER beraReserve balance: ",
            beraReserveBalanceBefore - beraReserveToken.balanceOf(BERA_RESERVE_WORKER)
        );

        assertGt(balanceOfTreasuryAfter, balanceOfTreasuryPrior);
    }

    function testSellBelowTreasuryValue() public {
        buyBeraTokens(BERA_RESERVE_WORKER);
        uint256 beraReserveBalanceBefore = beraReserveToken.balanceOf(BERA_RESERVE_WORKER);

        address[] memory addresses = new address[](1);
        addresses[0] = BERA_RESERVE_WORKER;
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.excludeMultipleAccountsFromDecay(addresses, true);
        vm.stopPrank();

        console2.log("Treasury Value: ", beraReserveToken.getTreasuryValue());

        uint256 _belowTreasuryValue = beraReserveToken.getTreasuryValue() - 90e6;

        console2.log("Below Treasury Value: ", _belowTreasuryValue);

        /**
         * Setting market cap to below treasury value
         */
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.setMarketCap(_belowTreasuryValue);

        vm.stopPrank();

        address[] memory path = new address[](2);
        path[0] = address(beraReserveToken);
        path[1] = HONEY_TOKEN;

        uint256 balanceOfTreasuryPrior = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        vm.startPrank(BERA_RESERVE_WORKER);

        IERC20(address(beraReserveToken)).approve(address(uniswapRouter), 90e9);

        //5% slippage
        uint256 amountOut = uniswapRouter.getAmountsOut(90e9, path)[1];
        uint256 slippage = (95 * amountOut) / 100;
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            90e9,
            slippage,
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );
        vm.stopPrank();

        uint256 balanceOfTreasuryAfter = beraReserveToken.balanceOf(PROTOCOL_TREASURY);

        assertLt(
            beraReserveToken.balanceOf(BERA_RESERVE_WORKER),
            beraReserveBalanceBefore,
            "beraReserve balance should be less than beraReserveBalanceBefore"
        );

        console2.log(
            "BERA_RESERVE_WORKER beraReserve balance: ",
            beraReserveBalanceBefore - beraReserveToken.balanceOf(BERA_RESERVE_WORKER)
        );

        assertGt(balanceOfTreasuryAfter, balanceOfTreasuryPrior);
    }

    /**
     * HELPERS
     */
    function buyBeraTokens(address _to) public {
        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(_to, 1_000e18);

        vm.prank(_to);
        //approve honey
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        console2.log("feeDistributor balance prior: ", IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor)));
        console2.log("beraReserveToken balance prior: ", IERC20(address(beraReserveToken)).balanceOf(_to));
        console2.log("honey balance prior", IERC20(HONEY_TOKEN).balanceOf(_to));

        vm.startPrank(_to);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(100e18, 10e9, path, _to, block.timestamp + 1000);
    }

    function updateTwapPrices() internal {
        skip(1 hours);
        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_WORKER, 1_000e18);

        vm.prank(BERA_RESERVE_WORKER);
        //approve honey
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        vm.startPrank(BERA_RESERVE_WORKER);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            100e18,
            10e9,
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        vm.stopPrank();

        simpleTwap.update();

        console2.log("Price After Update", simpleTwap.consult(1e9));
    }
}
