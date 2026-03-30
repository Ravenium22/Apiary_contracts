// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryStaking.sol";

/**
 * @title DeployStaking
 * @notice Deployment script for Apiary Staking contract
 * @dev Step 4 of Apiary protocol deployment
 *
 * Usage:
 *   forge script script/deployment/04_DeployStaking.s.sol:DeployStaking \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 *
 * Environment Variables Required:
 *   - APIARY_ADDRESS: Address of APIARY token
 *   - PROTOCOL_ADMIN: Address of the protocol admin/owner
 */
contract DeployStaking is Script {

    function run() external returns (address staking) {
        // Load environment variables
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");

        console.log("=== Deploying Apiary Staking ===");
        console.log("APIARY:", apiary);
        console.log("Protocol Admin:", protocolAdmin);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();

        // Deploy Staking contract (Synthetix StakingRewards model)
        // Constructor: ApiaryStaking(_apiary, _initialOwner)
        ApiaryStaking stakingContract = new ApiaryStaking(
            apiary,
            protocolAdmin
        );

        vm.stopBroadcast();

        console.log("\n=== Staking Contract Deployed ===");
        console.log("Staking:", address(stakingContract));
        console.log("Owner:", stakingContract.owner());

        // Sanity checks
        require(stakingContract.owner() == protocolAdmin, "Owner not set correctly");
        require(stakingContract.APIARY() == apiary, "APIARY not set");

        console.log(unicode"\n\u2713 Staking deployment successful!");
        console.log(unicode"\u2713 Owner verified");
        console.log(unicode"\n\u26a0 Next steps:");
        console.log("  1. Set rewards distributor (yield manager) via setRewardsDistributor()");

        return address(stakingContract);
    }
}
