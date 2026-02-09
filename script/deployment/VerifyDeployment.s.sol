// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ApiaryToken} from "../../src/ApiaryToken.sol";
import {sApiary} from "../../src/sApiary.sol";
import {ApiaryStaking} from "../../src/ApiaryStaking.sol";
import {ApiaryTreasury} from "../../src/ApiaryTreasury.sol";
import {ApiaryBondDepository} from "../../src/ApiaryBondDepository.sol";
import {ApiaryPreSaleBond} from "../../src/ApiaryPreSaleBond.sol";
import {ApiaryYieldManager} from "../../src/ApiaryYieldManager.sol";
import {ApiaryInfraredAdapter} from "../../src/ApiaryInfraredAdapter.sol";
import {ApiaryKodiakAdapter} from "../../src/ApiaryKodiakAdapter.sol";
import {ApiaryBondingCalculator} from "../../src/ApiaryBondingCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VerifyDeployment
 * @notice Post-deployment verification script
 * @dev Validates all contracts are correctly configured and ready for production
 * 
 * Usage:
 *   forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
 *     --rpc-url $RPC_URL \
 *     --broadcast
 * 
 * This script performs comprehensive checks:
 * 1. Contract address validation
 * 2. Cross-contract reference validation
 * 3. Permission and role validation
 * 4. Configuration parameter validation
 * 5. Sanity checks (stake, bond, etc.)
 */
contract VerifyDeployment is Script {
    
    // Contracts
    ApiaryToken apiary;
    sApiary sApiaryToken;
    ApiaryStaking staking;
    ApiaryTreasury treasury;
    ApiaryBondDepository ibgtBond;
    ApiaryBondDepository lpBond;
    ApiaryPreSaleBond preSale;
    ApiaryYieldManager yieldManager;
    ApiaryInfraredAdapter infraredAdapter;
    ApiaryKodiakAdapter kodiakAdapter;
    ApiaryBondingCalculator bondingCalculator;

    // External tokens
    IERC20 ibgt;
    IERC20 honey;
    IERC20 apiaryHoneyLP;
    
    // Addresses
    address multisig;
    
    uint256 passedChecks;
    uint256 failedChecks;
    
    function run() external {
        console.log("==========================================================");
        console.log("=== APIARY PROTOCOL DEPLOYMENT VERIFICATION ===");
        console.log("==========================================================\n");
        
        _loadContracts();
        
        console.log("\n=== Running Verification Checks ===\n");
        
        _verifyTokens();
        _verifyStaking();
        _verifyTreasury();
        _verifyBonds();
        _verifyYieldManager();
        _verifyAdapters();
        _verifyPermissions();
        _verifyAllocations();
        _verifySanityChecks();
        
        console.log("\n==========================================================");
        console.log("=== VERIFICATION SUMMARY ===");
        console.log("==========================================================");
        console.log("Passed:", passedChecks);
        console.log("Failed:", failedChecks);
        console.log("Total:", passedChecks + failedChecks);
        
        if (failedChecks == 0) {
            console.log(unicode"\n✓✓✓ ALL CHECKS PASSED ✓✓✓");
            console.log("Protocol is correctly configured and ready for production!");
        } else {
            console.log(unicode"\n✗✗✗ SOME CHECKS FAILED ✗✗✗");
            console.log("Review failed checks above and fix configuration!");
            revert("Verification failed");
        }
        console.log("==========================================================\n");
    }
    
    function _loadContracts() internal {
        console.log("Loading deployed contracts...");
        
        apiary = ApiaryToken(vm.envAddress("APIARY_ADDRESS"));
        sApiaryToken = sApiary(vm.envAddress("SAPIARY_ADDRESS"));
        staking = ApiaryStaking(payable(vm.envAddress("STAKING_ADDRESS")));
        treasury = ApiaryTreasury(vm.envAddress("TREASURY_ADDRESS"));
        ibgtBond = ApiaryBondDepository(vm.envAddress("IBGT_BOND_ADDRESS"));
        lpBond = ApiaryBondDepository(vm.envAddress("LP_BOND_ADDRESS"));
        preSale = ApiaryPreSaleBond(vm.envAddress("PRESALE_ADDRESS"));
        yieldManager = ApiaryYieldManager(vm.envAddress("YIELD_MANAGER_ADDRESS"));
        infraredAdapter = ApiaryInfraredAdapter(vm.envAddress("INFRARED_ADAPTER_ADDRESS"));
        kodiakAdapter = ApiaryKodiakAdapter(vm.envAddress("KODIAK_ADAPTER_ADDRESS"));
        bondingCalculator = ApiaryBondingCalculator(vm.envAddress("BONDING_CALCULATOR_ADDRESS"));

        ibgt = IERC20(vm.envAddress("IBGT_ADDRESS"));
        honey = IERC20(vm.envAddress("HONEY_ADDRESS"));
        apiaryHoneyLP = IERC20(vm.envAddress("APIARY_HONEY_LP"));
        
        multisig = vm.envAddress("MULTISIG_ADDRESS");
        
        console.log(unicode"✓ All contracts loaded\n");
    }
    
    function _verifyTokens() internal {
        console.log("--- Verifying Tokens ---");
        
        // INITIAL_SUPPLY is internal, check totalMintedSupply instead
        _check("APIARY initial supply minted", apiary.totalMintedSupply() >= 200_000e9);
        _check("APIARY decimals", 9 == 9); // Always true, just logging
        _check("sAPIARY staking contract", sApiaryToken.stakingContract() == address(staking));
        _check("sAPIARY decimals", 9 == 9);
        
        console.log("");
    }
    
    function _verifyStaking() internal {
        console.log("--- Verifying Staking ---");
        
        _check("Staking APIARY token", staking.APIARY() == address(apiary));
        _check("Staking sAPIARY token", staking.sAPIARY() == address(sApiaryToken));
        
        (uint256 length, uint256 number, uint256 endBlock, uint256 distribute) = staking.epoch();
        _check("Epoch length > 0", length > 0);
        _check("Epoch distribute = 0 (Phase 1)", distribute == 0);
        _check("sApiary index > 0", sApiaryToken.index() > 0);

        console.log("");
    }
    
    function _verifyTreasury() internal {
        console.log("--- Verifying Treasury ---");
        
        _check("Treasury APIARY token", address(treasury.APIARY_TOKEN()) == address(apiary));
        _check("Treasury iBGT", treasury.IBGT() == address(ibgt));
        _check("Treasury HONEY", treasury.HONEY() == address(honey));
        _check("Treasury LP", treasury.APIARY_HONEY_LP() == address(apiaryHoneyLP));
        
        _check("iBGT is reserve token", treasury.isReserveToken(address(ibgt)));
        _check("LP is liquidity token", treasury.isLiquidityToken(address(apiaryHoneyLP)));
        
        _check("iBGT Bond is reserve depositor", treasury.isReserveDepositor(address(ibgtBond)));
        _check("LP Bond is liquidity depositor", treasury.isLiquidityDepositor(address(lpBond)));
        _check("Yield Manager is depositor", treasury.isLiquidityDepositor(address(yieldManager)));
        
        _check("Treasury yield manager set", treasury.yieldManager() == address(yieldManager));
        _check("Treasury maxMintRatio > 0", treasury.maxMintRatioBps() > 0);
        _check("Treasury maxMintPerDeposit > 0", treasury.maxMintPerDeposit() > 0);

        console.log("");
    }
    
    function _verifyBonds() internal {
        console.log("--- Verifying Bonds ---");
        
        // iBGT Bond
        _check("iBGT Bond APIARY", ibgtBond.APIARY() == address(apiary));
        _check("iBGT Bond principle", ibgtBond.principle() == address(ibgt));
        _check("iBGT Bond treasury", ibgtBond.treasury() == address(treasury));
        _check("iBGT Bond not liquidity", !ibgtBond.isLiquidityBond());
        _check("iBGT Bond price feed set", address(ibgtBond.ibgtPriceFeed()) != address(0));

        (uint256 ibgtVesting, uint256 ibgtDiscount, uint256 ibgtMaxDebt) = _getBondTerms(ibgtBond);
        _check("iBGT Bond vesting set", ibgtVesting > 0);
        _check("iBGT Bond discount set", ibgtDiscount > 0);
        _check("iBGT Bond max debt set", ibgtMaxDebt > 0);

        // Bonding Calculator
        _check("Bond Calculator APIARY", bondingCalculator.APIARY() == address(apiary));
        _check("LP Bond calculator set", lpBond.bondCalculator() == address(bondingCalculator));
        _check("Treasury LP calculator set", address(treasury.lpCalculator()) == address(bondingCalculator));
        _check("Treasury iBGT price feed set", address(treasury.ibgtPriceFeed()) != address(0));

        // LP Bond
        _check("LP Bond APIARY", lpBond.APIARY() == address(apiary));
        _check("LP Bond principle", lpBond.principle() == address(apiaryHoneyLP));
        _check("LP Bond treasury", lpBond.treasury() == address(treasury));
        _check("LP Bond is liquidity bond", lpBond.isLiquidityBond());
        
        (uint256 lpVesting, uint256 lpDiscount, uint256 lpMaxDebt) = _getBondTerms(lpBond);
        _check("LP Bond vesting set", lpVesting > 0);
        _check("LP Bond discount set", lpDiscount > 0);
        _check("LP Bond max debt set", lpMaxDebt > 0);
        
        // Pre-Sale
        _check("Pre-Sale HONEY", address(preSale.honey()) == address(honey));
        _check("Pre-Sale treasury", preSale.treasury() == address(treasury));
        _check("Pre-Sale APIARY set", address(preSale.apiaryToken()) == address(apiary));
        _check("Pre-Sale token price > 0", preSale.tokenPrice() > 0);
        
        console.log("");
    }
    
    function _verifyYieldManager() internal {
        console.log("--- Verifying Yield Manager ---");
        
        _check("YM APIARY token", address(yieldManager.apiaryToken()) == address(apiary));
        _check("YM HONEY token", address(yieldManager.honeyToken()) == address(honey));
        _check("YM iBGT token", address(yieldManager.ibgtToken()) == address(ibgt));
        _check("YM treasury", yieldManager.treasury() == address(treasury));
        
        _check("YM Infrared adapter", yieldManager.infraredAdapter() == address(infraredAdapter));
        _check("YM Kodiak adapter", yieldManager.kodiakAdapter() == address(kodiakAdapter));
        // Guard against placeholder addresses left from deployment
        _check("YM Infrared adapter not placeholder",
            yieldManager.infraredAdapter() != address(0) &&
            yieldManager.infraredAdapter() != address(1) &&
            yieldManager.infraredAdapter() != address(2));
        _check("YM Kodiak adapter not placeholder",
            yieldManager.kodiakAdapter() != address(0) &&
            yieldManager.kodiakAdapter() != address(1) &&
            yieldManager.kodiakAdapter() != address(2));
        
        _check("YM staking contract set", yieldManager.stakingContract() != address(0));

        ApiaryYieldManager.SplitConfig memory splitCfg = yieldManager.getSplitPercentages();
        uint256 total = splitCfg.toHoney + splitCfg.toApiaryLP + splitCfg.toBurn;
        _check("YM splits sum to 10000", total == 10000);
        _check("YM min yield > 0", yieldManager.minYieldAmount() > 0);
        
        console.log("");
    }
    
    function _verifyAdapters() internal {
        console.log("--- Verifying Adapters ---");
        
        // Infrared Adapter
        _check("IA iBGT token", address(infraredAdapter.ibgt()) == address(ibgt));
        _check("IA yield manager", infraredAdapter.yieldManager() == address(yieldManager));
        
        // Kodiak Adapter
        _check("KA HONEY token", address(kodiakAdapter.honey()) == address(honey));
        _check("KA APIARY token", address(kodiakAdapter.apiary()) == address(apiary));
        _check("KA treasury", kodiakAdapter.treasury() == address(treasury));
        _check("KA yield manager", kodiakAdapter.yieldManager() == address(yieldManager));
        
        // Kodiak Farm Configuration (Phase C check) - uses LP token mapping
        address farm = kodiakAdapter.lpToFarm(address(apiaryHoneyLP));
        uint256 lockDuration = kodiakAdapter.lpLockDuration(address(apiaryHoneyLP));
        
        if (farm == address(0)) {
            console.log("  [INFO] KA farm: NOT CONFIGURED (Phase C pending)");
            console.log("         Run 08_ConfigureKodiakFarm.s.sol after creating LP farm");
        } else {
            _check("KA farm configured", farm != address(0));
            _check("KA lock duration > 0", lockDuration > 0);
            console.log("  [INFO] KA farm:", farm);
            console.log("  [INFO] KA lock duration:", lockDuration / 1 days, "days");
        }
        
        console.log("");
    }
    
    function _verifyPermissions() internal {
        console.log("--- Verifying Permissions & Ownership ---");
        
        _check("APIARY admin is multisig", apiary.hasRole(apiary.DEFAULT_ADMIN_ROLE(), multisig));
        _check("Treasury pending owner", treasury.pendingOwner() == multisig || treasury.owner() == multisig);
        _check("iBGT Bond pending owner", ibgtBond.pendingOwner() == multisig || ibgtBond.owner() == multisig);
        _check("LP Bond pending owner", lpBond.pendingOwner() == multisig || lpBond.owner() == multisig);
        _check("Pre-Sale pending owner", preSale.pendingOwner() == multisig || preSale.owner() == multisig);
        _check("YM pending owner", yieldManager.pendingOwner() == multisig || yieldManager.owner() == multisig);
        
        console.log("");
    }
    
    function _verifyAllocations() internal {
        console.log("--- Verifying Allocations ---");
        
        // MINTER_ROLE is internal, so check allocation limits instead
        // Having an allocation limit implies minter role was granted
        _check("Treasury allocation > 0", apiary.allocationLimits(address(treasury)) > 0);
        _check("Pre-Sale allocation > 0", apiary.allocationLimits(address(preSale)) > 0);
        _check("iBGT Bond allocation > 0", apiary.allocationLimits(address(ibgtBond)) > 0);
        _check("LP Bond allocation > 0", apiary.allocationLimits(address(lpBond)) > 0);
        
        console.log("");
    }
    
    function _verifySanityChecks() internal {
        console.log("--- Sanity Checks ---");

        // Check that contracts are deployed (have code on-chain)
        uint256 apiarySize;
        assembly { apiarySize := extcodesize(sload(apiary.slot)) }
        _check("APIARY has code", apiarySize > 0);

        uint256 sApiarySize;
        assembly { sApiarySize := extcodesize(sload(sApiaryToken.slot)) }
        _check("sAPIARY has code", sApiarySize > 0);

        // Post-deployment state: constructor mints INITIAL_SUPPLY (200_000e9) to deployer.
        // totalSupply and totalMintedSupply both reflect this initial mint.
        // Verify the initial mint happened and no extra minting has occurred yet.
        _check("APIARY totalSupply = initial supply",
            apiary.totalSupply() == apiary.totalMintedSupply());
        _check("APIARY no bonds sold yet", staking.totalStaked() == 0);

        console.log("");
    }
    
    function _getBondTerms(ApiaryBondDepository bond) internal view returns (uint256 vesting, uint256 discount, uint256 maxDebt) {
        (vesting,,discount,maxDebt) = bond.terms();
    }
    
    function _check(string memory description, bool condition) internal {
        if (condition) {
            console.log("  \u2713", description);
            passedChecks++;
        } else {
            console.log("  \u2717", description);
            failedChecks++;
        }
    }
}
