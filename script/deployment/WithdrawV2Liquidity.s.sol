// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IKodiakRouter} from "../../src/interfaces/IKodiakRouter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/**
 * @title WithdrawV2Liquidity
 * @notice Withdraw all V2 LP tokens from the current test deployment
 *
 * Usage:
 *   forge script script/deployment/WithdrawV2Liquidity.s.sol:WithdrawV2Liquidity \
 *     --rpc-url $BERACHAIN_RPC_URL --private-key $PRIVATE_KEY --broadcast -vv
 */
contract WithdrawV2Liquidity is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address kodiakRouter = vm.envAddress("KODIAK_ROUTER");
        address lpPair = vm.envAddress("LP_PAIR_ADDRESS");
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");

        uint256 lpBalance = IERC20(lpPair).balanceOf(deployer);

        console.log("=== Withdraw V2 Liquidity ===");
        console.log("Deployer:", deployer);
        console.log("LP Pair:", lpPair);
        console.log("LP Balance:", lpBalance);

        require(lpBalance > 0, "No LP tokens to withdraw");

        vm.startBroadcast(deployerPrivateKey);

        IERC20(lpPair).approve(kodiakRouter, lpBalance);

        (uint256 amountApiary, uint256 amountHoney) = IKodiakRouter(kodiakRouter).removeLiquidity(
            apiary,
            honey,
            lpBalance,
            0, // Accept any amount
            0,
            deployer,
            block.timestamp + 300
        );

        vm.stopBroadcast();

        console.log("APIARY received:", amountApiary);
        console.log("HONEY received:", amountHoney);
        console.log("LP remaining:", IERC20(lpPair).balanceOf(deployer));
        console.log("=== Done ===");
    }
}
