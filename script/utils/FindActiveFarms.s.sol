// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IKodiakFarm} from "../../src/interfaces/IKodiakFarm.sol";

/**
 * @title FindActiveFarms
 * @notice Script to discover active Kodiak Farms on Berachain mainnet
 * 
 * @dev RUN WITH:
 *      forge script script/utils/FindActiveFarms.s.sol:FindActiveFarms \
 *        --fork-url https://rpc.berachain.com -vvv
 * 
 * This script helps find active farms to use in fork testing.
 * It queries the KodiakFarmFactory and known farm addresses.
 */
contract FindActiveFarms is Script {
    /*//////////////////////////////////////////////////////////////
                            MAINNET ADDRESSES
    //////////////////////////////////////////////////////////////*/
    
    address constant KODIAK_FARM_FACTORY = 0xAeAa563d9110f833FA3fb1FF9a35DFBa11B0c9cF;
    address constant KODIAK_V2_FACTORY = 0x5e705e184D233FF2A7cb1553793464a9d0C3028F;
    address constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address constant WBERA = 0x6969696969696969696969696969696969696969;
    
    /*//////////////////////////////////////////////////////////////
                                RUN
    //////////////////////////////////////////////////////////////*/
    
    function run() external view {
        console.log("===========================================");
        console.log("=== Finding Active Kodiak Farms ===");
        console.log("===========================================\n");
        
        // Check factory info
        _checkFactory();
        
        // Try to find farms for common pairs
        _findFarmForPair(WBERA, HONEY, "WBERA/HONEY");
        
        // List some known farm addresses to check (update these)
        address[] memory knownFarms = _getKnownFarms();
        for (uint256 i = 0; i < knownFarms.length; i++) {
            _inspectFarm(knownFarms[i]);
        }
        
        console.log("\n===========================================");
        console.log("=== Discovery Complete ===");
        console.log("===========================================");
    }
    
    function _checkFactory() internal view {
        console.log("Checking KodiakFarmFactory at:", KODIAK_FARM_FACTORY);
        
        if (KODIAK_FARM_FACTORY.code.length == 0) {
            console.log("  WARNING: Factory has no code!");
            return;
        }
        
        console.log("  Factory has code, attempting to query...\n");
    }
    
    function _findFarmForPair(address tokenA, address tokenB, string memory name) internal view {
        console.log("Looking for", name, "farm...");
        
        // Get LP token from V2 factory
        address lp = IKodiakV2Factory(KODIAK_V2_FACTORY).getPair(tokenA, tokenB);
        
        if (lp == address(0)) {
            console.log("  No LP pair found for", name);
            return;
        }
        
        console.log("  LP token:", lp);
        
        // Try different methods to find the farm
        
        // Method 1: lpToFarm mapping
        try IKodiakFarmFactory(KODIAK_FARM_FACTORY).lpToFarm(lp) returns (address farm) {
            if (farm != address(0)) {
                console.log("  Farm found via lpToFarm:", farm);
                _inspectFarm(farm);
                return;
            }
        } catch {}
        
        // Method 2: getFarm function
        try IKodiakFarmFactory(KODIAK_FARM_FACTORY).getFarm(lp) returns (address farm) {
            if (farm != address(0)) {
                console.log("  Farm found via getFarm:", farm);
                _inspectFarm(farm);
                return;
            }
        } catch {}
        
        // Method 3: gauges mapping (some versions use this)
        try IKodiakFarmFactory(KODIAK_FARM_FACTORY).gauges(lp) returns (address farm) {
            if (farm != address(0)) {
                console.log("  Farm found via gauges:", farm);
                _inspectFarm(farm);
                return;
            }
        } catch {}
        
        console.log("  No farm found for this LP\n");
    }
    
    function _inspectFarm(address farmAddress) internal view {
        console.log("\n--- Inspecting Farm:", farmAddress, "---");
        
        if (farmAddress.code.length == 0) {
            console.log("  ERROR: No code at address");
            return;
        }
        
        IKodiakFarm farm = IKodiakFarm(farmAddress);
        
        // Try to read farm config
        try farm.stakingToken() returns (address stakingToken) {
            console.log("  Staking Token:", stakingToken);
            
            try farm.lock_time_min() returns (uint256 minLock) {
                console.log("  Min Lock Time (sec):", minLock);
                console.log("  Min Lock Time (days):", minLock / 1 days);
            } catch {
                console.log("  Min Lock Time: FAILED TO READ");
            }
            
            try farm.lock_time_for_max_multiplier() returns (uint256 maxLock) {
                console.log("  Max Lock Time (sec):", maxLock);
                console.log("  Max Lock Time (days):", maxLock / 1 days);
            } catch {
                console.log("  Max Lock Time: FAILED TO READ");
            }
            
            try farm.lock_max_multiplier() returns (uint256 mult) {
                console.log("  Max Multiplier:", mult);
                console.log("  Max Multiplier (x):", mult / 1e18);
            } catch {
                console.log("  Max Multiplier: FAILED TO READ");
            }
            
            try farm.totalLiquidityLocked() returns (uint256 total) {
                console.log("  Total Locked:", total);
            } catch {
                console.log("  Total Locked: FAILED TO READ");
            }
            
            try farm.stakingPaused() returns (bool paused) {
                console.log("  Staking Paused:", paused);
            } catch {
                console.log("  Staking Paused: FAILED TO READ");
            }
            
            try farm.getAllRewardTokens() returns (address[] memory tokens) {
                console.log("  Reward Tokens:", tokens.length);
                for (uint256 i = 0; i < tokens.length; i++) {
                    console.log("    [", i, "]:", tokens[i]);
                }
            } catch {
                console.log("  Reward Tokens: FAILED TO READ");
            }
            
            console.log("  === FARM IS VALID ===\n");
            
        } catch {
            console.log("  ERROR: Could not read stakingToken - likely not a valid farm");
        }
    }
    
    /**
     * @notice Returns known farm addresses to check
     * @dev Update this list with actual farm addresses from mainnet
     *      You can find these via:
     *      - Kodiak UI
     *      - Block explorer events
     *      - Community resources
     */
    function _getKnownFarms() internal pure returns (address[] memory) {
        // TODO: Add known farm addresses here after discovering them
        // Example:
        // address[] memory farms = new address[](2);
        // farms[0] = 0x1234...;
        // farms[1] = 0x5678...;
        
        address[] memory farms = new address[](0);
        return farms;
    }
}

/*//////////////////////////////////////////////////////////////
                    HELPER INTERFACES
//////////////////////////////////////////////////////////////*/

interface IKodiakFarmFactory {
    function lpToFarm(address lp) external view returns (address);
    function getFarm(address lp) external view returns (address);
    function gauges(address lp) external view returns (address);
    function allFarms(uint256 index) external view returns (address);
    function allFarmsLength() external view returns (uint256);
}

interface IKodiakV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
}
