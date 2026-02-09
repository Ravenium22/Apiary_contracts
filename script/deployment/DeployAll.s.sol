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
import {ApiaryBondingCalculator} from "../../src/ApiaryBondingCalculator.sol";

/**
 * @title DeployAll
 * @notice Complete deployment script for Apiary Protocol on Berachain
 * @dev Deploys all contracts in sequence with proper linking.
 *      All external addresses are read from environment variables — no hardcoded addresses.
 *
 * IMPORTANT: This script deploys core contracts first. The TWAP Oracle and Bond contracts
 * that depend on LP pair will need an actual LP pair address. You can either:
 * 1. Deploy in phases: First deploy core, create LP, then deploy bonds
 * 2. Use an existing LP pair address via LP_PAIR_ADDRESS env var
 *
 * Usage:
 *   # Dry run (simulation)
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url $BERACHAIN_RPC_URL \
 *     --private-key $PRIVATE_KEY
 *
 *   # With broadcast (actual deployment)
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url $BERACHAIN_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 *   # With verification
 *   forge script script/deployment/DeployAll.s.sol:DeployAll \
 *     --rpc-url $BERACHAIN_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BERASCAN_API_KEY
 *
 * Required Environment Variables (set in .env):
 *   - PRIVATE_KEY: Deployer private key
 *   - IBGT_ADDRESS: iBGT token address
 *   - HONEY_ADDRESS: HONEY stablecoin address
 *   - INFRARED_STAKING: Infrared staking contract address
 *   - KODIAK_ROUTER: Kodiak DEX router address
 *   - KODIAK_FACTORY: Kodiak DEX factory address
 *   - EPOCH_LENGTH: Epoch length in blocks
 *   - MERKLE_ROOT: Pre-sale whitelist merkle root (optional, defaults to placeholder)
 *
 * Optional Environment Variables:
 *   - LP_PAIR_ADDRESS: Existing APIARY/HONEY LP pair (if created beforehand)
 *   - BERASCAN_API_KEY: For contract verification
 */
contract DeployAll is Script {

    // Berachain mainnet chain ID
    uint256 constant BERACHAIN_MAINNET = 80094;

    // ============ RESOLVED CONFIG (set in _loadConfig) ============
    // External addresses
    address internal IBGT_ADDRESS;
    address internal IBGT_PRICE_FEED;
    address internal HONEY_ADDRESS;
    address internal INFRARED_STAKING;
    address internal KODIAK_ROUTER;
    address internal KODIAK_FACTORY;
    // Staking
    uint256 internal EPOCH_LENGTH;
    uint256 internal FIRST_EPOCH_NUMBER;
    // Pre-sale
    bytes32 internal MERKLE_ROOT;
    // Bond terms
    uint256 internal BOND_VESTING_TERM;
    uint256 internal BOND_MAX_PAYOUT;
    uint256 internal BOND_DISCOUNT_RATE;
    uint256 internal BOND_MAX_DEBT;
    // Allocation limits (APIARY token minting caps)
    uint256 internal ALLOC_TREASURY;
    uint256 internal ALLOC_PRESALE;
    uint256 internal ALLOC_IBGT_BOND;
    uint256 internal ALLOC_LP_BOND;
    // Treasury
    uint256 internal MAX_MINT_RATIO_BPS;
    uint256 internal MAX_MINT_PER_DEPOSIT;
    // sApiary
    uint256 internal SAPIARY_INITIAL_INDEX;
    // Ownership
    address internal MULTISIG;
    
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
        address bondingCalculator;
        address yieldManager;
        address infraredAdapter;
        address kodiakAdapter;
        address apiaryHoneyLP;
    }
    
    function run() external returns (DeployedAddresses memory deployed) {
        _loadConfig();

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
        console.log("");
        console.log("External addresses:");
        console.log("  iBGT:        ", IBGT_ADDRESS);
        console.log("  HONEY:       ", HONEY_ADDRESS);
        console.log("  Infrared:    ", INFRARED_STAKING);
        console.log("  Kodiak Rtr:  ", KODIAK_ROUTER);
        console.log("  Kodiak Fct:  ", KODIAK_FACTORY);
        console.log("  Epoch Length:", EPOCH_LENGTH);
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
        
        // ============ STEP 8: Deploy Bonding Calculator ============
        console.log("STEP 8: Deploying Bonding Calculator...");
        ApiaryBondingCalculator bondingCalc = new ApiaryBondingCalculator(deployed.apiary);
        deployed.bondingCalculator = address(bondingCalc);
        console.log("  Bonding Calculator:", deployed.bondingCalculator);

        // ============ STEP 9: Deploy Bond Contracts ============
        console.log("STEP 9: Deploying Bond Contracts...");

        if (hasRealLP) {
            // iBGT Bond (uses iBGT/USD price feed for correct valuation)
            ApiaryBondDepository ibgtBond = new ApiaryBondDepository(
                deployed.apiary,
                IBGT_ADDRESS,
                deployed.treasury,
                deployer,
                address(0), // No bond calculator for reserve token
                deployed.twapOracle,
                IBGT_PRICE_FEED
            );
            deployed.ibgtBond = address(ibgtBond);
            console.log("  iBGT Bond:", deployed.ibgtBond);

            // LP Bond (uses bonding calculator for LP valuation, no iBGT price feed)
            ApiaryBondDepository lpBond = new ApiaryBondDepository(
                deployed.apiary,
                deployed.apiaryHoneyLP,
                deployed.treasury,
                deployer,
                deployed.bondingCalculator,
                deployed.twapOracle,
                address(0) // LP bonds don't need iBGT price feed
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
            MERKLE_ROOT
        );
        deployed.preSaleBond = address(preSaleBond);
        console.log("  Pre-Sale Bond:", deployed.preSaleBond);
        
        // ============ STEP 10: Deploy Yield Manager & Adapters ============
        console.log("STEP 10: Deploying Yield Manager & Adapters...");
        
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

        // Wire real adapters into Yield Manager (replaces address(1)/address(2) placeholders)
        yieldManager.setInfraredAdapter(deployed.infraredAdapter);
        yieldManager.setKodiakAdapter(deployed.kodiakAdapter);
        console.log("  Yield Manager adapters updated");

        // ============ STEP 11: APIARY Minting Allocations (B-7) ============
        console.log("STEP 11: Setting APIARY minting allocations...");
        apiary.setAllocationLimit(deployed.treasury, ALLOC_TREASURY);
        console.log("  Treasury allocation set");
        apiary.setAllocationLimit(deployed.preSaleBond, ALLOC_PRESALE);
        console.log("  Pre-Sale allocation set");
        if (deployed.ibgtBond != address(0)) {
            apiary.setAllocationLimit(deployed.ibgtBond, ALLOC_IBGT_BOND);
            console.log("  iBGT Bond allocation set");
        }
        if (deployed.lpBond != address(0)) {
            apiary.setAllocationLimit(deployed.lpBond, ALLOC_LP_BOND);
            console.log("  LP Bond allocation set");
        }

        // ============ STEP 12: Treasury Configuration (H-1) ============
        console.log("STEP 12: Configuring treasury...");
        treasury.setReserveToken(IBGT_ADDRESS, true);
        console.log("  iBGT set as reserve token");
        if (hasRealLP) {
            treasury.setLiquidityToken(deployed.apiaryHoneyLP, true);
            console.log("  LP set as liquidity token");
        }
        treasury.setMaxMintRatio(MAX_MINT_RATIO_BPS);
        console.log("  Max mint ratio:", MAX_MINT_RATIO_BPS, "bps");
        treasury.setMaxMintPerDeposit(MAX_MINT_PER_DEPOSIT);
        console.log("  Max mint per deposit set");

        // Depositor roles
        if (deployed.ibgtBond != address(0)) {
            treasury.setReserveDepositor(deployed.ibgtBond, true);
            console.log("  iBGT Bond: reserve depositor");
        }
        if (deployed.lpBond != address(0)) {
            treasury.setLiquidityDepositor(deployed.lpBond, true);
            console.log("  LP Bond: liquidity depositor");
        }
        treasury.setReserveDepositor(deployed.preSaleBond, true);
        console.log("  Pre-Sale Bond: reserve depositor");
        treasury.setLiquidityDepositor(address(yieldManager), true);
        console.log("  Yield Manager: liquidity depositor");
        treasury.setYieldManager(deployed.yieldManager);
        console.log("  Yield manager set in treasury");
        treasury.setLPCalculator(deployed.bondingCalculator);
        console.log("  LP calculator set:", deployed.bondingCalculator);
        treasury.setIbgtPriceFeed(IBGT_PRICE_FEED);
        console.log("  iBGT price feed set:", IBGT_PRICE_FEED);

        // ============ STEP 13: Initialize Bond Terms (B-5) ============
        console.log("STEP 13: Initializing bond terms...");
        if (deployed.ibgtBond != address(0)) {
            ApiaryBondDepository(deployed.ibgtBond).initializeBondTerms(
                BOND_VESTING_TERM,
                BOND_MAX_PAYOUT,
                BOND_DISCOUNT_RATE,
                BOND_MAX_DEBT
            );
            console.log("  iBGT Bond terms initialized");
        }
        if (deployed.lpBond != address(0)) {
            ApiaryBondDepository(deployed.lpBond).initializeBondTerms(
                BOND_VESTING_TERM,
                BOND_MAX_PAYOUT,
                BOND_DISCOUNT_RATE,
                BOND_MAX_DEBT
            );
            console.log("  LP Bond terms initialized");
        }

        // ============ STEP 14: Set APIARY Token on Pre-Sale (B-6) ============
        console.log("STEP 14: Setting APIARY token on Pre-Sale...");
        preSaleBond.setApiaryToken(deployed.apiary);
        console.log("  Pre-Sale APIARY token set");

        // ============ STEP 15: sApiary Index + Staking Config (M-1) ============
        console.log("STEP 15: Configuring sApiary and Staking...");
        sApiaryToken.setIndex(SAPIARY_INITIAL_INDEX);
        console.log("  sApiary index set");
        // Note: staking.setContract(DISTRIBUTOR, addr) deferred until a distributor is deployed

        // ============ STEP 16: Yield Manager Config (H-3 + M-1) ============
        console.log("STEP 16: Configuring Yield Manager...");
        yieldManager.setStakingContract(deployed.staking);
        console.log("  YM staking contract set");
        yieldManager.setupApprovals();
        console.log("  YM token approvals configured");

        // ============ STEP 17: Ownership Transfer to Multisig (H-2) ============
        if (MULTISIG != address(0)) {
            console.log("STEP 17: Transferring ownership to multisig...");
            console.log("  Multisig:", MULTISIG);

            // ApiaryToken uses AccessControl — grant admin role to multisig
            apiary.grantRole(apiary.DEFAULT_ADMIN_ROLE(), MULTISIG);
            console.log("  APIARY: admin role granted");

            // Ownable2Step contracts — initiate transfer (multisig must acceptOwnership)
            treasury.transferOwnership(MULTISIG);
            console.log("  Treasury: transfer initiated");
            staking.transferOwnership(MULTISIG);
            console.log("  Staking: transfer initiated");
            sApiaryToken.transferOwnership(MULTISIG);
            console.log("  sApiary: transfer initiated");

            if (deployed.ibgtBond != address(0)) {
                ApiaryBondDepository(deployed.ibgtBond).transferOwnership(MULTISIG);
                console.log("  iBGT Bond: transfer initiated");
            }
            if (deployed.lpBond != address(0)) {
                ApiaryBondDepository(deployed.lpBond).transferOwnership(MULTISIG);
                console.log("  LP Bond: transfer initiated");
            }
            preSaleBond.transferOwnership(MULTISIG);
            console.log("  Pre-Sale: transfer initiated");
            yieldManager.transferOwnership(MULTISIG);
            console.log("  Yield Manager: transfer initiated");
            infraredAdapter.transferOwnership(MULTISIG);
            console.log("  Infrared Adapter: transfer initiated");
            kodiakAdapter.transferOwnership(MULTISIG);
            console.log("  Kodiak Adapter: transfer initiated");

            console.log("  NOTE: Multisig must call acceptOwnership() on each contract");
        } else {
            console.log("STEP 17: Skipping ownership transfer (no MULTISIG_ADDRESS set)");
        }

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
        console.log("  Bond Calc:    ", deployed.bondingCalculator);
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
        console.log("  CONFIGURATION APPLIED:");
        console.log("==============================================");
        console.log("  Bond Vesting Term:", BOND_VESTING_TERM, "blocks");
        console.log("  Bond Max Payout:  ", BOND_MAX_PAYOUT, "(/1000)");
        console.log("  Bond Discount:    ", BOND_DISCOUNT_RATE, "bps");
        console.log("  Bond Max Debt:    ", BOND_MAX_DEBT);
        console.log("  Max Mint Ratio:   ", MAX_MINT_RATIO_BPS, "bps");
        console.log("  sApiary Index:    ", SAPIARY_INITIAL_INDEX);
        if (MULTISIG != address(0)) {
            console.log("  Multisig:         ", MULTISIG);
        }
        console.log("");
        console.log("==============================================");
        console.log("  REMAINING STEPS:");
        console.log("==============================================");
        if (deployed.twapOracle == address(0)) {
            console.log("1. Create APIARY/HONEY LP pool on Kodiak");
            console.log("2. Add initial liquidity to the pool");
            console.log("3. Deploy TWAP Oracle + Bond contracts with LP address");
        }
        if (MULTISIG != address(0)) {
            console.log("4. Multisig calls acceptOwnership() on all contracts");
            console.log("5. Deployer renounces APIARY DEFAULT_ADMIN_ROLE");
        }
        console.log("6. Create Kodiak farm, run 08_ConfigureKodiakFarm.s.sol");
        console.log("7. Start pre-sale when ready");
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

    /**
     * @notice Load and validate all required configuration from environment variables
     * @dev Reverts with descriptive message if any required variable is missing or zero
     */
    function _loadConfig() internal {
        console.log("=== Loading configuration from environment ===");

        // -- External addresses --
        IBGT_ADDRESS = _requireEnvAddress("IBGT_ADDRESS");
        IBGT_PRICE_FEED = _requireEnvAddress("IBGT_PRICE_FEED");
        HONEY_ADDRESS = _requireEnvAddress("HONEY_ADDRESS");
        INFRARED_STAKING = _requireEnvAddress("INFRARED_STAKING");
        KODIAK_ROUTER = _requireEnvAddress("KODIAK_ROUTER");
        KODIAK_FACTORY = _requireEnvAddress("KODIAK_FACTORY");

        // -- Staking --
        EPOCH_LENGTH = vm.envUint("EPOCH_LENGTH");
        require(EPOCH_LENGTH > 0, "DeployAll: EPOCH_LENGTH must be > 0");
        FIRST_EPOCH_NUMBER = vm.envOr("FIRST_EPOCH_NUMBER", uint256(0));

        // -- Pre-sale merkle root --
        try vm.envBytes32("MERKLE_ROOT") returns (bytes32 root) {
            require(root != bytes32(0), "DeployAll: MERKLE_ROOT must be non-zero");
            MERKLE_ROOT = root;
        } catch {
            MERKLE_ROOT = keccak256("APIARY_PRESALE_PLACEHOLDER");
            console.log("  MERKLE_ROOT: using placeholder (set before pre-sale!)");
        }

        // -- Bond terms (required when LP exists, checked at use-site) --
        // MINIMUM_VESTING_TERM = 17280, max payout 1000 (1%), max discount 5000 (50%)
        BOND_VESTING_TERM = vm.envOr("BOND_VESTING_TERM", uint256(17_280));
        require(BOND_VESTING_TERM >= 17_280, "DeployAll: BOND_VESTING_TERM < 17280");
        BOND_MAX_PAYOUT = vm.envOr("BOND_MAX_PAYOUT", uint256(1));
        require(BOND_MAX_PAYOUT > 0 && BOND_MAX_PAYOUT <= 1000, "DeployAll: BOND_MAX_PAYOUT out of range 1-1000");
        BOND_DISCOUNT_RATE = vm.envOr("BOND_DISCOUNT_RATE", uint256(500));
        require(BOND_DISCOUNT_RATE <= 5000, "DeployAll: BOND_DISCOUNT_RATE > 5000");
        BOND_MAX_DEBT = vm.envOr("BOND_MAX_DEBT", uint256(100_000e9));
        require(BOND_MAX_DEBT > 0, "DeployAll: BOND_MAX_DEBT must be > 0");

        // -- Allocation limits (APIARY minting caps per minter, 9 decimals) --
        ALLOC_TREASURY = vm.envOr("ALLOC_TREASURY", uint256(1_000_000_000e9));
        ALLOC_PRESALE = vm.envOr("ALLOC_PRESALE", uint256(110_000e9));
        ALLOC_IBGT_BOND = vm.envOr("ALLOC_IBGT_BOND", uint256(20_000_000e9));
        ALLOC_LP_BOND = vm.envOr("ALLOC_LP_BOND", uint256(20_000_000e9));

        // -- Treasury safety limits (HIGH-01 fix parameters) --
        MAX_MINT_RATIO_BPS = vm.envOr("MAX_MINT_RATIO_BPS", uint256(12_000));
        require(MAX_MINT_RATIO_BPS <= 20_000, "DeployAll: MAX_MINT_RATIO_BPS > 20000");
        MAX_MINT_PER_DEPOSIT = vm.envOr("MAX_MINT_PER_DEPOSIT", uint256(1_000_000e9));

        // -- sApiary initial index (1e9 = 1.0, set once) --
        SAPIARY_INITIAL_INDEX = vm.envOr("SAPIARY_INITIAL_INDEX", uint256(1e9));
        require(SAPIARY_INITIAL_INDEX > 0, "DeployAll: SAPIARY_INITIAL_INDEX must be > 0");

        // -- Multisig for ownership transfer (optional, skip transfer if zero) --
        MULTISIG = vm.envOr("MULTISIG_ADDRESS", address(0));

        // -- Mainnet safety --
        if (block.chainid == BERACHAIN_MAINNET) {
            console.log("  MAINNET DEPLOYMENT DETECTED (chain 80094)");
            require(
                MERKLE_ROOT != keccak256("APIARY_PRESALE_PLACEHOLDER"),
                "DeployAll: placeholder merkle root not allowed on mainnet"
            );
            require(MULTISIG != address(0), "DeployAll: MULTISIG_ADDRESS required on mainnet");
        }

        console.log("  Config OK\n");
    }

    /**
     * @notice Read a required address env var, revert if missing or zero
     */
    function _requireEnvAddress(string memory name) internal view returns (address addr) {
        addr = vm.envAddress(name);
        require(addr != address(0), string.concat("DeployAll: ", name, " is zero address"));
    }
}
