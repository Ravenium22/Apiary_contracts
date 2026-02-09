// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ApiaryToken} from "../../src/ApiaryToken.sol";
import {sApiary} from "../../src/sApiary.sol";
import {ApiaryTreasury} from "../../src/ApiaryTreasury.sol";
import {ApiaryStaking} from "../../src/ApiaryStaking.sol";
import {ApiaryBondDepository} from "../../src/ApiaryBondDepository.sol";
import {ApiaryPreSaleBond} from "../../src/ApiaryPreSaleBond.sol";
import {ApiaryYieldManager} from "../../src/ApiaryYieldManager.sol";
import {ApiaryInfraredAdapter} from "../../src/ApiaryInfraredAdapter.sol";
import {ApiaryKodiakAdapter} from "../../src/ApiaryKodiakAdapter.sol";

/**
 * @title AcceptOwnership
 * @notice Post-deploy script for multisig to accept ownership of all contracts
 * @dev Run this AFTER DeployAll.s.sol has initiated ownership transfers.
 *
 * Two modes:
 *   1. MULTISIG mode (--private-key = multisig signer):
 *      Calls acceptOwnership() on all Ownable2Step contracts.
 *
 *   2. DEPLOYER mode (--private-key = deployer):
 *      Renounces DEFAULT_ADMIN_ROLE on ApiaryToken after multisig has accepted.
 *
 * Usage:
 *   # Step 1: Multisig accepts ownership
 *   forge script script/deployment/AcceptOwnership.s.sol:AcceptOwnershipMultisig \
 *     --rpc-url $BERACHAIN_RPC_URL --broadcast
 *
 *   # Step 2: Deployer renounces admin role
 *   forge script script/deployment/AcceptOwnership.s.sol:RenounceDeployerAdmin \
 *     --rpc-url $BERACHAIN_RPC_URL --broadcast
 */

/// @notice Multisig calls acceptOwnership() on all Ownable2Step contracts
contract AcceptOwnershipMultisig is Script {
    function run() external {
        // Load deployed contract addresses from env
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address staking = vm.envAddress("STAKING_ADDRESS");
        address sApiaryAddr = vm.envAddress("SAPIARY_ADDRESS");
        address preSale = vm.envAddress("PRESALE_ADDRESS");
        address yieldManager = vm.envAddress("YIELD_MANAGER_ADDRESS");
        address infraredAdapter = vm.envAddress("INFRARED_ADAPTER_ADDRESS");
        address kodiakAdapter = vm.envAddress("KODIAK_ADAPTER_ADDRESS");

        // Optional: bond contracts (may not be deployed yet if LP wasn't available)
        address ibgtBond = vm.envOr("IBGT_BOND_ADDRESS", address(0));
        address lpBond = vm.envOr("LP_BOND_ADDRESS", address(0));

        console.log("==============================================");
        console.log("  ACCEPT OWNERSHIP (Multisig)");
        console.log("==============================================");

        vm.startBroadcast();

        ApiaryTreasury(treasury).acceptOwnership();
        console.log("  Treasury: ownership accepted");

        ApiaryStaking(payable(staking)).acceptOwnership();
        console.log("  Staking: ownership accepted");

        sApiary(sApiaryAddr).acceptOwnership();
        console.log("  sApiary: ownership accepted");

        ApiaryPreSaleBond(preSale).acceptOwnership();
        console.log("  Pre-Sale Bond: ownership accepted");

        ApiaryYieldManager(yieldManager).acceptOwnership();
        console.log("  Yield Manager: ownership accepted");

        ApiaryInfraredAdapter(infraredAdapter).acceptOwnership();
        console.log("  Infrared Adapter: ownership accepted");

        ApiaryKodiakAdapter(kodiakAdapter).acceptOwnership();
        console.log("  Kodiak Adapter: ownership accepted");

        if (ibgtBond != address(0)) {
            ApiaryBondDepository(ibgtBond).acceptOwnership();
            console.log("  iBGT Bond: ownership accepted");
        }

        if (lpBond != address(0)) {
            ApiaryBondDepository(lpBond).acceptOwnership();
            console.log("  LP Bond: ownership accepted");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("  All ownership transfers accepted.");
        console.log("  Next: deployer should run RenounceDeployerAdmin");
        console.log("==============================================");
    }
}

/// @notice Deployer renounces DEFAULT_ADMIN_ROLE on ApiaryToken
contract RenounceDeployerAdmin is Script {
    function run() external {
        address apiaryAddr = vm.envAddress("APIARY_ADDRESS");
        address multisig = vm.envAddress("MULTISIG_ADDRESS");

        ApiaryToken apiary = ApiaryToken(apiaryAddr);
        bytes32 adminRole = apiary.DEFAULT_ADMIN_ROLE();

        console.log("==============================================");
        console.log("  RENOUNCE DEPLOYER ADMIN ROLE");
        console.log("==============================================");

        // Safety check: multisig must already have admin role
        require(
            apiary.hasRole(adminRole, multisig),
            "Multisig does not have DEFAULT_ADMIN_ROLE yet - run AcceptOwnershipMultisig first"
        );

        vm.startBroadcast();

        // Deployer renounces their own admin role
        apiary.renounceRole(adminRole, msg.sender);
        console.log("  Deployer admin role renounced");

        vm.stopBroadcast();

        // Verify
        require(!apiary.hasRole(adminRole, msg.sender), "Deployer still has admin role!");
        require(apiary.hasRole(adminRole, multisig), "Multisig lost admin role!");
        console.log("  Verified: only multisig has DEFAULT_ADMIN_ROLE");
        console.log("==============================================");
    }
}
