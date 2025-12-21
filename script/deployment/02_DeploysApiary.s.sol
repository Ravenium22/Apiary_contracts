// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/sApiary.sol";

/**
 * @title DeploysApiary
 * @notice Deployment script for sAPIARY (staked APIARY) token
 * @dev Step 2 of Apiary protocol deployment
 * 
 * Usage:
 *   forge script script/deployment/02_DeploysApiary.s.sol:DeploysApiary \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 * 
 * Environment Variables Required:
 *   - PROTOCOL_ADMIN: Address of the protocol admin/owner
 * 
 * Note: sAPIARY must be initialized with staking contract address after deployment
 */
contract DeploysApiary is Script {
    
    function run() external returns (address) {
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
        
        console.log("=== Deploying sAPIARY Token ===");
        console.log("Deployer:", msg.sender);
        console.log("Protocol Admin:", protocolAdmin);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy sAPIARY token
        // Constructor: sApiary(address _initialOwner)
        sApiary sApiaryToken = new sApiary(protocolAdmin);
        
        vm.stopBroadcast();
        
        console.log("\n=== sAPIARY Token Deployed ===");
        console.log("sAPIARY:", address(sApiaryToken));
        console.log("Owner:", sApiaryToken.owner());
        console.log("Decimals: 9");
        console.log("Initializer:", sApiaryToken.initializer());
        console.log("Total Supply:", sApiaryToken.totalSupply() / 1e9);
        
        // Sanity checks
        require(sApiaryToken.owner() == protocolAdmin, "Owner not set correctly");
        require(sApiaryToken.initializer() == msg.sender, "Initializer not set");
        require(sApiaryToken.stakingContract() == address(0), "Staking contract should not be set yet");
        require(sApiaryToken.totalSupply() > 0, "Total supply incorrect");
        
        console.log(unicode"\n✓ sAPIARY token deployment successful!");
        console.log(unicode"✓ Owner verified");
        console.log(unicode"✓ Initializer verified");
        console.log(unicode"⚠ IMPORTANT: Must call initialize(stakingContract) after staking deployment");
        
        return address(sApiaryToken);
    }
}
