// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { BeraReserveToken } from "src/BeraReserveToken.sol";
import { Test, console2 } from "forge-std/Test.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "../../src/interfaces/IUniswapV2Factory.sol";
import { sBeraReserve } from "../../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../../src/Staking.sol";
import { BeraReserveTreasury } from "../../src/Treasury.sol";
import { BeraReserveBondDepositoryV2 } from "../../src/BeraReserveBondDepositoryV2.sol";
import { StakingWarmup } from "../../src/StakingWarmup.sol";
import { BeraReserveBondingCalculator } from "../../src/BeraReserveBondingCalculator.sol";
import { BeraReserveFeeDistributor } from "src/BeraReserveFeeDistributor.sol";
import { BeraReserveLockUp } from "src/BeraReserveLockUp.sol";
import { StakingHelper } from "../../src/StakingHelper.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BeraReservePreBondClaims } from "src/BeraReservePreBondClaims.sol";
import { DistributorV2 } from "src/StakingDistributorV2.sol";
import { BeraReserveTreasuryV2 } from "src/BeraReserveTreasuryV2.sol";
import { BeraReserveBondingCalculator } from "src/BeraReserveBondingCalculator.sol";
import { BeraReserveUniswapV2TwapOracle } from "src/utils/BeraReserveUniswapV2TwapOracle.sol";

contract BeraReserveBaseTestV2 is Test {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    address public constant BERA_RESERVE_POL = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_TEAM = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    address public constant BERA_RESERVE_REWARD_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_AIRDROP_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_LIQUIDITY_WALLET = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    uint256 internal constant LIQUIDITY_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint256 internal constant AIRDROP_TOTAL_BRR_AMOUNT = 24_000e9; //24,000 (12% of total supply)
    uint256 internal constant REWARDS_TOTAL_BRR_AMOUNT = 26_000e9; // 26,000 BRR (13% of total supply)
    uint256 internal constant MARKETING_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint256 internal constant TEAM_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    uint256 internal constant SEED_ROUND_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    uint256 public constant VESTING_TOTAL_BRR_AMOUNT = 90_000e9;
    uint256 public constant TREASURY_TOTAL_BRR_AMOUNT = 40_000e9;
    uint256 public constant PRE_BONDS_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    address public constant USDC_TOKEN = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address public constant BOND_PRESALE_CONTRACT = 0xb90200C9b292e5a1C348baeb050c1dAF2D3f739a;
    address public constant BRR_HONEY_PAIR = 0xa8f9d7Ea6Baa104454bbcAD647A4c8b17778969C;

    //!Testing Only
    address public HONEY_WHALE = 0xD6D83e479359766f21A63b20d6AF43A138356EbA;
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022);
    address public HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address public BERA_RESERVE_WORKER = 0x2542909977999800000000000000000000000000;
    address public USDC_WHALE = 0xAB961d7C42BBcd454A54b342Bd191a8f090219E6;
    address public ALICE = makeAddr("ALICE");
    address public BOB = makeAddr("BOB");
    address public CHARLIE = makeAddr("CHARLIE");
    address public PROTOCOL_TREASURY = makeAddr("PROTOCOL_TREASURY");
    //!Testing purposes

    BeraReserveToken public beraReserveToken;
    sBeraReserve public sBeraReserveToken;
    BeraReserveStaking.CONTRACTS public contracts;
    BeraReserveStaking public staking;
    StakingWarmup public warmup;
    BeraReserveFeeDistributor public feeDistributor;
    BeraReserveLockUp public lockUp;
    BeraReservePreBondClaims public preSaleClaims;
    DistributorV2 public distributorV2;
    BeraReserveTreasuryV2 public treasury;
    BeraReserveBondingCalculator public bondingCalculator;
    BeraReserveBondDepositoryV2 public usdcDepository;
    BeraReserveBondDepositoryV2 public bRRHoneyDepository;
    BeraReserveUniswapV2TwapOracle public simpleTwap;

    address public uniswapV2Pair;

    function setUp() public virtual {
        uint256 berachainFork = vm.createFork(vm.envString("BERACHAIN_RPC_URL"));

        vm.selectFork(berachainFork);

        vm.startPrank(BERA_RESERVE_ADMIN);

        beraReserveToken = new BeraReserveToken(BERA_RESERVE_ADMIN, BERA_RESERVE_REWARD_WALLET, BERA_RESERVE_AIRDROP_WALLET);

        sBeraReserveToken = new sBeraReserve();

        staking = new BeraReserveStaking(
            address(beraReserveToken),
            address(sBeraReserveToken),
            14_400, //epochLength
            1, //firstEpochNumber
            block.number + 14_400
        );

        lockUp = new BeraReserveLockUp(BERA_RESERVE_ADMIN, address(beraReserveToken), address(sBeraReserveToken), address(staking));

        distributorV2 = new DistributorV2(
            address(beraReserveToken),
            14_400, //epochLength
            block.number + 14_400 //nextEpochBlock
        );

        warmup = new StakingWarmup(address(staking), address(sBeraReserveToken));

        feeDistributor = new BeraReserveFeeDistributor(
            BERA_RESERVE_ADMIN,
            PROTOCOL_TREASURY,
            BERA_RESERVE_POL,
            BERA_RESERVE_TEAM,
            address(beraReserveToken)
        );

        preSaleClaims = new BeraReservePreBondClaims(address(beraReserveToken), BERA_RESERVE_ADMIN, BOND_PRESALE_CONTRACT);

        bondingCalculator = new BeraReserveBondingCalculator(address(beraReserveToken));

        ///@notice configs

        beraReserveToken.setTwentyFivePercentBelowFees(1_600);

        beraReserveToken.setTenPercentBelowFees(1_200);

        beraReserveToken.setBelowTreasuryValueFees(1_000);

        ///@dev set mcap in usdc
        beraReserveToken.setMarketCap(200_000e6);

        beraReserveToken.setStaking(address(staking));

        beraReserveToken.setDecayRatio(0);

        beraReserveToken.setProtocolTreasury(PROTOCOL_TREASURY);

        contracts = BeraReserveStaking.CONTRACTS.WARMUP;

        staking.setContract(contracts, address(warmup));

        contracts = BeraReserveStaking.CONTRACTS.DISTRIBUTOR;

        staking.setContract(contracts, address(distributorV2));

        contracts = BeraReserveStaking.CONTRACTS.LOCKER;

        staking.setContract(contracts, address(lockUp));

        distributorV2.addRecipient(address(staking), 4_300); // the recipient gets 1% of the distributable BRR per epoch.

        sBeraReserveToken.initialize(address(staking));

        sBeraReserveToken.setIndex(1e9);

        //sBeraReserveToken.setTreasury(address(treasury));

        beraReserveToken.setFeeDistributor(address(feeDistributor));

        ///@dev exclude accounts from fees and decay
        beraReserveToken.excludeAccountFromFeesAndDecay(address(staking), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(feeDistributor), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(preSaleClaims), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(lockUp), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(distributorV2), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_POL, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_TEAM, true);

        //set mint allocations
        beraReserveToken.setAllocationLimit(address(lockUp), VESTING_TOTAL_BRR_AMOUNT);
        beraReserveToken.setAllocationLimit(address(preSaleClaims), PRE_BONDS_TOTAL_BRR_AMOUNT);
        beraReserveToken.setAllocationLimit(address(distributorV2), type(uint256).max);

        lockUp.mintAndStakeBRR();

        preSaleClaims.mintBRR();

        vm.stopPrank();

        createPairAndAddLiquidity();
    }

    /**
     * HELPER FUNCTIONS
     */
    function createPairAndAddLiquidity() public {
        vm.startPrank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_LIQUIDITY_WALLET, 10_000e18);
        vm.stopPrank();

        //add liquidity
        vm.startPrank(BERA_RESERVE_LIQUIDITY_WALLET);

        //create pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouter.factory()).createPair(address(beraReserveToken), HONEY_TOKEN);

        beraReserveToken.approve(address(uniswapRouter), 10_000e9);
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 10_000e18);
        uniswapRouter.addLiquidity(
            address(beraReserveToken),
            HONEY_TOKEN,
            10_000e9,
            10_000e18,
            0,
            0,
            BERA_RESERVE_LIQUIDITY_WALLET,
            block.timestamp + 1000
        );
        vm.stopPrank();

        vm.startPrank(BERA_RESERVE_ADMIN);

        beraReserveToken.updateUniswapV2Pair(uniswapV2Pair);

        vm.stopPrank();

        vm.startPrank(BERA_RESERVE_ADMIN);

        treasury = new BeraReserveTreasuryV2(BERA_RESERVE_ADMIN, address(beraReserveToken), USDC_TOKEN, uniswapV2Pair);

        treasury.setReservesManager(BERA_RESERVE_ADMIN);

        simpleTwap = new BeraReserveUniswapV2TwapOracle(uniswapV2Pair);

        usdcDepository = new BeraReserveBondDepositoryV2(
            address(beraReserveToken),
            USDC_TOKEN,
            address(treasury),
            address(feeDistributor),
            BERA_RESERVE_ADMIN,
            address(0),
            address(simpleTwap)
        );

        bRRHoneyDepository = new BeraReserveBondDepositoryV2(
            address(beraReserveToken),
            uniswapV2Pair,
            address(treasury),
            address(feeDistributor),
            BERA_RESERVE_ADMIN,
            address(bondingCalculator),
            address(simpleTwap)
        );

        treasury.setReserveDepositor(address(usdcDepository), true);

        treasury.setLiquidityDepositor(address(bRRHoneyDepository), true);

        treasury.setLiquidityToken(uniswapV2Pair, true);

        beraReserveToken.setAllocationLimit(address(treasury), 40_000e9);

        vm.stopPrank();
    }
}
