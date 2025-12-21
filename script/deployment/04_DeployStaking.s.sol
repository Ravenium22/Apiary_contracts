// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../../src/ApiaryStaking.sol";
import "../../src/ApiaryStakingWarmup.sol";

/**
 * @title DeployStaking
 * @notice Deployment script for Apiary Staking and Warmup contracts
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
 *   - SAPIARY_ADDRESS: Address of sAPIARY token
 *   - EPOCH_LENGTH: Length of each epoch in blocks (e.g., 28800 for 8 hours on Berachain)
 *   - FIRST_EPOCH_NUMBER: Starting epoch number (usually 0)
 *   - FIRST_EPOCH_BLOCK: Block number when first epoch ends
 *   - PROTOCOL_ADMIN: Address of the protocol admin/owner
 */
contract DeployStaking is Script {
    
    function run() external returns (address staking, address warmup) {
        // Load environment variables
        address apiary = vm.envAddress("APIARY_ADDRESS");
        address sApiaryAddr = vm.envAddress("SAPIARY_ADDRESS");
        uint256 epochLength = vm.envUint("EPOCH_LENGTH");
        uint256 firstEpochNumber = vm.envUint("FIRST_EPOCH_NUMBER");
        uint256 firstEpochBlock = vm.envUint("FIRST_EPOCH_BLOCK");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
        
        console.log("=== Deploying Apiary Staking ===");
        console.log("APIARY:", apiary);
        console.log("sAPIARY:", sApiaryAddr);
        console.log("Epoch Length:", epochLength, "blocks");
        console.log("First Epoch Number:", firstEpochNumber);
        console.log("First Epoch Block:", firstEpochBlock);
        console.log("Protocol Admin:", protocolAdmin);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy Staking contract
        // Constructor: ApiaryStaking(_APIARY, _sAPIARY, _epochLength, _firstEpochNumber, _firstEpochBlock, _initialOwner)
        ApiaryStaking stakingContract = new ApiaryStaking(
            apiary,
            sApiaryAddr,
            epochLength,
            firstEpochNumber,
            firstEpochBlock,
            protocolAdmin
        );
        
        // Deploy Warmup contract
        // Constructor: ApiaryStakingWarmup(address _staking, address _sAPIARY)
        ApiaryStakingWarmup warmupContract = new ApiaryStakingWarmup(
            address(stakingContract),
            sApiaryAddr
        );
        
        vm.stopBroadcast();
        
        console.log("\n=== Staking Contracts Deployed ===");
        console.log("Staking:", address(stakingContract));
        console.log("Warmup:", address(warmupContract));
        console.log("Owner:", stakingContract.owner());
        
        // Get epoch info
        (uint256 length, uint256 number, uint256 endBlock, uint256 distribute) = stakingContract.epoch();
        
        console.log("\nEpoch Configuration:");
        console.log("  Length:", length, "blocks");
        console.log("  Number:", number);
        console.log("  End Block:", endBlock);
        console.log("  Distribute:", distribute, "(Phase 1: no yield)");
        
        // Sanity checks
        require(stakingContract.owner() == protocolAdmin, "Owner not set correctly");
        require(stakingContract.APIARY() == apiary, "APIARY not set");
        require(stakingContract.sAPIARY() == sApiaryAddr, "sAPIARY not set");
        require(length == epochLength, "Epoch length incorrect");
        require(number == firstEpochNumber, "First epoch number incorrect");
        require(endBlock == firstEpochBlock, "First epoch block incorrect");
        require(distribute == 0, "Distribute should be 0 for Phase 1");
        
        require(warmupContract.staking() == address(stakingContract), "Warmup staking not set");
        require(address(warmupContract.sAPIARY()) == sApiaryAddr, "Warmup sAPIARY not set");
        
        console.log(unicode"\n✓ Staking deployment successful!");
        console.log(unicode"✓ Owner verified");
        console.log(unicode"✓ Epoch configuration verified");
        console.log(unicode"✓ Warmup contract verified");
        console.log(unicode"\n⚠ Next steps:");
        console.log("  1. Initialize sAPIARY with staking contract address");
        console.log("  2. Set warmup contract in staking");
        console.log("  3. Set locker contract in staking (if using lockup)");
        
        return (address(stakingContract), address(warmupContract));
    }
}
