// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool);
}

interface IKodiakIslandFactory {
    function deployVault(
        address tokenA,
        address tokenB,
        uint24 uniFee,
        address manager,
        address managerTreasury,
        uint16 managerFee,
        int24 lowerTick,
        int24 upperTick
    ) external returns (address island);
}

interface IKodiakIsland {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function lowerTick() external view returns (int24);
    function upperTick() external view returns (int24);
    function pool() external view returns (address);
    function toggleRestrictMint() external;
}

/**
 * @title DeployKodiakIsland
 * @notice Deploy a Permissionless Kodiak Island (V3) for APIARY/HONEY with $0.50-$1.50 range
 * @dev Creates the V3 pool if needed, initializes at $0.50, deploys the Island.
 *      After this, multisig deposits 30k APIARY via Kodiak Islands UI (single-sided zap).
 *
 * Token ordering: APIARY (0x6F...) < HONEY (0xFC...) -> APIARY = token0, HONEY = token1
 * Price = HONEY/APIARY in raw units: $0.50 = 0.5e18/1e9 = 5e8
 *
 * Tick math (tick spacing = 60 for 0.3% fee):
 *   $0.50 -> tick 200311 -> aligned to 200280 (~$0.4984)
 *   $1.50 -> tick 211298 -> aligned to 211320 (~$1.5033)
 *
 * Usage:
 *   forge script script/deployment/00b_DeployKodiakIsland.s.sol:DeployKodiakIsland \
 *     --rpc-url $BERACHAIN_RPC_URL --private-key $PRIVATE_KEY --broadcast -vv
 */
contract DeployKodiakIsland is Script {

    // Kodiak mainnet addresses (from docs)
    address constant V3_FACTORY = 0xD84CBf0B02636E7f53dB9E5e45A616E05d710990;
    address constant ISLAND_FACTORY = 0x5261c5A5f08818c08Ed0Eb036d9575bA1E02c1d6;

    // V3 pool fee tier: 0.3% = 3000
    uint24 constant FEE = 3000;

    // Tick range for $0.50 - $1.50 (aligned to tick spacing 60)
    int24 constant LOWER_TICK = 200280;  // ~$0.4984/APIARY
    int24 constant UPPER_TICK = 211320;  // ~$1.5033/APIARY

    // sqrtPriceX96 at $0.50/APIARY (pool initialization price)
    // sqrt(5e8) * 2^96 = 1771595571142957102961017161607260
    uint160 constant INIT_SQRT_PRICE_X96 = 1771595571142957102961017161607260;

    function run() external returns (address islandAddr) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");

        console.log("==============================================");
        console.log("  Deploy Kodiak Island (V3) for APIARY/HONEY");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("APIARY (token0):", apiary);
        console.log("HONEY (token1):", honey);
        console.log("Fee tier: 0.3%");
        console.log("Range: ~$0.50 - ~$1.50");

        // Verify token ordering (APIARY should be token0)
        require(apiary < honey, "Token ordering wrong: APIARY must be < HONEY");

        IUniswapV3Factory v3Factory = IUniswapV3Factory(V3_FACTORY);
        address pool = v3Factory.getPool(apiary, honey, FEE);

        // --- Step 1 & 2: Create + initialize V3 pool (separate broadcast) ---
        if (pool == address(0)) {
            console.log("\nSTEP 1: Creating V3 pool...");
            vm.startBroadcast(deployerPrivateKey);
            pool = v3Factory.createPool(apiary, honey, FEE);
            console.log("  V3 pool created:", pool);

            console.log("STEP 2: Initializing pool at $0.50...");
            IUniswapV3Pool(pool).initialize(INIT_SQRT_PRICE_X96);
            console.log("  Pool initialized");
            vm.stopBroadcast();
        } else {
            console.log("\nSTEP 1-2: V3 pool already exists:", pool);
        }

        // --- Step 3: Deploy Permissionless Island (separate broadcast) ---
        console.log("STEP 3: Deploying Permissionless Island...");
        vm.startBroadcast(deployerPrivateKey);

        IKodiakIslandFactory islandFactory = IKodiakIslandFactory(ISLAND_FACTORY);
        islandAddr = islandFactory.deployVault(
            apiary,
            honey,
            FEE,
            address(0), // No manager (permissionless)
            address(0), // No treasury
            0,          // No manager fee
            LOWER_TICK,
            UPPER_TICK
        );
        console.log("  Island deployed:", islandAddr);

        // Verify island
        IKodiakIsland island = IKodiakIsland(islandAddr);
        console.log("  Island token0:", island.token0());
        console.log("  Island token1:", island.token1());
        console.log("  Island pool:", island.pool());

        vm.stopBroadcast();

        // --- Summary ---
        console.log("\n==============================================");
        console.log("  KODIAK ISLAND DEPLOYED");
        console.log("==============================================");
        console.log("  V3 Pool:  ", pool);
        console.log("  Island:   ", islandAddr);
        console.log("  Range:    ~$0.50 - ~$1.50");
        console.log("");
        console.log("  NEXT STEPS (manual via Kodiak UI):");
        console.log("  1. Multisig goes to Kodiak Islands UI");
        console.log("  2. Find this Island or paste address");
        console.log("  3. Deposit 30,000 APIARY (single-sided zap)");
        console.log("  4. As bonds grow V2, gradually reduce V3");
        console.log("==============================================");

        return islandAddr;
    }
}
