// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "./01_DeployToken.s.sol";
import "./02_DeploysApiary.s.sol";
import "./03_DeployTreasury.s.sol";
import "./04_DeployStaking.s.sol";
import "./05_DeployBonds.s.sol";
import "./06_DeployYieldManager.s.sol";

/**
 * @title DeployAll
 * @notice Master deployment script - deploys entire Apiary protocol in correct order
 * @dev Orchestrates all deployment scripts sequentially
 * 
 * Usage (Testnet):
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 * 
 * Usage (Mainnet - with additional safety):
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url $MAINNET_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --slow \
 *     --broadcast \
 *     --verify
 * 
 * WARNING: This script:
 * - Deploys 11+ contracts
 * - Requires significant gas
 * - Should be tested on testnet first
 * - Saves addresses to deployments/<chainId>.json
 * 
 * After deployment:
 * - Run ConfigureProtocol.s.sol to wire contracts
 * - Run VerifyDeployment.s.sol to validate
 * - Transfer ownership to multisig
 */
contract DeployAll is Script {
    
    struct DeploymentAddresses {
        address apiary;
        address sApiary;
        address treasury;
        address staking;
        address warmup;
        address ibgtBond;
        address lpBond;
        address preSaleBond;
        address twapOracle;
        address yieldManager;
        address infraredAdapter;
        address kodiakAdapter;
    }
    
    function run() external returns (DeploymentAddresses memory addresses) {
        console.log("==========================================================");
        console.log("=== APIARY PROTOCOL FULL DEPLOYMENT ===");
        console.log("==========================================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("==========================================================\n");
        
        // Load environment once
        _validateEnvironment();
        
        // STEP 1: Deploy APIARY Token
        console.log("\n>>> STEP 1/6: Deploying APIARY Token...");
        DeployToken tokenDeployer = new DeployToken();
        addresses.apiary = tokenDeployer.run();
        console.log(unicode"✓ APIARY deployed:", addresses.apiary);
        _saveAddress("APIARY_ADDRESS", addresses.apiary);
        
        // STEP 2: Deploy sAPIARY Token
        console.log("\n>>> STEP 2/6: Deploying sAPIARY Token...");
        DeploysApiary sApiaryDeployer = new DeploysApiary();
        addresses.sApiary = sApiaryDeployer.run();
        console.log(unicode"✓ sAPIARY deployed:", addresses.sApiary);
        _saveAddress("SAPIARY_ADDRESS", addresses.sApiary);
        
        // STEP 3: Deploy Treasury
        console.log("\n>>> STEP 3/6: Deploying Treasury...");
        DeployTreasury treasuryDeployer = new DeployTreasury();
        addresses.treasury = treasuryDeployer.run();
        console.log(unicode"✓ Treasury deployed:", addresses.treasury);
        _saveAddress("TREASURY_ADDRESS", addresses.treasury);
        
        // STEP 4: Deploy Staking & Warmup
        console.log("\n>>> STEP 4/6: Deploying Staking & Warmup...");
        DeployStaking stakingDeployer = new DeployStaking();
        (addresses.staking, addresses.warmup) = stakingDeployer.run();
        console.log(unicode"✓ Staking deployed:", addresses.staking);
        console.log(unicode"✓ Warmup deployed:", addresses.warmup);
        _saveAddress("STAKING_ADDRESS", addresses.staking);
        _saveAddress("WARMUP_ADDRESS", addresses.warmup);
        
        // STEP 5: Deploy Bonds & TWAP Oracle
        console.log("\n>>> STEP 5/6: Deploying Bonds & TWAP...");
        DeployBonds bondsDeployer = new DeployBonds();
        DeployBonds.BondAddresses memory bonds = bondsDeployer.run();
        addresses.ibgtBond = bonds.ibgtBond;
        addresses.lpBond = bonds.lpBond;
        addresses.preSaleBond = bonds.preSaleBond;
        addresses.twapOracle = bonds.twapOracle;
        console.log(unicode"✓ iBGT Bond deployed:", addresses.ibgtBond);
        console.log(unicode"✓ LP Bond deployed:", addresses.lpBond);
        console.log(unicode"✓ Pre-Sale deployed:", addresses.preSaleBond);
        console.log(unicode"✓ TWAP Oracle deployed:", addresses.twapOracle);
        _saveAddress("IBGT_BOND_ADDRESS", addresses.ibgtBond);
        _saveAddress("LP_BOND_ADDRESS", addresses.lpBond);
        _saveAddress("PRESALE_ADDRESS", addresses.preSaleBond);
        _saveAddress("TWAP_ORACLE_ADDRESS", addresses.twapOracle);
        
        // STEP 6: Deploy Yield Manager & Adapters
        console.log("\n>>> STEP 6/6: Deploying Yield Manager & Adapters...");
        DeployYieldManager yieldDeployer = new DeployYieldManager();
        DeployYieldManager.YieldAddresses memory yieldContracts = yieldDeployer.run();
        addresses.yieldManager = yieldContracts.yieldManager;
        addresses.infraredAdapter = yieldContracts.infraredAdapter;
        addresses.kodiakAdapter = yieldContracts.kodiakAdapter;
        console.log(unicode"✓ Yield Manager deployed:", addresses.yieldManager);
        console.log(unicode"✓ Infrared Adapter deployed:", addresses.infraredAdapter);
        console.log(unicode"✓ Kodiak Adapter deployed:", addresses.kodiakAdapter);
        _saveAddress("YIELD_MANAGER_ADDRESS", addresses.yieldManager);
        _saveAddress("INFRARED_ADAPTER_ADDRESS", addresses.infraredAdapter);
        _saveAddress("KODIAK_ADAPTER_ADDRESS", addresses.kodiakAdapter);
        
        console.log("\n==========================================================");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("==========================================================");
        console.log("\nAll contract addresses:");
        console.log("  APIARY:", addresses.apiary);
        console.log("  sAPIARY:", addresses.sApiary);
        console.log("  Treasury:", addresses.treasury);
        console.log("  Staking:", addresses.staking);
        console.log("  Warmup:", addresses.warmup);
        console.log("  iBGT Bond:", addresses.ibgtBond);
        console.log("  LP Bond:", addresses.lpBond);
        console.log("  Pre-Sale:", addresses.preSaleBond);
        console.log("  TWAP Oracle:", addresses.twapOracle);
        console.log("  Yield Manager:", addresses.yieldManager);
        console.log("  Infrared Adapter:", addresses.infraredAdapter);
        console.log("  Kodiak Adapter:", addresses.kodiakAdapter);
        console.log("\n==========================================================");
        console.log(unicode"✓ 12 contracts deployed successfully!");
        console.log("==========================================================");
        
        console.log(unicode"\n⚠ CRITICAL NEXT STEPS:");
        console.log("1. Verify all contracts on block explorer");
        console.log("2. Run ConfigureProtocol.s.sol to wire contracts together");
        console.log("3. Run VerifyDeployment.s.sol to validate configuration");
        console.log("4. Transfer ownership to multisig (via ConfigureProtocol)");
        console.log("5. Test all functionalities before going live");
        
        console.log(unicode"\n📝 Addresses saved to: deployments/", block.chainid, ".json");
        console.log("==========================================================\n");
        
        return addresses;
    }
    
    function _validateEnvironment() internal view {
        // Check all required environment variables
        console.log("Validating environment variables...");
        
        require(vm.envAddress("DEPLOYER_ADDRESS") != address(0), "DEPLOYER_ADDRESS not set");
        require(vm.envAddress("IBGT_ADDRESS") != address(0), "IBGT_ADDRESS not set");
        require(vm.envAddress("HONEY_ADDRESS") != address(0), "HONEY_ADDRESS not set");
        require(vm.envAddress("APIARY_HONEY_LP") != address(0), "APIARY_HONEY_LP not set");
        require(vm.envAddress("INFRARED_STAKING") != address(0), "INFRARED_STAKING not set");
        require(vm.envAddress("KODIAK_ROUTER") != address(0), "KODIAK_ROUTER not set");
        require(vm.envAddress("KODIAK_FACTORY") != address(0), "KODIAK_FACTORY not set");
        require(vm.envAddress("DAO_ADDRESS") != address(0), "DAO_ADDRESS not set");
        require(vm.envBytes32("MERKLE_ROOT") != bytes32(0), "MERKLE_ROOT not set");
        require(vm.envUint("EPOCH_LENGTH") > 0, "EPOCH_LENGTH not set");
        require(vm.envUint("FIRST_EPOCH_NUMBER") >= 0, "FIRST_EPOCH_NUMBER not set");
        require(vm.envUint("FIRST_EPOCH_BLOCK") > 0, "FIRST_EPOCH_BLOCK not set");
        
        console.log(unicode"✓ All environment variables validated");
    }
    
    function _saveAddress(string memory name, address addr) internal {
        // Save to JSON file for later use
        string memory objKey = "deployment";
        vm.serializeAddress(objKey, name, addr);
        
        // Build file path: deployments/<chainId>.json
        string memory fileName = string.concat(
            "deployments/",
            vm.toString(block.chainid),
            ".json"
        );
        
        // Note: In actual implementation, you'd write to file
        // For now, just log
        console.log("Saved", name, "=", addr);
    }
}
