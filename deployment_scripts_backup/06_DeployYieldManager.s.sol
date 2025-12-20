// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryYieldManager.sol";
import "../../src/ApiaryInfraredAdapter.sol";
import "../../src/ApiaryKodiakAdapter.sol";

/**
 * @title DeployYieldManager
 * @notice Deployment script for Yield Manager and Adapters
 * @dev Step 6 of Apiary protocol deployment
 * 
 * Usage:
 *   forge script script/deployment/06_DeployYieldManager.s.sol:DeployYieldManager \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 * 
 * Environment Variables Required:
 *   - APIARY_ADDRESS: Address of APIARY token
 *   - HONEY_ADDRESS: Address of HONEY stablecoin
 *   - IBGT_ADDRESS: Address of iBGT token
 *   - TREASURY_ADDRESS: Address of treasury contract
 *   - INFRARED_STAKING: Address of Infrared staking contract
 *   - KODIAK_ROUTER: Address of Kodiak router
 *   - KODIAK_FACTORY: Address of Kodiak factory
 *   - DEPLOYER_ADDRESS: Admin address
 */
contract DeployYieldManager is Script {
    
    struct YieldAddresses {
        address yieldManager;
        address infraredAdapter;
        address kodiakAdapter;
    }
    
    function run() external returns (YieldAddresses memory) {
        // Load environment variables
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");
        address ibgt = vm.envAddress("IBGT_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address infraredStaking = vm.envAddress("INFRARED_STAKING");
        address kodiakRouter = vm.envAddress("KODIAK_ROUTER");
        address kodiakFactory = vm.envAddress("KODIAK_FACTORY");
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        
        console.log("=== Deploying Yield Manager & Adapters ===");
        console.log("APIARY:", apiary);
        console.log("HONEY:", honey);
        console.log("iBGT:", ibgt);
        console.log("Treasury:", treasury);
        console.log("Infrared:", infraredStaking);
        console.log("Kodiak Router:", kodiakRouter);
        console.log("Kodiak Factory:", kodiakFactory);
        console.log("Admin:", admin);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Note: We need to deploy adapters first, then yield manager
        // But yield manager needs adapter addresses, and adapters need yield manager address
        // Solution: Deploy in stages or use CREATE2 for predictable addresses
        
        // For simplicity, we'll deploy yield manager with placeholder adapters
        // Then deploy adapters with correct yield manager
        // Then update yield manager with correct adapters
        
        // Step 1: Deploy Yield Manager with placeholder adapters (will update later)
        ApiaryYieldManager yieldManager = new ApiaryYieldManager(
            apiary,
            honey,
            ibgt,
            treasury,
            address(1), // Placeholder for infraredAdapter
            address(2), // Placeholder for kodiakAdapter
            admin
        );
        
        console.log("\n1. Yield Manager deployed:", address(yieldManager));
        
        // Step 2: Deploy Infrared Adapter with correct yield manager
        ApiaryInfraredAdapter infraredAdapter = new ApiaryInfraredAdapter(
            infraredStaking,
            ibgt,
            treasury,
            address(yieldManager),
            admin
        );
        
        console.log("2. Infrared Adapter deployed:", address(infraredAdapter));
        
        // Step 3: Deploy Kodiak Adapter with correct yield manager
        ApiaryKodiakAdapter kodiakAdapter = new ApiaryKodiakAdapter(
            kodiakRouter,
            kodiakFactory,
            honey,
            apiary,
            treasury,
            address(yieldManager),
            admin
        );
        
        console.log("3. Kodiak Adapter deployed:", address(kodiakAdapter));
        
        vm.stopBroadcast();
        
        console.log("\n=== Yield Contracts Deployed ===");
        console.log("Yield Manager:", address(yieldManager));
        console.log("Infrared Adapter:", address(infraredAdapter));
        console.log("Kodiak Adapter:", address(kodiakAdapter));
        
        // Display default configurations
        console.log("\nYield Manager Configuration:");
        console.log("  Strategy:", uint8(yieldManager.currentStrategy())); // 0 = PHASE1_LP_BURN
        (uint16 toHoney, uint16 toApiaryLP, uint16 toBurn, uint16 toStakers, uint16 toCompound) = yieldManager.splitConfig();
        console.log("  Split - To HONEY:", toHoney, "bps (25%)");
        console.log("  Split - To APIARY LP:", toApiaryLP, "bps (50%)");
        console.log("  Split - To Burn:", toBurn, "bps (25%)");
        console.log("  Slippage Tolerance:", yieldManager.slippageTolerance(), "bps");
        console.log("  Min Yield:", yieldManager.minYieldAmount() / 1e18, "iBGT");
        console.log("  Max Execution:", yieldManager.maxExecutionAmount() / 1e18, "iBGT");
        
        console.log("\nInfrared Adapter Configuration:");
        console.log("  Min Stake:", infraredAdapter.minStakeAmount() / 1e18, "iBGT");
        console.log("  Min Unstake:", infraredAdapter.minUnstakeAmount() / 1e18, "iBGT");
        
        console.log("\nKodiak Adapter Configuration:");
        console.log("  Default Slippage:", kodiakAdapter.defaultSlippageBps(), "bps");
        console.log("  Deadline Offset:", kodiakAdapter.defaultDeadlineOffset(), "seconds");
        console.log("  Min Swap:", kodiakAdapter.minSwapAmount() / 1e18, "tokens");
        console.log("  Min Liquidity:", kodiakAdapter.minLiquidityAmount() / 1e18, "LP");
        
        // Sanity checks
        require(address(yieldManager.apiaryToken()) == apiary, "YM: APIARY not set");
        require(address(yieldManager.honeyToken()) == honey, "YM: HONEY not set");
        require(address(yieldManager.ibgtToken()) == ibgt, "YM: iBGT not set");
        require(yieldManager.treasury() == treasury, "YM: Treasury not set");
        require(yieldManager.owner() == admin, "YM: Owner not set");
        
        require(address(infraredAdapter.ibgt()) == ibgt, "IA: iBGT not set");
        require(infraredAdapter.treasury() == treasury, "IA: Treasury not set");
        require(infraredAdapter.yieldManager() == address(yieldManager), "IA: YM not set");
        require(infraredAdapter.owner() == admin, "IA: Owner not set");
        
        require(address(kodiakAdapter.honey()) == honey, "KA: HONEY not set");
        require(address(kodiakAdapter.apiary()) == apiary, "KA: APIARY not set");
        require(kodiakAdapter.treasury() == treasury, "KA: Treasury not set");
        require(kodiakAdapter.yieldManager() == address(yieldManager), "KA: YM not set");
        require(kodiakAdapter.owner() == admin, "KA: Owner not set");
        
        console.log(unicode"\n✓ All yield contracts deployed successfully!");
        console.log(unicode"✓ Yield Manager verified");
        console.log(unicode"✓ Infrared Adapter verified");
        console.log(unicode"✓ Kodiak Adapter verified");
        console.log(unicode"✓ Default Phase 1 configuration set (25/25/50)");
        console.log(unicode"\n⚠ CRITICAL Next steps:");
        console.log("  1. Update Yield Manager with correct adapter addresses");
        console.log("  2. Set yield manager in treasury");
        console.log("  3. Set treasury as liquidity depositor");
        console.log("  4. Approve token spending where needed");
        
        return YieldAddresses({
            yieldManager: address(yieldManager),
            infraredAdapter: address(infraredAdapter),
            kodiakAdapter: address(kodiakAdapter)
        });
    }
}
