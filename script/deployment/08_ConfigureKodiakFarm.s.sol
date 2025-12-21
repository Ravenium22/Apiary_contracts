// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ApiaryKodiakAdapter} from "../../src/ApiaryKodiakAdapter.sol";
import {IKodiakFarm} from "../../src/interfaces/IKodiakFarm.sol";

/**
 * @title ConfigureKodiakFarm
 * @notice Phase C: Configure the Kodiak adapter with the farm address and lock duration
 * 
 * PREREQUISITES:
 * ============================================================================
 * 1. Phase A (Script 06): Protocol deployed with YieldManager and KodiakAdapter
 * 2. Phase B (Manual): APIARY/HONEY LP created and farm deployed via Kodiak UI
 *    - Create LP pair on Kodiak DEX (https://app.kodiak.finance/#/pools)
 *    - Deploy farm via KodiakFarmFactory for the LP pair
 *    - Record the farm contract address (NOT the factory at 0xEB81a9...)
 * 
 * USAGE:
 * ============================================================================
 * Set the following environment variables before running:
 *   PRIVATE_KEY             - Deployer private key (must be adapter owner)
 *   KODIAK_FARM_ADDRESS     - The farm contract address from Phase B
 *   LP_TOKEN_ADDRESS        - The APIARY/HONEY LP token address
 *   LOCK_DURATION_DAYS      - Lock duration in days (default: 30)
 *   ADAPTER_ADDRESS         - KodiakAdapter address
 * 
 * Run command:
 *   forge script script/deployment/08_ConfigureKodiakFarm.s.sol:ConfigureKodiakFarm \
 *     --rpc-url $RPC_URL --broadcast --verify
 * 
 * WHAT THIS SCRIPT DOES:
 * ============================================================================
 * 1. Validates the Kodiak farm is legitimate and stakes the correct LP token
 * 2. Calls registerFarm(lpToken, farmAddress) on the adapter to set the farm address
 * 3. Calls setLockDuration(lpToken, lockDuration) to configure the staking lock period
 * 4. Verifies the configuration was applied correctly
 */
contract ConfigureKodiakFarm is Script {
    // Default lock duration: 30 days
    uint256 constant DEFAULT_LOCK_DURATION = 30 days;
    
    // Minimum lock duration: 1 day (safety check)
    uint256 constant MIN_LOCK_DURATION = 1 days;
    
    // Maximum lock duration: 365 days (safety check)
    uint256 constant MAX_LOCK_DURATION = 365 days;

    function run() external {
        // Load private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("Phase C: Configure Kodiak Farm");
        console.log("========================================");
        console.log("Deployer:", deployer);
        
        // Get farm address (required)
        address farmAddress = vm.envAddress("KODIAK_FARM_ADDRESS");
        require(farmAddress != address(0), "KODIAK_FARM_ADDRESS not set");
        console.log("Farm Address:", farmAddress);
        
        // Get LP token address (required)
        address lpToken = vm.envAddress("LP_TOKEN_ADDRESS");
        require(lpToken != address(0), "LP_TOKEN_ADDRESS not set");
        console.log("LP Token:", lpToken);
        
        // Get lock duration (optional, default 30 days)
        uint256 lockDurationDays = vm.envOr("LOCK_DURATION_DAYS", uint256(30));
        uint256 lockDuration = lockDurationDays * 1 days;
        console.log("Lock Duration:", lockDurationDays, "days");
        
        // Validate lock duration
        require(lockDuration >= MIN_LOCK_DURATION, "Lock duration too short (min 1 day)");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock duration too long (max 365 days)");
        
        // Get adapter address (required)
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        require(adapterAddress != address(0), "ADAPTER_ADDRESS not set");
        ApiaryKodiakAdapter adapter = ApiaryKodiakAdapter(adapterAddress);
        console.log("Kodiak Adapter:", address(adapter));
        
        // Verify deployer is owner
        require(adapter.owner() == deployer, "Deployer is not adapter owner");
        console.log("Owner verification: PASSED");
        
        // Validate the farm
        _validateFarm(farmAddress, lpToken, adapter);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Register the farm
        console.log("\n--- Registering Farm ---");
        adapter.registerFarm(lpToken, farmAddress);
        console.log("Farm registered successfully");
        
        // Step 2: Set lock duration
        console.log("\n--- Setting Lock Duration ---");
        adapter.setLockDuration(lpToken, lockDuration);
        console.log("Lock duration set to", lockDurationDays, "days");
        
        vm.stopBroadcast();
        
        // Verify configuration
        _verifyConfiguration(adapter, lpToken, farmAddress, lockDuration);
        
        console.log("\n========================================");
        console.log("Kodiak Farm Configuration Complete!");
        console.log("========================================");
        console.log("\nNext steps:");
        console.log("1. Run VerifyDeployment.s.sol to confirm full protocol setup");
        console.log("2. Treasury can now deposit LP tokens for Kodiak staking");
        console.log("3. Monitor farm rewards via adapter.getPendingRewards(lpToken)");
    }
    
    function _validateFarm(address farmAddress, address lpToken, ApiaryKodiakAdapter adapter) internal view {
        console.log("\n--- Validating Farm ---");
        
        // Check farm has code
        require(farmAddress.code.length > 0, "Farm address has no code");
        console.log("Farm contract exists: PASSED");
        
        // Check LP token has code
        require(lpToken.code.length > 0, "LP token address has no code");
        console.log("LP token contract exists: PASSED");
        
        // Check farm stakes the correct LP token
        IKodiakFarm farm = IKodiakFarm(farmAddress);
        try farm.stakingToken() returns (address farmLP) {
            console.log("Farm staking token:", farmLP);
            require(farmLP == lpToken, "Farm LP token mismatch!");
            console.log("LP token match: PASSED");
        } catch {
            revert("Could not read farm stakingToken()");
        }
        
        // Check farm is not already registered for this LP
        address currentFarm = adapter.lpToFarm(lpToken);
        require(currentFarm == address(0), "Farm already registered for this LP");
        console.log("No existing farm: PASSED");
        
        // Read farm lock settings
        try farm.lock_time_min() returns (uint256 minLock) {
            console.log("Farm min lock:", minLock / 1 days, "days");
        } catch {}
        
        try farm.lock_time_for_max_multiplier() returns (uint256 maxLock) {
            console.log("Farm max multiplier lock:", maxLock / 1 days, "days");
        } catch {}
        
        console.log("Farm validation: PASSED");
    }
    
    function _verifyConfiguration(
        ApiaryKodiakAdapter adapter,
        address lpToken,
        address expectedFarm,
        uint256 expectedLockDuration
    ) internal view {
        console.log("\n--- Verifying Configuration ---");
        
        // Verify farm address
        address actualFarm = adapter.lpToFarm(lpToken);
        require(actualFarm == expectedFarm, "Farm address not set correctly");
        console.log("Farm address verified: PASSED");
        
        // Verify lock duration
        uint256 actualLockDuration = adapter.lpLockDuration(lpToken);
        require(actualLockDuration == expectedLockDuration, "Lock duration not set correctly");
        console.log("Lock duration verified: PASSED");
        
        // Check adapter is ready for staking
        console.log("\nAdapter Status:");
        console.log("  Treasury:", adapter.treasury());
        console.log("  Yield Manager:", adapter.yieldManager());
        console.log("  Farm for LP:", adapter.lpToFarm(lpToken));
        console.log("  Lock Duration:", adapter.lpLockDuration(lpToken) / 1 days, "days");
        console.log("  LP Token:", lpToken);
        
        console.log("\nConfiguration verification: PASSED");
    }
}
