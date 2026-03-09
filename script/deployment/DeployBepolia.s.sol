// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockPriceFeed} from "./MockPriceFeed.sol";

/**
 * @title DeployBepolia
 * @notice Deploys a mock iBGT/USD price feed on Bepolia testnet, then prints
 *         the address for use with DeployAll.s.sol.
 *
 * Usage:
 *   1. Deploy mock price feed:
 *      forge script script/deployment/DeployBepolia.s.sol:DeployMockPriceFeed \
 *        --rpc-url $BEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 *
 *   2. Copy the printed IBGT_PRICE_FEED address into your .env.bepolia
 *
 *   3. Deploy the full protocol:
 *      source .env.bepolia && forge script script/deployment/DeployAll.s.sol:DeployAll \
 *        --rpc-url $BEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployMockPriceFeed is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock iBGT/USD feed: $3.00 initial price, 8 decimals (Chainlink standard)
        MockPriceFeed priceFeed = new MockPriceFeed(3_00000000, 8);

        vm.stopBroadcast();

        console.log("==============================================");
        console.log("  Mock iBGT/USD Price Feed Deployed");
        console.log("==============================================");
        console.log("  Address:", address(priceFeed));
        console.log("  Price:   $3.00 (300000000, 8 decimals)");
        console.log("  Owner:  ", vm.addr(deployerPrivateKey));
        console.log("");
        console.log("  Add to .env.bepolia:");
        console.log("  IBGT_PRICE_FEED=<address above>");
        console.log("==============================================");

        return address(priceFeed);
    }
}
