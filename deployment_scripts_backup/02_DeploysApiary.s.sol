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
 * Note: sAPIARY must be initialized with staking contract address after deployment
 */
contract DeploysApiary is Script {
    
    function run() external returns (address) {
        console.log("=== Deploying sAPIARY Token ===");
        console.log("Deployer:", msg.sender);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy sAPIARY token
        // Constructor: sApiary() - no parameters
        sApiary sApiaryToken = new sApiary();
        
        vm.stopBroadcast();
        
        console.log("\n=== sAPIARY Token Deployed ===");
        console.log("sAPIARY:", address(sApiaryToken));
        console.log("Decimals:", 9);
        console.log("Initializer:", sApiaryToken.initializer());
        console.log("Initial Fragments Supply:", sApiaryToken.INITIAL_FRAGMENTS_SUPPLY() / 1e9);
        
        // Sanity checks
        require(sApiaryToken.initializer() == msg.sender, "Initializer not set");
        require(sApiaryToken.stakingContract() == address(0), "Staking contract should not be set yet");
        require(sApiaryToken.totalSupply() == sApiaryToken.INITIAL_FRAGMENTS_SUPPLY(), "Total supply incorrect");
        
        console.log(unicode"\n✓ sAPIARY token deployment successful!");
        console.log(unicode"✓ Initializer verified");
        console.log(unicode"⚠ IMPORTANT: Must call initialize(stakingContract) after staking deployment");
        
        return address(sApiaryToken);
    }
}
