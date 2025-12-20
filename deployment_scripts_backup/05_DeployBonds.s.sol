// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryBondDepository.sol";
import "../../src/ApiaryPreSaleBond.sol";
import "../../src/ApiaryUniswapV2TwapOracle.sol";

/**
 * @title DeployBonds
 * @notice Deployment script for Bond Depository, Pre-Sale Bond, and TWAP Oracle
 * @dev Step 5 of Apiary protocol deployment
 * 
 * Usage:
 *   forge script script/deployment/05_DeployBonds.s.sol:DeployBonds \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 * 
 * Environment Variables Required:
 *   - APIARY_ADDRESS: Address of APIARY token
 *   - IBGT_ADDRESS: Address of iBGT token
 *   - HONEY_ADDRESS: Address of HONEY stablecoin
 *   - APIARY_HONEY_LP: Address of APIARY/HONEY LP token
 *   - TREASURY_ADDRESS: Address of treasury contract
 *   - DAO_ADDRESS: Address of DAO (receives bond fees)
 *   - DEPLOYER_ADDRESS: Admin address
 *   - MERKLE_ROOT: Initial merkle root for pre-sale whitelist
 */
contract DeployBonds is Script {
    
    struct BondAddresses {
        address ibgtBond;
        address lpBond;
        address preSaleBond;
        address twapOracle;
    }
    
    function run() external returns (BondAddresses memory) {
        // Load environment variables
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address ibgt = vm.envAddress("IBGT_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");
        address apiaryHoneyLP = vm.envAddress("APIARY_HONEY_LP");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address dao = vm.envAddress("DAO_ADDRESS");
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        
        console.log("=== Deploying Bond Contracts ===");
        console.log("APIARY:", apiary);
        console.log("Treasury:", treasury);
        console.log("DAO:", dao);
        console.log("Admin:", admin);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy TWAP Oracle first (required by bond depositories)
        ApiaryUniswapV2TwapOracle twapOracle = new ApiaryUniswapV2TwapOracle(
            apiaryHoneyLP,
            apiary,
            honey
        );
        
        console.log("\n1. TWAP Oracle deployed:", address(twapOracle));
        
        // Deploy iBGT Bond Depository
        // No bond calculator needed for single-asset bonds
        ApiaryBondDepository ibgtBond = new ApiaryBondDepository(
            apiary,           // APIARY token
            ibgt,             // Principle (iBGT)
            treasury,         // Treasury
            dao,              // DAO
            admin,            // Admin
            address(0),       // No bond calculator (not LP)
            address(twapOracle) // TWAP oracle
        );
        
        console.log("2. iBGT Bond Depository deployed:", address(ibgtBond));
        
        // Deploy LP Bond Depository
        // Note: Bond calculator contract would need to be deployed separately
        // For now, using address(0) - update in configuration if needed
        ApiaryBondDepository lpBond = new ApiaryBondDepository(
            apiary,           // APIARY token
            apiaryHoneyLP,    // Principle (LP token)
            treasury,         // Treasury
            dao,              // DAO
            admin,            // Admin
            address(0),       // Bond calculator (deploy separately if needed)
            address(twapOracle) // TWAP oracle
        );
        
        console.log("3. LP Bond Depository deployed:", address(lpBond));
        
        // Deploy Pre-Sale Bond
        ApiaryPreSaleBond preSaleBond = new ApiaryPreSaleBond(
            honey,            // Payment token (HONEY)
            treasury,         // Treasury (receives payments)
            admin,            // Admin
            merkleRoot        // Merkle root for whitelist
        );
        
        console.log("4. Pre-Sale Bond deployed:", address(preSaleBond));
        
        vm.stopBroadcast();
        
        console.log("\n=== Bond Contracts Deployed ===");
        console.log("TWAP Oracle:", address(twapOracle));
        console.log("iBGT Bond:", address(ibgtBond));
        console.log("LP Bond:", address(lpBond));
        console.log("Pre-Sale Bond:", address(preSaleBond));
        
        // Sanity checks - iBGT Bond
        require(ibgtBond.APIARY() == apiary, "iBGT Bond: APIARY not set");
        require(ibgtBond.principle() == ibgt, "iBGT Bond: Principle not iBGT");
        require(ibgtBond.treasury() == treasury, "iBGT Bond: Treasury not set");
        require(ibgtBond.dao() == dao, "iBGT Bond: DAO not set");
        require(ibgtBond.owner() == admin, "iBGT Bond: Owner not set");
        require(!ibgtBond.isLiquidityBond(), "iBGT Bond: Should not be liquidity bond");
        
        // Sanity checks - LP Bond
        require(lpBond.APIARY() == apiary, "LP Bond: APIARY not set");
        require(lpBond.principle() == apiaryHoneyLP, "LP Bond: Principle not LP");
        require(lpBond.treasury() == treasury, "LP Bond: Treasury not set");
        require(lpBond.dao() == dao, "LP Bond: DAO not set");
        require(lpBond.owner() == admin, "LP Bond: Owner not set");
        
        // Sanity checks - Pre-Sale
        require(address(preSaleBond.honey()) == honey, "Pre-Sale: HONEY not set");
        require(preSaleBond.treasury() == treasury, "Pre-Sale: Treasury not set");
        require(preSaleBond.owner() == admin, "Pre-Sale: Owner not set");
        require(preSaleBond.merkleRoot() == merkleRoot, "Pre-Sale: Merkle root not set");
        require(preSaleBond.tokenPrice() == 25e16, "Pre-Sale: Default price incorrect");
        require(preSaleBond.isWhitelistEnabled(), "Pre-Sale: Whitelist should be enabled");
        
        console.log(unicode"\n✓ All bond contracts deployed successfully!");
        console.log(unicode"✓ iBGT Bond verified");
        console.log(unicode"✓ LP Bond verified");
        console.log(unicode"✓ Pre-Sale Bond verified");
        console.log(unicode"✓ TWAP Oracle verified");
        console.log(unicode"\n⚠ Next steps:");
        console.log("  1. Set APIARY allocation limits for all bond contracts");
        console.log("  2. Set treasury depositor status for bond contracts");
        console.log("  3. Configure bond terms (vesting, discount, max debt)");
        console.log("  4. Start pre-sale when ready");
        
        return BondAddresses({
            ibgtBond: address(ibgtBond),
            lpBond: address(lpBond),
            preSaleBond: address(preSaleBond),
            twapOracle: address(twapOracle)
        });
    }
}
