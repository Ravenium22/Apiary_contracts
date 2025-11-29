// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test, console2 } from "lib/forge-std/src/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { IUniswapV2Pair } from "src/interfaces/IUniswapV2Pair.sol";
import { BeraReserveUniswapV2TwapOracle } from "src/utils/BeraReserveUniswapV2TwapOracle.sol";

contract BeraReserveUniswapV2TwapOracleTest is BeraReserveBaseTestV2 {
    function testRevertIfZeroAddress() public {
        vm.expectRevert(BeraReserveUniswapV2TwapOracle.ZERO_ADDRESS.selector);
        new BeraReserveUniswapV2TwapOracle(address(0));
    }
    function testInitialConsultBootstrapsSpotPrice() public {
        skip(1 hours); // make sure PERIOD has passed
        uint256 consultOut = simpleTwap.consult(1e18);

        assertGt(consultOut, 0, "Consult should return a non-zero amount after bootstrapping");
    }

    function testCheckUpdateWorksCorrectly() public {
        // Initial consult (should bootstrap TWAP if not yet done)
        uint256 brrPrice = simpleTwap.consult(1e9);
        console2.log("Initial brrPrice", brrPrice);
        assertGt(brrPrice, 0, "Initial TWAP price should be greater than zero");

        // Skip 5 minutes to simulate time passing but not enough for full update
        skip(5 minutes);
        uint256 priceAfter5Mins = simpleTwap.consult(1e9);
        console2.log("brrPrice after 5 minutes", priceAfter5Mins);

        // Assert price should still be the same (not enough time passed for TWAP update)
        assertEq(priceAfter5Mins, brrPrice, "Price should not change if PERIOD not elapsed");

        // Simulate a trade: HONEY -> BRR to move price
        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_WORKER, 1_000e18);

        vm.prank(BERA_RESERVE_WORKER);
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        vm.startPrank(BERA_RESERVE_WORKER);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            100e18,
            10e9, // minimum amount out
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );
        vm.stopPrank();

        // Skip enough time for TWAP to update
        skip(1 hours);

        uint256 newBrrPriceAfterSwap = simpleTwap.consult(1e9);
        console2.log("newBrrPriceAfterSwap", newBrrPriceAfterSwap);

        // Assert the price has changed after the swap and TWAP period elapsed
        assertTrue(newBrrPriceAfterSwap != brrPrice, "TWAP should reflect updated price after swap");
        assertTrue(newBrrPriceAfterSwap != 0, "New TWAP price should not be zero");
    }
}
