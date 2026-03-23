// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestnetUniswapV2Factory, TestnetUniswapV2Router, TestnetUniswapV2Pair} from "./TestnetUniswapV2.sol";

/**
 * @title DeployTestnetDEX
 * @notice Deploys a minimal UniswapV2 DEX on Bepolia and optionally seeds an APIARY/HONEY pool.
 *
 * Usage:
 *
 *   Step 1 — Deploy DEX (Factory + Router):
 *     forge script script/testnet/DeployTestnetDEX.s.sol:DeployDEX \
 *       --rpc-url $BEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 *
 *   Step 2 — After deploying APIARY via DeployAll, seed the LP pool:
 *     forge script script/testnet/DeployTestnetDEX.s.sol:SeedLiquidity \
 *       --rpc-url $BEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
 *
 * The Factory and Router addresses go into .env as KODIAK_FACTORY and KODIAK_ROUTER.
 */

// ============================================================================
// STEP 1: Deploy Factory + Router
// ============================================================================

contract DeployDEX is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address weth = address(0xdead); // placeholder, not used

        vm.startBroadcast(pk);

        TestnetUniswapV2Factory factory = new TestnetUniswapV2Factory();
        TestnetUniswapV2Router router = new TestnetUniswapV2Router(address(factory), weth);

        vm.stopBroadcast();

        console.log("==============================================");
        console.log("  Testnet UniswapV2 DEX Deployed");
        console.log("==============================================");
        console.log("  Factory:", address(factory));
        console.log("  Router: ", address(router));
        console.log("");
        console.log("  Add to .env.bepolia:");
        console.log("  KODIAK_FACTORY=", address(factory));
        console.log("  KODIAK_ROUTER=", address(router));
        console.log("==============================================");
    }
}

// ============================================================================
// STEP 2: Create APIARY/HONEY pair + seed liquidity
// ============================================================================

contract SeedLiquidity is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address apiary = vm.envAddress("APIARY_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");
        address routerAddr = vm.envAddress("KODIAK_ROUTER");
        address factoryAddr = vm.envAddress("KODIAK_FACTORY");

        // Amounts to seed: sets initial price at $0.50 per APIARY
        // 100 APIARY (9 dec) + 50 HONEY (18 dec) = $0.50/APIARY
        uint256 apiaryAmount = vm.envOr("SEED_APIARY_AMOUNT", uint256(100e9));    // 100 APIARY
        uint256 honeyAmount  = vm.envOr("SEED_HONEY_AMOUNT",  uint256(50e18));    // 50 HONEY

        TestnetUniswapV2Router router = TestnetUniswapV2Router(routerAddr);
        TestnetUniswapV2Factory factory = TestnetUniswapV2Factory(factoryAddr);

        console.log("==============================================");
        console.log("  Seeding APIARY/HONEY Liquidity");
        console.log("==============================================");
        console.log("  APIARY:", apiary);
        console.log("  HONEY: ", honey);
        console.log("  Router:", routerAddr);
        console.log("  APIARY amount:", apiaryAmount);
        console.log("  HONEY amount: ", honeyAmount);
        console.log("");

        // Check balances
        uint256 apiaryBal = IERC20(apiary).balanceOf(deployer);
        uint256 honeyBal = IERC20(honey).balanceOf(deployer);
        console.log("  Deployer APIARY balance:", apiaryBal);
        console.log("  Deployer HONEY balance: ", honeyBal);
        require(apiaryBal >= apiaryAmount, "SeedLiquidity: insufficient APIARY balance");
        require(honeyBal >= honeyAmount, "SeedLiquidity: insufficient HONEY balance");

        vm.startBroadcast(pk);

        // Approve router
        IERC20(apiary).approve(routerAddr, apiaryAmount);
        IERC20(honey).approve(routerAddr, honeyAmount);

        // Add liquidity (creates pair if it doesn't exist)
        (uint256 actualA, uint256 actualB, uint256 lp) = router.addLiquidity(
            apiary,
            honey,
            apiaryAmount,
            honeyAmount,
            0, // min amounts (testnet, no slippage concern)
            0,
            deployer,
            block.timestamp + 600
        );

        vm.stopBroadcast();

        // Get pair address
        address pair = factory.getPair(apiary, honey);

        console.log("");
        console.log("  Liquidity added!");
        console.log("  APIARY deposited:", actualA);
        console.log("  HONEY deposited: ", actualB);
        console.log("  LP tokens minted:", lp);
        console.log("");
        console.log("  LP Pair Address: ", pair);
        console.log("");
        console.log("  Add to .env.bepolia:");
        console.log("  LP_PAIR_ADDRESS=", pair);
        console.log("  APIARY_HONEY_LP=", pair);
        console.log("==============================================");
    }
}
