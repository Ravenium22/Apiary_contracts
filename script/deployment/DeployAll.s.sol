// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ApiaryToken} from "../../src/ApiaryToken.sol";
import {sApiary} from "../../src/sApiary.sol";
import {ApiaryTreasury} from "../../src/ApiaryTreasury.sol";
import {ApiaryStaking} from "../../src/ApiaryStaking.sol";
import {ApiaryBondDepository} from "../../src/ApiaryBondDepository.sol";
import {ApiaryPreSaleBond} from "../../src/ApiaryPreSaleBond.sol";
import {ApiaryUniswapV2TwapOracle} from "../../src/ApiaryUniswapV2TwapOracle.sol";
import {ApiaryYieldManager} from "../../src/ApiaryYieldManager.sol";
import {ApiaryInfraredAdapter} from "../../src/ApiaryInfraredAdapter.sol";
import {ApiaryKodiakAdapter} from "../../src/ApiaryKodiakAdapter.sol";

/**
 * @title DeployAll
 * @notice Complete deployment script for Apiary Protocol on Berachain Bepolia testnet
 * @dev Deploys all contracts in sequence with proper linking
 * 
 * IMPORTANT: This script deploys core contracts first. The TWAP Oracle and Bond contracts
 * that depend on LP pair will need an actual LP pair address. You can either:
 * 1. Deploy in phases: First deploy core, create LP, then deploy bonds
 * 2. Use an existing LP pair address via LP_PAIR_ADDRESS env var
 * 
 * Usage:
 *   # Dry run (simulation)
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url https://bepolia.rpc.berachain.com \
 *     --private-key $PRIVATE_KEY
 *
 *   # With broadcast (actual deployment)
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url https://bepolia.rpc.berachain.com \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 *   # With verification
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url https://bepolia.rpc.berachain.com \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BERASCAN_API_KEY
 * 
 * Required Environment Variables (set in .env):
 *   - PRIVATE_KEY: Deployer private key
 *   - BERASCAN_API_KEY: For contract verification
 *   
 * Optional Environment Variables:
 *   - LP_PAIR_ADDRESS: Existing APIARY/HONEY LP pair (if created beforehand)
 *   
 * The script uses TESTNET addresses for Bepolia
 */
contract DeployAll is Script {
    
    // ============ BEPOLIA TESTNET ADDRESSES ============
    // Update these if deploying to mainnet
    address constant IBGT_ADDRESS = 0x46eFC86F0D7455F135CC9df501673739d513E982; // iBGT on Bepolia
    address constant HONEY_ADDRESS = 0x7EeCA4205fF31f947EdBd49195a7A88E6A91161B; // HONEY on Bepolia
    address constant INFRARED_STAKING = 0x75F3Be06b02E235E93Aa599F2fA6e44ed67B6C47; // Infrared on Bepolia
    address constant KODIAK_ROUTER = 0x496e305C03909ae382974cAcA4c580E1BF32afBE; // Kodiak Router on Bepolia
    address constant KODIAK_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da; // Kodiak Factory on Bepolia
    
    // Epoch configuration for testnet (faster epochs for testing)
    uint256 constant EPOCH_LENGTH = 600; // 10 minutes in blocks (Berachain ~1s blocks)
    uint256 constant FIRST_EPOCH_NUMBER = 0;
    
    // Default merkle root for pre-sale (placeholder - must be updated before starting pre-sale)
    // This is a keccak256 hash of "placeholder" to satisfy the non-zero requirement
    bytes32 constant DEFAULT_MERKLE_ROOT = keccak256("APIARY_PRESALE_PLACEHOLDER");
    
    // ============ DEPLOYED ADDRESSES ============
    struct DeployedAddresses {
        address apiary;
        address sApiary;
        address treasury;
        address staking;
        address ibgtBond;
        address lpBond;
        address preSaleBond;
        address twapOracle;
        address yieldManager;
        address infraredAdapter;
        address kodiakAdapter;
        address apiaryHoneyLP;
    }
    
    function run() external returns (DeployedAddresses memory deployed) {
        // Get deployer address from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Try to get LP pair address from env, or use placeholder
        address lpPairAddress = _tryGetLPPairAddress();
        bool hasRealLP = lpPairAddress != address(0) && lpPairAddress.code.length > 0;
        
        console.log("==============================================");
        console.log("  APIARY PROTOCOL - FULL DEPLOYMENT");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        if (!hasRealLP) {
            console.log("");
            console.log("WARNING: No LP pair found. TWAP Oracle and Bond contracts");
            console.log("         will be skipped. Deploy them after creating LP pool.");
        }
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ STEP 1: Deploy APIARY Token ============
        console.log("STEP 1: Deploying APIARY Token...");
        ApiaryToken apiary = new ApiaryToken(deployer);
        deployed.apiary = address(apiary);
        console.log("  APIARY Token:", deployed.apiary);
        
        // ============ STEP 2: Deploy sAPIARY Token ============
        console.log("STEP 2: Deploying sAPIARY Token...");
        sApiary sApiaryToken = new sApiary(deployer);
        deployed.sApiary = address(sApiaryToken);
        console.log("  sAPIARY Token:", deployed.sApiary);
        
        // ============ STEP 3: Set LP address ============
        console.log("STEP 3: Setting LP address...");
        if (hasRealLP) {
            deployed.apiaryHoneyLP = lpPairAddress;
            console.log("  Using existing LP pair:", deployed.apiaryHoneyLP);
        } else {
            // Use a placeholder - treasury will need to be updated later
            deployed.apiaryHoneyLP = address(0xdead);
            console.log("  Using placeholder LP (update later):", deployed.apiaryHoneyLP);
        }
        
        // ============ STEP 4: Deploy Treasury ============
        console.log("STEP 4: Deploying Treasury...");
        ApiaryTreasury treasury = new ApiaryTreasury(
            deployer,
            deployed.apiary,
            IBGT_ADDRESS,
            HONEY_ADDRESS,
            deployed.apiaryHoneyLP
        );
        deployed.treasury = address(treasury);
        console.log("  Treasury:", deployed.treasury);
        
        // ============ STEP 5: Deploy Staking ============
        console.log("STEP 5: Deploying Staking...");
        uint256 firstEpochBlock = block.number + EPOCH_LENGTH;
        ApiaryStaking staking = new ApiaryStaking(
            deployed.apiary,
            deployed.sApiary,
            EPOCH_LENGTH,
            FIRST_EPOCH_NUMBER,
            firstEpochBlock,
            deployer
        );
        deployed.staking = address(staking);
        console.log("  Staking:", deployed.staking);
        
        // ============ STEP 6: Initialize sAPIARY with Staking ============
        console.log("STEP 6: Initializing sAPIARY with Staking contract...");
        sApiaryToken.initialize(deployed.staking);
        console.log("  sAPIARY initialized with staking");
        
        // ============ STEP 7: Deploy TWAP Oracle (only if LP exists) ============
        if (hasRealLP) {
            console.log("STEP 7: Deploying TWAP Oracle...");
            ApiaryUniswapV2TwapOracle twapOracle = new ApiaryUniswapV2TwapOracle(
                deployed.apiaryHoneyLP
            );
            deployed.twapOracle = address(twapOracle);
            console.log("  TWAP Oracle:", deployed.twapOracle);
        } else {
            console.log("STEP 7: Skipping TWAP Oracle (no LP pair)...");
            deployed.twapOracle = address(0);
        }
        
        // ============ STEP 8: Deploy Bond Contracts ============
        console.log("STEP 8: Deploying Bond Contracts...");
        
        if (hasRealLP) {
            // iBGT Bond
            ApiaryBondDepository ibgtBond = new ApiaryBondDepository(
                deployed.apiary,
                IBGT_ADDRESS,
                deployed.treasury,
                deployer,
                address(0), // No bond calculator for reserve token
                deployed.twapOracle
            );
            deployed.ibgtBond = address(ibgtBond);
            console.log("  iBGT Bond:", deployed.ibgtBond);
            
            // LP Bond
            ApiaryBondDepository lpBond = new ApiaryBondDepository(
                deployed.apiary,
                deployed.apiaryHoneyLP,
                deployed.treasury,
                deployer,
                address(0), // Bond calculator (deploy separately if needed)
                deployed.twapOracle
            );
            deployed.lpBond = address(lpBond);
            console.log("  LP Bond:", deployed.lpBond);
        } else {
            console.log("  Skipping iBGT Bond and LP Bond (no LP pair)...");
            deployed.ibgtBond = address(0);
            deployed.lpBond = address(0);
        }
        
        // Pre-Sale Bond (doesn't need LP pair)
        ApiaryPreSaleBond preSaleBond = new ApiaryPreSaleBond(
            HONEY_ADDRESS,
            deployed.treasury,
            deployer,
            DEFAULT_MERKLE_ROOT
        );
        deployed.preSaleBond = address(preSaleBond);
        console.log("  Pre-Sale Bond:", deployed.preSaleBond);
        
        // ============ STEP 9: Deploy Yield Manager & Adapters ============
        console.log("STEP 9: Deploying Yield Manager & Adapters...");
        
        // Deploy Yield Manager with placeholder adapters
        ApiaryYieldManager yieldManager = new ApiaryYieldManager(
            deployed.apiary,
            HONEY_ADDRESS,
            IBGT_ADDRESS,
            deployed.treasury,
            address(1), // Placeholder
            address(2), // Placeholder
            deployer
        );
        deployed.yieldManager = address(yieldManager);
        console.log("  Yield Manager:", deployed.yieldManager);
        
        // Deploy Infrared Adapter
        ApiaryInfraredAdapter infraredAdapter = new ApiaryInfraredAdapter(
            INFRARED_STAKING,
            IBGT_ADDRESS,
            deployed.yieldManager,
            deployer
        );
        deployed.infraredAdapter = address(infraredAdapter);
        console.log("  Infrared Adapter:", deployed.infraredAdapter);
        
        // Deploy Kodiak Adapter
        ApiaryKodiakAdapter kodiakAdapter = new ApiaryKodiakAdapter(
            KODIAK_ROUTER,
            KODIAK_FACTORY,
            HONEY_ADDRESS,
            deployed.apiary,
            deployed.treasury,
            deployed.yieldManager,
            deployer
        );
        deployed.kodiakAdapter = address(kodiakAdapter);
        console.log("  Kodiak Adapter:", deployed.kodiakAdapter);
        
        // ============ STEP 10: Configure Permissions ============
        console.log("STEP 10: Configuring permissions...");
        
        // Grant APIARY minting permissions to treasury
        apiary.setAllocationLimit(deployed.treasury, 1_000_000_000 * 1e9); // 1B APIARY
        console.log("  Treasury mint allocation: 1B APIARY");
        
        // Grant treasury depositor status to bond contracts
        if (deployed.ibgtBond != address(0)) {
            treasury.setReserveDepositor(deployed.ibgtBond, true);
        }
        if (deployed.lpBond != address(0)) {
            treasury.setReserveDepositor(deployed.lpBond, true);
        }
        treasury.setReserveDepositor(deployed.preSaleBond, true);
        console.log("  Bond contracts set as reserve depositors");
        
        // Set yield manager in treasury
        treasury.setYieldManager(deployed.yieldManager);
        console.log("  Yield manager configured in treasury");
        
        vm.stopBroadcast();
        
        // ============ DEPLOYMENT SUMMARY ============
        console.log("");
        console.log("==============================================");
        console.log("  DEPLOYMENT COMPLETE!");
        console.log("==============================================");
        console.log("");
        console.log("Core Tokens:");
        console.log("  APIARY:       ", deployed.apiary);
        console.log("  sAPIARY:      ", deployed.sApiary);
        console.log("");
        console.log("Core Contracts:");
        console.log("  Treasury:     ", deployed.treasury);
        console.log("  Staking:      ", deployed.staking);
        console.log("");
        console.log("Bond Contracts:");
        console.log("  iBGT Bond:    ", deployed.ibgtBond);
        console.log("  LP Bond:      ", deployed.lpBond);
        console.log("  Pre-Sale:     ", deployed.preSaleBond);
        console.log("  TWAP Oracle:  ", deployed.twapOracle);
        console.log("");
        console.log("Yield Contracts:");
        console.log("  Yield Manager:", deployed.yieldManager);
        console.log("  Infrared:     ", deployed.infraredAdapter);
        console.log("  Kodiak:       ", deployed.kodiakAdapter);
        console.log("");
        console.log("External Addresses Used:");
        console.log("  iBGT:         ", IBGT_ADDRESS);
        console.log("  HONEY:        ", HONEY_ADDRESS);
        console.log("  APIARY/HONEY LP:", deployed.apiaryHoneyLP);
        console.log("");
        console.log("==============================================");
        console.log("  NEXT STEPS:");
        console.log("==============================================");
        if (deployed.twapOracle == address(0)) {
            console.log("1. Create APIARY/HONEY LP pool on Kodiak");
            console.log("2. Add initial liquidity to the pool");
            console.log("3. Run 05_DeployBonds.s.sol with LP address");
            console.log("4. Update LP address in treasury");
        }
        console.log("5. Configure bond terms (vesting, discount, etc.)");
        console.log("6. Start pre-sale when ready");
        console.log("7. Create Kodiak farm for LP rewards");
        console.log("==============================================");
        
        return deployed;
    }
    
    /**
     * @notice Tries to get LP pair address from environment variable
     * @dev Returns address(0) if not set or if the address has no code
     */
    function _tryGetLPPairAddress() internal view returns (address) {
        try vm.envAddress("LP_PAIR_ADDRESS") returns (address lpAddr) {
            return lpAddr;
        } catch {
            return address(0);
        }
    }
}
