// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
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
import {IKodiakFactory} from "../../src/interfaces/IKodiakFactory.sol";
import {IKodiakRouter} from "../../src/interfaces/IKodiakRouter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/**
 * @title SimulateMainnetDeploy
 * @notice Full mainnet fork simulation — tests the entire deployment without spending gas or tokens.
 * @dev Uses vm.deal / vm.prank to give the deployer fake balances on the fork.
 *
 * Usage:
 *   forge script script/deployment/SimulateMainnetDeploy.s.sol:SimulateMainnetDeploy \
 *     --fork-url $BERACHAIN_RPC_URL -vvv
 */
contract SimulateMainnetDeploy is Test {

    function run() external {
        // --- Config from .env ---
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address honey = vm.envAddress("HONEY_ADDRESS");
        address ibgt = vm.envAddress("IBGT_ADDRESS");
        address ibgtPriceFeed = vm.envAddress("IBGT_PRICE_FEED");
        address infraredStaking = vm.envAddress("INFRARED_STAKING");
        address kodiakRouter = vm.envAddress("KODIAK_ROUTER");
        address kodiakFactory = vm.envAddress("KODIAK_FACTORY");
        uint256 epochLength = vm.envUint("EPOCH_LENGTH");
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        address multisig = vm.envAddress("MULTISIG_ADDRESS");

        uint256 bondVestingTerm = vm.envOr("BOND_VESTING_TERM", uint256(302_400));
        uint256 bondMaxPayout = vm.envOr("BOND_MAX_PAYOUT", uint256(100));
        uint256 bondDiscountRate = vm.envOr("BOND_DISCOUNT_RATE", uint256(500));
        uint256 bondMaxDebt = vm.envOr("BOND_MAX_DEBT", uint256(20_000e9));
        uint256 bondReferencePrice = vm.envOr("BOND_REFERENCE_PRICE", uint256(5e17));
        uint256 allocTreasury = vm.envOr("ALLOC_TREASURY", uint256(1_000_000_000e9));
        uint256 allocPresale = vm.envOr("ALLOC_PRESALE", uint256(110_000e9));
        uint256 allocIbgtBond = vm.envOr("ALLOC_IBGT_BOND", uint256(20_000_000e9));
        uint256 allocLpBond = vm.envOr("ALLOC_LP_BOND", uint256(20_000_000e9));
        uint256 maxMintRatioBps = vm.envOr("MAX_MINT_RATIO_BPS", uint256(12_000));
        uint256 maxMintPerDeposit = vm.envOr("MAX_MINT_PER_DEPOSIT", uint256(1_000_000e9));

        uint256 launchAmount = vm.envOr("LAUNCH_APIARY_AMOUNT", uint256(30_000e9));
        uint256 v2SeedApiary = vm.envOr("V2_SEED_APIARY", uint256(100e9));
        uint256 v2SeedHoney = vm.envOr("V2_SEED_HONEY", uint256(50000000000000000)); // 0.05 HONEY
        uint256 totalMint = launchAmount + v2SeedApiary;

        console.log("==============================================");
        console.log("  MAINNET FORK SIMULATION");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Block:   ", block.number);

        // --- Give deployer fake HONEY balance for V2 seed ---
        vm.startPrank(deployer);
        deal(honey, deployer, v2SeedHoney * 2);
        console.log("\nDeployer HONEY balance (dealt):", IERC20(honey).balanceOf(deployer));

        // =============================================
        // PHASE 0: Deploy Token + Seed Liquidity
        // =============================================
        console.log("\n--- PHASE 0: Deploy Token + Seed Liquidity ---");

        ApiaryToken apiary = new ApiaryToken(deployer);
        console.log("1. APIARY deployed:", address(apiary));

        apiary.setAllocationLimit(deployer, totalMint);
        apiary.mint(deployer, totalMint);
        console.log("2. Minted", totalMint, "APIARY");

        apiary.transfer(multisig, launchAmount);
        console.log("3. Sent", launchAmount, "APIARY to multisig for V3");

        address lpPair = IKodiakFactory(kodiakFactory).createPair(address(apiary), honey);
        console.log("4. V2 LP pair created:", lpPair);

        apiary.approve(kodiakRouter, v2SeedApiary);
        IERC20(honey).approve(kodiakRouter, v2SeedHoney);

        (uint256 amtA, uint256 amtB, uint256 liq) = IKodiakRouter(kodiakRouter).addLiquidity(
            address(apiary), honey,
            v2SeedApiary, v2SeedHoney,
            0, 0,
            deployer,
            block.timestamp + 300
        );
        console.log("5. V2 seeded - APIARY:", amtA);
        console.log("   HONEY:", amtB, "LP:", liq);

        // =============================================
        // PHASE 1: Deploy All Remaining Contracts
        // =============================================
        console.log("\n--- PHASE 1: Deploy Remaining Contracts ---");

        sApiary sApiaryToken = new sApiary(deployer);
        console.log("5. sApiary deployed:", address(sApiaryToken));

        ApiaryTreasury treasury = new ApiaryTreasury(deployer, address(apiary), ibgt, honey, lpPair);
        console.log("6. Treasury deployed:", address(treasury));

        uint256 firstEpochBlock = block.number + epochLength;
        ApiaryStaking staking = new ApiaryStaking(address(apiary), address(sApiaryToken), epochLength, 0, firstEpochBlock, deployer);
        console.log("7. Staking deployed:", address(staking));

        sApiaryToken.initialize(address(staking));
        console.log("8. sApiary initialized");

        ApiaryUniswapV2TwapOracle twapOracle = new ApiaryUniswapV2TwapOracle(lpPair, address(apiary));
        console.log("9. TWAP Oracle deployed:", address(twapOracle));

        ApiaryBondingCalculator bondCalc = new ApiaryBondingCalculator(address(apiary));
        console.log("10. Bonding Calculator deployed:", address(bondCalc));

        ApiaryBondDepository ibgtBond = new ApiaryBondDepository(
            address(apiary), ibgt, address(treasury), deployer, address(0), address(twapOracle), ibgtPriceFeed
        );
        console.log("11. iBGT Bond deployed:", address(ibgtBond));

        ApiaryBondDepository lpBond = new ApiaryBondDepository(
            address(apiary), lpPair, address(treasury), deployer, address(bondCalc), address(twapOracle), address(0)
        );
        console.log("12. LP Bond deployed:", address(lpBond));

        ApiaryPreSaleBond preSale = new ApiaryPreSaleBond(honey, address(treasury), deployer, merkleRoot);
        console.log("13. Pre-Sale Bond deployed:", address(preSale));

        ApiaryYieldManager yieldManager = new ApiaryYieldManager(
            address(apiary), honey, ibgt, address(treasury), address(1), address(2), deployer
        );
        console.log("14. Yield Manager deployed:", address(yieldManager));

        ApiaryInfraredAdapter infraredAdapter = new ApiaryInfraredAdapter(
            infraredStaking, ibgt, address(yieldManager), deployer
        );
        console.log("15. Infrared Adapter deployed:", address(infraredAdapter));

        ApiaryKodiakAdapter kodiakAdapter = new ApiaryKodiakAdapter(
            kodiakRouter, kodiakFactory, honey, address(apiary), address(treasury), address(yieldManager), deployer
        );
        console.log("16. Kodiak Adapter deployed:", address(kodiakAdapter));

        // =============================================
        // PHASE 1b: Configuration
        // =============================================
        console.log("\n--- Configuration ---");

        yieldManager.setInfraredAdapter(address(infraredAdapter));
        yieldManager.setKodiakAdapter(address(kodiakAdapter));
        console.log("17. YM adapters wired");

        apiary.setAllocationLimit(address(treasury), allocTreasury);
        apiary.setAllocationLimit(address(preSale), allocPresale);
        apiary.setAllocationLimit(address(ibgtBond), allocIbgtBond);
        apiary.setAllocationLimit(address(lpBond), allocLpBond);
        console.log("18. Minting allocations set");

        treasury.setReserveToken(ibgt, true);
        treasury.setLiquidityToken(lpPair, true);
        treasury.setMaxMintRatio(maxMintRatioBps);
        treasury.setMaxMintPerDeposit(maxMintPerDeposit);
        treasury.setReserveDepositor(address(ibgtBond), true);
        treasury.setLiquidityDepositor(address(lpBond), true);
        treasury.setReserveDepositor(address(preSale), true);
        treasury.setLiquidityDepositor(address(yieldManager), true);
        treasury.setYieldManager(address(yieldManager));
        treasury.setLPCalculator(address(bondCalc));
        treasury.setIbgtPriceFeed(ibgtPriceFeed);
        console.log("19. Treasury configured");

        ibgtBond.initializeBondTerms(bondVestingTerm, bondMaxPayout, bondDiscountRate, bondMaxDebt);
        lpBond.initializeBondTerms(bondVestingTerm, bondMaxPayout, bondDiscountRate, bondMaxDebt);
        console.log("20. Bond terms initialized");

        ibgtBond.setReferencePrice(bondReferencePrice);
        lpBond.setReferencePrice(bondReferencePrice);
        console.log("21. Reference prices set:", bondReferencePrice);

        preSale.setApiaryToken(address(apiary));
        console.log("22. Pre-Sale APIARY token set");

        sApiaryToken.setIndex(1e9);
        console.log("23. sApiary index set");

        yieldManager.setStakingContract(address(staking));
        yieldManager.setupApprovals();
        console.log("24. Yield Manager configured");

        // =============================================
        // PHASE 2: Ownership Transfer
        // =============================================
        console.log("\n--- Ownership Transfer ---");

        apiary.grantRole(apiary.DEFAULT_ADMIN_ROLE(), multisig);
        treasury.transferOwnership(multisig);
        staking.transferOwnership(multisig);
        sApiaryToken.transferOwnership(multisig);
        ibgtBond.transferOwnership(multisig);
        lpBond.transferOwnership(multisig);
        preSale.transferOwnership(multisig);
        yieldManager.transferOwnership(multisig);
        infraredAdapter.transferOwnership(multisig);
        kodiakAdapter.transferOwnership(multisig);
        console.log("25. Ownership transferred to multisig:", multisig);

        vm.stopPrank();

        // =============================================
        // Verification
        // =============================================
        console.log("\n--- Verification ---");

        require(apiary.hasRole(apiary.DEFAULT_ADMIN_ROLE(), multisig), "FAIL: multisig not admin");
        require(ibgtBond.referencePrice() == bondReferencePrice, "FAIL: iBGT referencePrice");
        require(lpBond.referencePrice() == bondReferencePrice, "FAIL: LP referencePrice");
        require(treasury.isReserveDepositor(address(ibgtBond)), "FAIL: iBGT bond not depositor");
        require(treasury.isLiquidityDepositor(address(lpBond)), "FAIL: LP bond not depositor");
        require(!ibgtBond.isLiquidityBond(), "FAIL: iBGT bond should not be LP");
        require(lpBond.isLiquidityBond(), "FAIL: LP bond should be LP");
        require(address(preSale.honey()) == honey, "FAIL: preSale honey");
        require(IERC20(lpPair).balanceOf(deployer) > 0, "FAIL: no LP tokens");
        console.log("All checks passed!");

        // =============================================
        // Summary
        // =============================================
        console.log("\n==============================================");
        console.log("  SIMULATION COMPLETE - ALL PASSED");
        console.log("==============================================");
        console.log("APIARY:          ", address(apiary));
        console.log("sAPIARY:         ", address(sApiaryToken));
        console.log("Treasury:        ", address(treasury));
        console.log("Staking:         ", address(staking));
        console.log("TWAP Oracle:     ", address(twapOracle));
        console.log("Bond Calculator: ", address(bondCalc));
        console.log("iBGT Bond:       ", address(ibgtBond));
        console.log("LP Bond:         ", address(lpBond));
        console.log("Pre-Sale:        ", address(preSale));
        console.log("Yield Manager:   ", address(yieldManager));
        console.log("Infrared Adapter:", address(infraredAdapter));
        console.log("Kodiak Adapter:  ", address(kodiakAdapter));
        console.log("LP Pair:         ", lpPair);
        console.log("==============================================");
    }
}
