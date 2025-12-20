// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryTreasury.sol";

/**
 * @title DeployTreasury
 * @notice Deployment script for Apiary Treasury
 * @dev Step 3 of Apiary protocol deployment
 * 
 * Usage:
 *   forge script script/deployment/03_DeployTreasury.s.sol:DeployTreasury \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 * 
 * Environment Variables Required:
 *   - APIARY_ADDRESS: Address of APIARY token
 *   - IBGT_ADDRESS: Address of iBGT token on Berachain
 *   - HONEY_ADDRESS: Address of HONEY stablecoin
 *   - APIARY_HONEY_LP: Address of APIARY/HONEY LP token from Kodiak
 *   - DEPLOYER_ADDRESS: Admin address (should be multisig)
 */
contract DeployTreasury is Script {
    
    function run() external returns (address) {
        // Load environment variables
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address ibgt = vm.envAddress("IBGT_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");
        address apiaryHoneyLP = vm.envAddress("APIARY_HONEY_LP");
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        
        console.log("=== Deploying Apiary Treasury ===");
        console.log("APIARY:", apiary);
        console.log("iBGT:", ibgt);
        console.log("HONEY:", honey);
        console.log("APIARY/HONEY LP:", apiaryHoneyLP);
        console.log("Admin:", admin);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy Treasury
        // Constructor: ApiaryTreasury(admin, _apiary, _ibgt, _honey, _apiaryHoneyLP)
        ApiaryTreasury treasury = new ApiaryTreasury(
            admin,
            apiary,
            ibgt,
            honey,
            apiaryHoneyLP
        );
        
        vm.stopBroadcast();
        
        console.log("\n=== Treasury Deployed ===");
        console.log("Treasury:", address(treasury));
        console.log("Owner:", treasury.owner());
        
        // Sanity checks
        require(treasury.owner() == admin, "Owner not set correctly");
        require(address(treasury.APIARY_TOKEN()) == apiary, "APIARY token not set");
        require(treasury.IBGT() == ibgt, "iBGT not set");
        require(treasury.HONEY() == honey, "HONEY not set");
        require(treasury.APIARY_HONEY_LP() == apiaryHoneyLP, "LP token not set");
        require(treasury.isReserveToken(ibgt), "iBGT not approved as reserve");
        require(treasury.isLiquidityToken(apiaryHoneyLP), "LP not approved as liquidity");
        
        console.log(unicode"\n✓ Treasury deployment successful!");
        console.log(unicode"✓ Owner verified");
        console.log(unicode"✓ Token references verified");
        console.log(unicode"✓ iBGT approved as reserve token");
        console.log(unicode"✓ APIARY/HONEY LP approved as liquidity token");
        console.log(unicode"\n⚠ Next steps:");
        console.log("  1. Set APIARY allocation limit for treasury");
        console.log("  2. Set reserve depositors (bond contracts)");
        console.log("  3. Set liquidity depositors (yield manager)");
        console.log("  4. Set yield manager address");
        
        return address(treasury);
    }
}
