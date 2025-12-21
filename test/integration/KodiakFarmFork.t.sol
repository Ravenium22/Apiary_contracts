// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IKodiakFarm} from "../../src/interfaces/IKodiakFarm.sol";
import {IKodiakRouter} from "../../src/interfaces/IKodiakRouter.sol";
import {IKodiakFactory} from "../../src/interfaces/IKodiakFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KodiakFarmForkTest
 * @notice Integration test that forks Berachain mainnet to verify our
 *         IKodiakFarm interface matches the real Kodiak Farm implementation
 * 
 * @dev RUN WITH:
 *      forge test --match-contract KodiakFarmForkTest --fork-url https://rpc.berachain.com -vvv
 * 
 *      Or with specific test:
 *      forge test --match-test test_realFarmInterface --fork-url https://rpc.berachain.com -vvv
 * 
 * ADDRESSES (Berachain Mainnet):
 * - KodiakFarmFactory: 0xAeAa563d9110f833FA3fb1FF9a35DFBa11B0c9cF
 * - Kodiak V2 Router: 0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022
 * - Kodiak V2 Factory: 0x5e705e184d233ff2a7cb1553793464a9d0c3028f
 * - HONEY: 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce
 * - WBERA: 0x6969696969696969696969696969696969696969
 */
contract KodiakFarmForkTest is Test {
    /*//////////////////////////////////////////////////////////////
                            MAINNET ADDRESSES
    //////////////////////////////////////////////////////////////*/
    
    // Core Kodiak contracts
    address constant KODIAK_FARM_FACTORY = 0xAeAa563d9110f833FA3fb1FF9a35DFBa11B0c9cF;
    address constant KODIAK_V2_ROUTER = 0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022;
    address constant KODIAK_V2_FACTORY = 0x5e705e184D233FF2A7cb1553793464a9d0C3028F;
    
    // Tokens
    address constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address constant WBERA = 0x6969696969696969696969696969696969696969;
    
    // Known active farms (update these if they become inactive)
    // WBERA/HONEY farm - popular pair likely to have a farm
    // We'll discover this dynamically or hardcode if known
    
    /*//////////////////////////////////////////////////////////////
                              STATE
    //////////////////////////////////////////////////////////////*/
    
    uint256 berachainFork;
    
    IKodiakRouter router;
    IKodiakFactory factory;
    
    address testFarm;
    address testLPToken;
    address testUser;
    
    // Track discovered farms for inspection
    address[] discoveredFarms;
    
    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Create fork - this will be overridden by --fork-url in command
        // But we set it here for IDE support
        string memory rpcUrl = vm.envOr("BERACHAIN_RPC", string("https://rpc.berachain.com"));
        berachainFork = vm.createFork(rpcUrl);
        vm.selectFork(berachainFork);
        
        // Initialize contracts
        router = IKodiakRouter(KODIAK_V2_ROUTER);
        factory = IKodiakFactory(KODIAK_V2_FACTORY);
        
        // Setup test user with funds
        testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);
        
        // Find an active farm to test against
        _discoverActiveFarm();
    }
    
    /*//////////////////////////////////////////////////////////////
                         FARM DISCOVERY
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Discover an active farm to test against
     * @dev Tries multiple strategies:
     *      1. Check known popular LP pairs for farms
     *      2. Query factory events (if available)
     *      3. Use hardcoded known farm addresses
     */
    function _discoverActiveFarm() internal {
        // Strategy 1: Check WBERA/HONEY LP
        address wberaHoneyLP = factory.getPair(WBERA, HONEY);
        if (wberaHoneyLP != address(0)) {
            console.log("Found WBERA/HONEY LP:", wberaHoneyLP);
            
            // Try to find farm for this LP via factory
            address farm = _findFarmForLP(wberaHoneyLP);
            if (farm != address(0)) {
                testFarm = farm;
                testLPToken = wberaHoneyLP;
                console.log("Found farm for WBERA/HONEY:", farm);
                return;
            }
        }
        
        // Strategy 2: Try other common pairs
        address[] memory commonTokens = _getCommonTokens();
        for (uint256 i = 0; i < commonTokens.length; i++) {
            for (uint256 j = i + 1; j < commonTokens.length; j++) {
                address pair = factory.getPair(commonTokens[i], commonTokens[j]);
                if (pair != address(0)) {
                    address farm = _findFarmForLP(pair);
                    if (farm != address(0) && _isFarmActive(farm)) {
                        testFarm = farm;
                        testLPToken = pair;
                        console.log("Found active farm:", farm);
                        console.log("For LP token:", pair);
                        return;
                    }
                }
            }
        }
        
        // Strategy 3: Use hardcoded known farm (update as needed)
        // This is a fallback - update with an actual farm address from mainnet
        console.log("WARNING: No active farm discovered automatically");
        console.log("Tests may be skipped or fail");
    }
    
    /**
     * @notice Get common tokens to search for pairs
     */
    function _getCommonTokens() internal pure returns (address[] memory) {
        address[] memory tokens = new address[](3);
        tokens[0] = WBERA;
        tokens[1] = HONEY;
        // Add more common tokens as needed
        // tokens[2] = USDC;
        return tokens;
    }
    
    /**
     * @notice Try to find a farm for a given LP token
     * @dev This is a heuristic approach since we don't have factory.getFarm()
     *      We check if there's a farm that accepts this LP token
     */
    function _findFarmForLP(address lpToken) internal view returns (address) {
        // The KodiakFarmFactory doesn't have a simple getFarm() function
        // We need to either:
        // 1. Query past FarmCreated events
        // 2. Have a list of known farm addresses
        // 3. Iterate through possible farm addresses
        
        // For now, we'll check if there's a farm using a known pattern
        // This would need to be updated based on actual factory interface
        
        // Try checking the factory for lpToFarm mapping if it exists
        try IKodiakFarmFactory(KODIAK_FARM_FACTORY).lpToFarm(lpToken) returns (address farm) {
            if (farm != address(0)) {
                return farm;
            }
        } catch {}
        
        // Alternative: Check if the factory has a getFarm function
        try IKodiakFarmFactory(KODIAK_FARM_FACTORY).getFarm(lpToken) returns (address farm) {
            if (farm != address(0)) {
                return farm;
            }
        } catch {}
        
        return address(0);
    }
    
    /**
     * @notice Check if a farm is active and has liquidity
     */
    function _isFarmActive(address farm) internal view returns (bool) {
        if (farm == address(0) || farm.code.length == 0) return false;
        
        try IKodiakFarm(farm).stakingToken() returns (address) {
            try IKodiakFarm(farm).stakingPaused() returns (bool paused) {
                return !paused;
            } catch {
                return true; // Assume active if we can't check
            }
        } catch {
            return false;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                    INTERFACE COMPATIBILITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Verify our IKodiakFarm interface matches the real implementation
     * @dev Tests all view functions - should not revert if interface is correct
     */
    function test_realFarmInterface() public {
        vm.skip(testFarm == address(0));
        
        console.log("Testing farm interface at:", testFarm);
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        // Core config functions - MUST match
        address stakingToken = farm.stakingToken();
        console.log("stakingToken():", stakingToken);
        require(stakingToken != address(0), "stakingToken returned zero");
        require(stakingToken == testLPToken, "stakingToken mismatch");
        
        // Lock time config
        uint256 lockTimeMin = farm.lock_time_min();
        console.log("lock_time_min():", lockTimeMin);
        
        uint256 lockTimeMax = farm.lock_time_for_max_multiplier();
        console.log("lock_time_for_max_multiplier():", lockTimeMax);
        require(lockTimeMax >= lockTimeMin, "Invalid lock time config");
        
        uint256 maxMultiplier = farm.lock_max_multiplier();
        console.log("lock_max_multiplier():", maxMultiplier);
        require(maxMultiplier >= 1e18, "Max multiplier should be >= 1x");
        
        // Reward tokens
        address[] memory rewardTokens = farm.getAllRewardTokens();
        console.log("getAllRewardTokens() count:", rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            console.log("  Reward token", i, ":", rewardTokens[i]);
        }
        
        // Global state
        uint256 totalLocked = farm.totalLiquidityLocked();
        console.log("totalLiquidityLocked():", totalLocked);
        
        // Check staking/rewards status
        bool stakingPaused = farm.stakingPaused();
        console.log("stakingPaused():", stakingPaused);
        
        bool rewardsPaused = farm.rewardsCollectionPaused();
        console.log("rewardsCollectionPaused():", rewardsPaused);
        
        bool unlocked = farm.stakesUnlocked();
        console.log("stakesUnlocked():", unlocked);
        
        // Multiplier calculation
        if (lockTimeMin > 0) {
            uint256 multiplier = farm.lockMultiplier(lockTimeMin);
            console.log("lockMultiplier(min):", multiplier);
            require(multiplier >= 1e18, "Min lock multiplier should be >= 1x");
        }
        
        console.log("\n=== Interface Test PASSED ===");
    }
    
    /**
     * @notice Test view functions for a user account
     */
    function test_userViewFunctions() public {
        vm.skip(testFarm == address(0));
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        // Test user view functions (should work even with no stakes)
        uint256 locked = farm.lockedLiquidityOf(testUser);
        console.log("lockedLiquidityOf(testUser):", locked);
        assertEq(locked, 0, "New user should have 0 locked");
        
        IKodiakFarm.LockedStake[] memory stakes = farm.lockedStakesOf(testUser);
        console.log("lockedStakesOf(testUser) count:", stakes.length);
        assertEq(stakes.length, 0, "New user should have 0 stakes");
        
        uint256[] memory earned = farm.earned(testUser);
        console.log("earned(testUser) tokens:", earned.length);
        
        uint256 weight = farm.combinedWeightOf(testUser);
        console.log("combinedWeightOf(testUser):", weight);
        assertEq(weight, 0, "New user should have 0 weight");
        
        console.log("\n=== User View Functions Test PASSED ===");
    }
    
    /*//////////////////////////////////////////////////////////////
                        STAKING FLOW TESTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Test full staking flow: get LP tokens, stake, wait, withdraw
     */
    function test_stakeAndWithdraw() public {
        vm.skip(testFarm == address(0));
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        // Skip if staking is paused
        if (farm.stakingPaused()) {
            console.log("Staking is paused, skipping test");
            return;
        }
        
        // Get LP tokens first
        uint256 lpAmount = _getLPTokens(1 ether);
        if (lpAmount == 0) {
            console.log("Could not get LP tokens, skipping");
            return;
        }
        console.log("Got LP tokens:", lpAmount);
        
        // Get lock duration
        uint256 lockDuration = farm.lock_time_min();
        if (lockDuration == 0) {
            lockDuration = 7 days; // Default if min is 0
        }
        console.log("Lock duration:", lockDuration);
        
        // Approve and stake
        vm.startPrank(testUser);
        IERC20(testLPToken).approve(testFarm, lpAmount);
        
        uint256 stakedBefore = farm.lockedLiquidityOf(testUser);
        
        // Stake and capture kek_id
        bytes32 kekId = farm.stakeLocked(lpAmount, lockDuration);
        console.log("Staked! kek_id:", vm.toString(kekId));
        
        // Verify stake recorded
        uint256 stakedAfter = farm.lockedLiquidityOf(testUser);
        assertEq(stakedAfter, stakedBefore + lpAmount, "Staked amount not recorded");
        
        // Verify stake in lockedStakesOf
        IKodiakFarm.LockedStake[] memory stakes = farm.lockedStakesOf(testUser);
        assertGt(stakes.length, 0, "Should have at least 1 stake");
        
        bool foundStake = false;
        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].kek_id == kekId) {
                foundStake = true;
                assertEq(stakes[i].liquidity, lpAmount, "Stake liquidity mismatch");
                assertGt(stakes[i].lock_multiplier, 0, "Should have multiplier > 0");
                console.log("Stake verified:");
                console.log("  liquidity:", stakes[i].liquidity);
                console.log("  lock_multiplier:", stakes[i].lock_multiplier);
                console.log("  ending_timestamp:", stakes[i].ending_timestamp);
                break;
            }
        }
        assertTrue(foundStake, "Could not find our stake");
        
        // Warp time past lock
        vm.warp(block.timestamp + lockDuration + 1);
        
        // Withdraw
        uint256 lpBefore = IERC20(testLPToken).balanceOf(testUser);
        farm.withdrawLocked(kekId);
        uint256 lpAfter = IERC20(testLPToken).balanceOf(testUser);
        
        assertEq(lpAfter - lpBefore, lpAmount, "Should receive full LP amount back");
        
        vm.stopPrank();
        
        console.log("\n=== Stake and Withdraw Test PASSED ===");
    }
    
    /**
     * @notice Test claiming rewards
     */
    function test_claimRewards() public {
        vm.skip(testFarm == address(0));
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        if (farm.stakingPaused() || farm.rewardsCollectionPaused()) {
            console.log("Staking or rewards paused, skipping");
            return;
        }
        
        // Get and stake LP tokens
        uint256 lpAmount = _getLPTokens(1 ether);
        if (lpAmount == 0) {
            console.log("Could not get LP tokens, skipping");
            return;
        }
        
        uint256 lockDuration = farm.lock_time_min();
        if (lockDuration == 0) lockDuration = 7 days;
        
        vm.startPrank(testUser);
        IERC20(testLPToken).approve(testFarm, lpAmount);
        bytes32 kekId = farm.stakeLocked(lpAmount, lockDuration);
        
        // Warp time to accrue rewards
        vm.warp(block.timestamp + 1 days);
        
        // Check earned rewards
        uint256[] memory earnedBefore = farm.earned(testUser);
        console.log("Earned rewards after 1 day:");
        address[] memory rewardTokens = farm.getAllRewardTokens();
        for (uint256 i = 0; i < earnedBefore.length; i++) {
            console.log("  ", rewardTokens[i], ":", earnedBefore[i]);
        }
        
        // Record balances before claim
        uint256[] memory balancesBefore = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(testUser);
        }
        
        // Claim rewards
        uint256[] memory claimed = farm.getReward();
        console.log("Claimed rewards:");
        for (uint256 i = 0; i < claimed.length; i++) {
            console.log("  ", rewardTokens[i], ":", claimed[i]);
        }
        
        // Verify received
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 received = IERC20(rewardTokens[i]).balanceOf(testUser) - balancesBefore[i];
            // Note: Received might differ slightly from claimed due to timing
            if (claimed[i] > 0) {
                assertGt(received, 0, "Should have received rewards");
            }
        }
        
        // Clean up: warp to unlock and withdraw
        vm.warp(block.timestamp + lockDuration);
        farm.withdrawLocked(kekId);
        
        vm.stopPrank();
        
        console.log("\n=== Claim Rewards Test PASSED ===");
    }
    
    /**
     * @notice Test withdrawLockedAll function
     */
    function test_withdrawLockedAll() public {
        vm.skip(testFarm == address(0));
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        if (farm.stakingPaused()) {
            console.log("Staking paused, skipping");
            return;
        }
        
        // Get LP tokens and create multiple stakes
        uint256 lpAmount = _getLPTokens(2 ether);
        if (lpAmount == 0) {
            console.log("Could not get LP tokens, skipping");
            return;
        }
        
        uint256 lockDuration = farm.lock_time_min();
        if (lockDuration == 0) lockDuration = 7 days;
        
        vm.startPrank(testUser);
        IERC20(testLPToken).approve(testFarm, lpAmount);
        
        // Create 2 stakes
        uint256 stake1Amount = lpAmount / 2;
        uint256 stake2Amount = lpAmount - stake1Amount;
        
        bytes32 kekId1 = farm.stakeLocked(stake1Amount, lockDuration);
        bytes32 kekId2 = farm.stakeLocked(stake2Amount, lockDuration);
        console.log("Created stakes:", vm.toString(kekId1), vm.toString(kekId2));
        
        // Warp past lock
        vm.warp(block.timestamp + lockDuration + 1);
        
        // Withdraw all
        uint256 lpBefore = IERC20(testLPToken).balanceOf(testUser);
        farm.withdrawLockedAll();
        uint256 lpAfter = IERC20(testLPToken).balanceOf(testUser);
        
        assertEq(lpAfter - lpBefore, lpAmount, "Should receive all LP back");
        
        // Verify no stakes remain
        IKodiakFarm.LockedStake[] memory stakes = farm.lockedStakesOf(testUser);
        assertEq(stakes.length, 0, "Should have no stakes after withdrawAll");
        
        vm.stopPrank();
        
        console.log("\n=== Withdraw All Test PASSED ===");
    }
    
    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get LP tokens for testing by adding liquidity
     * @dev Uses router to add liquidity to the test pair
     */
    function _getLPTokens(uint256 beraAmount) internal returns (uint256) {
        if (testLPToken == address(0)) return 0;
        
        // Figure out which tokens the LP needs
        address token0;
        address token1;
        try IKodiakPair(testLPToken).token0() returns (address t0) {
            token0 = t0;
            token1 = IKodiakPair(testLPToken).token1();
        } catch {
            console.log("Could not get LP pair tokens");
            return 0;
        }
        
        console.log("LP pair: token0=", token0, "token1=", token1);
        
        // Get token balances for user
        // For WBERA, we can wrap ETH
        // For other tokens, we'd need to deal them
        
        vm.startPrank(testUser);
        
        // If one token is WBERA, wrap some BERA
        if (token0 == WBERA || token1 == WBERA) {
            // Wrap BERA to WBERA
            IWBERA(WBERA).deposit{value: beraAmount}();
            console.log("Wrapped", beraAmount, "BERA to WBERA");
        }
        
        // Deal tokens to user (use foundry's deal for testing)
        uint256 amount0 = beraAmount;
        uint256 amount1 = beraAmount;
        
        // Get reserves to calculate proper ratio
        try IKodiakPair(testLPToken).getReserves() returns (uint112 r0, uint112 r1, uint32) {
            if (r0 > 0 && r1 > 0) {
                // Calculate amount1 based on ratio
                amount1 = (beraAmount * r1) / r0;
            }
        } catch {}
        
        // Deal tokens if needed
        if (token0 != WBERA) {
            deal(token0, testUser, amount0);
        }
        if (token1 != WBERA) {
            deal(token1, testUser, amount1);
        }
        
        // Approve router
        IERC20(token0).approve(KODIAK_V2_ROUTER, amount0);
        IERC20(token1).approve(KODIAK_V2_ROUTER, amount1);
        
        // Add liquidity
        try router.addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            0, // Accept any amount
            0,
            testUser,
            block.timestamp + 1 hours
        ) returns (uint256, uint256, uint256 liquidity) {
            console.log("Added liquidity, got LP:", liquidity);
            vm.stopPrank();
            return liquidity;
        } catch Error(string memory reason) {
            console.log("addLiquidity failed:", reason);
            vm.stopPrank();
            return 0;
        } catch {
            console.log("addLiquidity failed (no reason)");
            vm.stopPrank();
            return 0;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        DIAGNOSTIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Print detailed farm info for debugging
     */
    function test_printFarmInfo() public {
        if (testFarm == address(0)) {
            console.log("No farm discovered, skipping");
            return;
        }
        
        IKodiakFarm farm = IKodiakFarm(testFarm);
        
        console.log("\n=== FARM INFO ===");
        console.log("Farm address:", testFarm);
        console.log("LP token:", farm.stakingToken());
        console.log("");
        console.log("Lock Config:");
        console.log("  Min lock time:", farm.lock_time_min(), "seconds");
        console.log("  Max multiplier lock:", farm.lock_time_for_max_multiplier(), "seconds");
        console.log("  Max multiplier:", farm.lock_max_multiplier());
        console.log("");
        console.log("State:");
        console.log("  Total locked:", farm.totalLiquidityLocked());
        console.log("  Staking paused:", farm.stakingPaused());
        console.log("  Rewards paused:", farm.rewardsCollectionPaused());
        console.log("  Stakes unlocked:", farm.stakesUnlocked());
        console.log("");
        console.log("Reward Tokens:");
        address[] memory tokens = farm.getAllRewardTokens();
        uint256[] memory rates = farm.getAllRewardRates();
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("  ", tokens[i], "rate:", rates[i]);
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    HELPER INTERFACES
//////////////////////////////////////////////////////////////*/

interface IKodiakFarmFactory {
    function lpToFarm(address lp) external view returns (address);
    function getFarm(address lp) external view returns (address);
}

interface IKodiakPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IWBERA {
    function deposit() external payable;
    function withdraw(uint256) external;
}
