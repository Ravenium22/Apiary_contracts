// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ApiaryToken} from "../../src/ApiaryToken.sol";
import {IKodiakFactory} from "../../src/interfaces/IKodiakFactory.sol";
import {IKodiakRouter} from "../../src/interfaces/IKodiakRouter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

/**
 * @title DeployTokenAndCreateLP
 * @notice Phase 0: Deploy APIARY, seed tiny V2 LP, create + init V3 pool
 * @dev Constructor auto-mints 200k APIARY. No extra minting needed.
 *
 * Strategy:
 *   - V2: tiny seed so contracts work (TWAP, bonds, treasury)
 *   - V3: pool initialized BELOW Island lower tick ($0.498) so Island deposit is 100% APIARY
 *   - Island deployment + deposit done separately via cast (factory exceeds forge gas estimate)
 *
 * Usage:
 *   forge script script/deployment/00_DeployTokenAndCreateLP.s.sol:DeployTokenAndCreateLP \
 *     --rpc-url $BERACHAIN_RPC_URL --private-key $PRIVATE_KEY --broadcast -vv
 */
contract DeployTokenAndCreateLP is Script {

    // Kodiak mainnet
    address constant V3_FACTORY = 0xD84CBf0B02636E7f53dB9E5e45A616E05d710990;
    uint24 constant V3_FEE = 3000; // 0.3%

    // Initialize V3 pool at tick 200220 (~$0.495) — BELOW Island lower tick 200280 (~$0.498)
    // This makes Island deposits 100% APIARY (token0), 0 HONEY needed.
    // sqrt(1.0001^200220) * 2^96 = calculated below
    // price at tick 200220 = 1.0001^200220 ≈ 4.954e8
    // sqrtPrice = sqrt(4.954e8) ≈ 22258.7
    // sqrtPriceX96 = 22258.7 * 2^96
    uint160 constant INIT_SQRT_PRICE_X96 = 1763535759953844042750390480595830;

    function run() external returns (address apiaryAddr, address v2PairAddr, address v3PoolAddr) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address honey = vm.envAddress("HONEY_ADDRESS");
        address kodiakRouter = vm.envAddress("KODIAK_ROUTER");
        address kodiakFactory = vm.envAddress("KODIAK_FACTORY");

        console.log("==============================================");
        console.log("  PHASE 0: Deploy APIARY + Create Pools");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("V2: create pair only (multisig seeds liquidity later)");
        console.log("V3: create + init pool (multisig deposits via Island UI)");

        vm.startBroadcast(deployerPrivateKey);

        // --- Step 1: Deploy APIARY token (constructor mints 200k to deployer) ---
        console.log("\nSTEP 1: Deploying APIARY Token...");
        ApiaryToken apiary = new ApiaryToken(deployer);
        apiaryAddr = address(apiary);
        console.log("  APIARY:", apiaryAddr);
        console.log("  Initial supply:", apiary.totalSupply());

        // --- Step 2: Create V2 pair (empty — multisig adds liquidity later) ---
        console.log("STEP 2: Creating V2 pair...");
        IKodiakFactory v2Factory = IKodiakFactory(kodiakFactory);
        v2PairAddr = v2Factory.createPair(apiaryAddr, honey);
        console.log("  V2 pair:", v2PairAddr);
        console.log("  NOTE: Pair is empty. Multisig must addLiquidity before TWAP works.");

        // --- Step 3: Create V3 pool + initialize below Island range ---
        console.log("STEP 3: Creating V3 pool...");
        IUniswapV3Factory v3Factory = IUniswapV3Factory(V3_FACTORY);
        v3PoolAddr = v3Factory.createPool(apiaryAddr, honey, V3_FEE);
        console.log("  V3 pool:", v3PoolAddr);

        IUniswapV3Pool(v3PoolAddr).initialize(INIT_SQRT_PRICE_X96);
        console.log("  V3 initialized at ~$0.495 (below Island lower tick)");

        vm.stopBroadcast();

        // --- Summary ---
        uint256 remainingApiary = apiary.balanceOf(deployer);
        console.log("\n==============================================");
        console.log("  PHASE 0 COMPLETE");
        console.log("==============================================");
        console.log("  APIARY:      ", apiaryAddr);
        console.log("  V2 LP Pair:  ", v2PairAddr);
        console.log("  V3 Pool:     ", v3PoolAddr);
        console.log("  Deployer APIARY remaining:", remainingApiary);
        console.log("");
        console.log("  Set in .env:");
        console.log("    APIARY_ADDRESS=<above>");
        console.log("    LP_PAIR_ADDRESS=<V2 pair above>");
        console.log("");
        console.log("  NEXT STEPS:");
        console.log("  1. Deployer transfers ALL APIARY to multisig");
        console.log("  2. Multisig seeds V2 via Kodiak addLiquidity (APIARY + HONEY)");
        console.log("  3. Multisig deposits APIARY to V3 Island");
        console.log("  4. Multisig does OTC transfers");
        console.log("  5. Run DeployAll.s.sol");
        console.log("  6. Multisig funds pre-sale with remaining APIARY");
        console.log("==============================================");
    }
}
