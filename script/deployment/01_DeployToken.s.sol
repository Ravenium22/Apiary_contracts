// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryToken.sol";

/**
 * @title DeployToken
 * @notice Deployment script for APIARY token
 * @dev Step 1 of Apiary protocol deployment
 * 
 * Usage:
 *   forge script script/deployment/01_DeployToken.s.sol:DeployToken \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployToken is Script {
    
    function run() external returns (address) {
        // Load environment variables
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        
        console.log("=== Deploying APIARY Token ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy APIARY token
        // Constructor: ApiaryToken(address protocolAdmin)
        ApiaryToken apiary = new ApiaryToken(deployer);
        
        vm.stopBroadcast();
        
        console.log("\n=== APIARY Token Deployed ===");
        console.log("APIARY:", address(apiary));
        console.log("Supply Model: Uncapped (per-minter allocation limits)");
        console.log("Decimals: 9");
        console.log("Admin:", deployer);
        
        // Sanity checks
        require(apiary.hasRole(apiary.DEFAULT_ADMIN_ROLE(), deployer), "Admin role not set");
        require(apiary.totalSupply() == 0, "Supply should be 0 initially");
        
        console.log(unicode"\n✓ APIARY token deployment successful!");
        console.log(unicode"✓ Admin role verified");
        console.log(unicode"✓ Initial supply: 0 (mint via allocation limits)");
        
        return address(apiary);
    }
}
