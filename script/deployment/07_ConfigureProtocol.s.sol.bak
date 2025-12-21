// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryToken.sol";
import "../../src/sApiary.sol";
import "../../src/ApiaryStaking.sol";
import "../../src/ApiaryStakingWarmup.sol";
import "../../src/ApiaryTreasury.sol";
import "../../src/ApiaryBondDepository.sol";
import "../../src/ApiaryPreSaleBond.sol";
import "../../src/ApiaryYieldManager.sol";
import "../../src/ApiaryInfraredAdapter.sol";
import "../../src/ApiaryKodiakAdapter.sol";

/**
 * @title ConfigureProtocol
 * @notice Configuration script to wire all Apiary protocol contracts together
 * @dev Step 7 of Apiary protocol deployment - Run AFTER all contracts are deployed
 * 
 * Usage:
 *   forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 * 
 * This script performs all cross-contract configurations:
 * 1. Initialize sAPIARY with staking contract
 * 2. Set warmup contract in staking
 * 3. Set APIARY minting allocations
 * 4. Configure treasury depositors
 * 5. Set yield manager in treasury
 * 6. Update yield manager adapters
 * 7. Configure bond terms
 * 8. Transfer ownership to multisig
 */
contract ConfigureProtocol is Script {
    
    // Allocation amounts (in APIARY with 9 decimals)
    uint256 constant TREASURY_ALLOCATION = 40_000e9;      // 20% - Treasury
    uint256 constant PRESALE_ALLOCATION = 10_000e9;       // 5% - Pre-Sale
    uint256 constant IBGT_BOND_ALLOCATION = 30_000e9;     // 15% - iBGT Bonds
    uint256 constant LP_BOND_ALLOCATION = 30_000e9;       // 15% - LP Bonds
    
    // Bond terms defaults
    uint256 constant DEFAULT_VESTING_TERM = 129_600;      // ~36 hours at 1s blocks
    uint256 constant DEFAULT_DISCOUNT_RATE = 500;         // 5% discount
    uint256 constant DEFAULT_MAX_DEBT = 50_000e9;         // 50k APIARY max
    
    function run() external {
        // Load all deployed addresses
        address apiaryAddr = vm.envAddress("APIARY_ADDRESS");
        address sApiaryAddr = vm.envAddress("SAPIARY_ADDRESS");
        address stakingAddr = vm.envAddress("STAKING_ADDRESS");
        address warmupAddr = vm.envAddress("WARMUP_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address ibgtBondAddr = vm.envAddress("IBGT_BOND_ADDRESS");
        address lpBondAddr = vm.envAddress("LP_BOND_ADDRESS");
        address preSaleAddr = vm.envAddress("PRESALE_ADDRESS");
        address yieldManagerAddr = vm.envAddress("YIELD_MANAGER_ADDRESS");
        address infraredAdapterAddr = vm.envAddress("INFRARED_ADAPTER_ADDRESS");
        address kodiakAdapterAddr = vm.envAddress("KODIAK_ADAPTER_ADDRESS");
        address multisigAddr = vm.envAddress("MULTISIG_ADDRESS");
        
        console.log("=== Configuring Apiary Protocol ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Multisig:", multisigAddr);
        
        // Load contracts
        ApiaryToken apiary = ApiaryToken(apiaryAddr);
        sApiary sApiaryToken = sApiary(sApiaryAddr);
        ApiaryStaking staking = ApiaryStaking(stakingAddr);
        ApiaryStakingWarmup warmup = ApiaryStakingWarmup(warmupAddr);
        ApiaryTreasury treasury = ApiaryTreasury(treasuryAddr);
        ApiaryBondDepository ibgtBond = ApiaryBondDepository(ibgtBondAddr);
        ApiaryBondDepository lpBond = ApiaryBondDepository(lpBondAddr);
        ApiaryPreSaleBond preSale = ApiaryPreSaleBond(preSaleAddr);
        ApiaryYieldManager yieldManager = ApiaryYieldManager(yieldManagerAddr);
        ApiaryInfraredAdapter infraredAdapter = ApiaryInfraredAdapter(infraredAdapterAddr);
        ApiaryKodiakAdapter kodiakAdapter = ApiaryKodiakAdapter(kodiakAdapterAddr);
        
        vm.startBroadcast();
        
        console.log("\n=== Step 1: Initialize sAPIARY ===");
        sApiaryToken.initialize(stakingAddr);
        console.log(unicode"✓ sAPIARY initialized with staking contract");
        
        console.log("\n=== Step 2: Configure Staking ===");
        staking.setWarmupContract(warmupAddr);
        console.log(unicode"✓ Warmup contract set in staking");
        
        console.log("\n=== Step 3: Set APIARY Minting Allocations ===");
        apiary.setAllocationLimit(treasuryAddr, TREASURY_ALLOCATION);
        console.log(unicode"✓ Treasury allocation:", TREASURY_ALLOCATION / 1e9, "APIARY");
        
        apiary.setAllocationLimit(preSaleAddr, PRESALE_ALLOCATION);
        console.log(unicode"✓ Pre-Sale allocation:", PRESALE_ALLOCATION / 1e9, "APIARY");
        
        apiary.setAllocationLimit(ibgtBondAddr, IBGT_BOND_ALLOCATION);
        console.log(unicode"✓ iBGT Bond allocation:", IBGT_BOND_ALLOCATION / 1e9, "APIARY");
        
        apiary.setAllocationLimit(lpBondAddr, LP_BOND_ALLOCATION);
        console.log(unicode"✓ LP Bond allocation:", LP_BOND_ALLOCATION / 1e9, "APIARY");
        
        console.log("\n=== Step 4: Configure Treasury Depositors ===");
        treasury.setReserveDepositor(ibgtBondAddr, true);
        console.log(unicode"✓ iBGT Bond set as reserve depositor");
        
        treasury.setLiquidityDepositor(lpBondAddr, true);
        console.log(unicode"✓ LP Bond set as liquidity depositor");
        
        treasury.setLiquidityDepositor(yieldManagerAddr, true);
        console.log(unicode"✓ Yield Manager set as liquidity depositor");
        
        console.log("\n=== Step 5: Set Yield Manager in Treasury ===");
        treasury.setYieldManager(yieldManagerAddr);
        console.log(unicode"✓ Yield Manager connected to Treasury");
        
        console.log("\n=== Step 6: Update Yield Manager Adapters ===");
        yieldManager.setInfraredAdapter(infraredAdapterAddr);
        console.log(unicode"✓ Infrared Adapter set in Yield Manager");
        
        yieldManager.setKodiakAdapter(kodiakAdapterAddr);
        console.log(unicode"✓ Kodiak Adapter set in Yield Manager");
        
        console.log("\n=== Step 7: Configure Bond Terms ===");
        // iBGT Bond
        ibgtBond.setBondTerms(
            0, // vesting term
            DEFAULT_VESTING_TERM
        );
        ibgtBond.setBondTerms(
            1, // discount rate
            DEFAULT_DISCOUNT_RATE
        );
        ibgtBond.setBondTerms(
            2, // max debt
            DEFAULT_MAX_DEBT
        );
        console.log(unicode"✓ iBGT Bond terms configured");
        console.log("  Vesting:", DEFAULT_VESTING_TERM, "blocks");
        console.log("  Discount:", DEFAULT_DISCOUNT_RATE / 100, "%");
        console.log("  Max Debt:", DEFAULT_MAX_DEBT / 1e9, "APIARY");
        
        // LP Bond
        lpBond.setBondTerms(
            0, // vesting term
            DEFAULT_VESTING_TERM
        );
        lpBond.setBondTerms(
            1, // discount rate
            DEFAULT_DISCOUNT_RATE
        );
        lpBond.setBondTerms(
            2, // max debt
            DEFAULT_MAX_DEBT
        );
        console.log(unicode"✓ LP Bond terms configured");
        
        console.log("\n=== Step 8: Set Pre-Sale APIARY Token ===");
        preSale.setApiaryToken(apiaryAddr);
        console.log(unicode"✓ APIARY token set in Pre-Sale");
        
        console.log("\n=== Step 9: Exclude Protocol Contracts from Fees (if applicable) ===");
        // Note: If APIARY has fee mechanisms, exclude protocol contracts
        // This depends on your token implementation
        console.log(unicode"⚠ Manual step: Exclude protocol contracts from fees if needed");
        
        console.log("\n=== Step 10: Transfer Ownership to Multisig ===");
        console.log(unicode"⚠ CRITICAL: About to transfer ownership to:", multisigAddr);
        console.log("   Deployer will lose admin access after this step!");
        
        // Transfer ownership of all contracts to multisig
        apiary.grantRole(apiary.DEFAULT_ADMIN_ROLE(), multisigAddr);
        apiary.renounceRole(apiary.DEFAULT_ADMIN_ROLE(), msg.sender);
        console.log(unicode"✓ APIARY admin role transferred");
        
        treasury.transferOwnership(multisigAddr);
        console.log(unicode"✓ Treasury ownership transferred");
        
        ibgtBond.transferOwnership(multisigAddr);
        console.log(unicode"✓ iBGT Bond ownership transferred");
        
        lpBond.transferOwnership(multisigAddr);
        console.log(unicode"✓ LP Bond ownership transferred");
        
        preSale.transferOwnership(multisigAddr);
        console.log(unicode"✓ Pre-Sale ownership transferred");
        
        yieldManager.transferOwnership(multisigAddr);
        console.log(unicode"✓ Yield Manager ownership transferred");
        
        infraredAdapter.transferOwnership(multisigAddr);
        console.log(unicode"✓ Infrared Adapter ownership transferred");
        
        kodiakAdapter.transferOwnership(multisigAddr);
        console.log(unicode"✓ Kodiak Adapter ownership transferred");
        
        vm.stopBroadcast();
        
        console.log("\n=== Configuration Complete ===");
        console.log(unicode"✓ All contracts configured");
        console.log(unicode"✓ All ownerships transferred to multisig");
        console.log(unicode"\n⚠ IMPORTANT: Multisig must accept ownership for Ownable2Step contracts:");
        console.log("  - Treasury");
        console.log("  - iBGT Bond");
        console.log("  - LP Bond");
        console.log("  - Pre-Sale");
        console.log("  - Yield Manager");
        console.log("  - Infrared Adapter");
        console.log("  - Kodiak Adapter");
        console.log(unicode"\n✓ Protocol ready for testing!");
        console.log("  Next: Run VerifyDeployment.s.sol to validate configuration");
    }
}
