// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { BeraReserveToken } from "src/BeraReserveToken.sol";
import { Test, console } from "forge-std/Test.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "../../src/interfaces/IUniswapV2Factory.sol";
import { sBeraReserve } from "../../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../../src/Staking.sol";
import { BeraReserveTreasury } from "../../src/Treasury.sol";
import { BeraReserveBondDepository } from "../../src/BondDepository.sol";
import { StakingWarmup } from "../../src/StakingWarmup.sol";
import { BeraReserveBondingCalculator } from "../../src/BeraReserveBondingCalculator.sol";
import { BeraReserveFeeDistributor } from "src/BeraReserveFeeDistributor.sol";
import { BeraReserveLockUp } from "src/BeraReserveLockUp.sol";
import { Distributor } from "../../src/StakingDistributor.sol";
import { StakingHelper } from "../../src/StakingHelper.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BeraReservePreBondClaims } from "src/BeraReservePreBondClaims.sol";

contract BeraReserveBaseTest is Test {
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

    //!Testing Only
    address public HONEY_WHALE = 0xD6D83e479359766f21A63b20d6AF43A138356EbA;
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022);
    address public HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address public BERA_RESERVE_WORKER = 0x2542909977999800000000000000000000000000;
    address public USDC_WHALE = 0xAB961d7C42BBcd454A54b342Bd191a8f090219E6;
    address public ALICE = makeAddr("ALICE");
    address public BOB = makeAddr("BOB");
    address public CHARLIE = makeAddr("CHARLIE");
    address public DEBTOR = makeAddr("DEBTOR");
    address public PROTOCOL_TREASURY = makeAddr("PROTOCOL_TREASURY");
    //!Testing purposes

    BeraReserveToken public beraReserveToken;
    sBeraReserve public sBeraReserveToken;
    BeraReserveStaking public staking;
    BeraReserveStaking.CONTRACTS public contracts;
    BeraReserveTreasury public treasury;
    BeraReserveBondDepository public usdcBondDepository;
    StakingWarmup public warmup;
    BeraReserveBondingCalculator public bondingCalculator;
    Distributor public distributor;
    BeraReserveFeeDistributor public feeDistributor;
    BeraReserveLockUp public lockUp;
    BeraReservePreBondClaims public preSaleClaims;

    address public uniswapV2Pair;

    function setUp() public virtual {
        uint256 berachainFork = vm.createFork(vm.envString("BERACHAIN_RPC_URL"));

        vm.selectFork(berachainFork);

        vm.startPrank(BERA_RESERVE_ADMIN);

        beraReserveToken =
            new BeraReserveToken(BERA_RESERVE_ADMIN, BERA_RESERVE_REWARD_WALLET, BERA_RESERVE_AIRDROP_WALLET);

        sBeraReserveToken = new sBeraReserve();

        staking = new BeraReserveStaking(
            address(beraReserveToken),
            address(sBeraReserveToken),
            14_400, //epochLength
            0, //firstEpochNumber
            block.number + 14_400
        );

        lockUp = new BeraReserveLockUp(
            BERA_RESERVE_ADMIN, address(beraReserveToken), address(sBeraReserveToken), address(staking)
        );

        treasury = new BeraReserveTreasury(
            address(beraReserveToken),
            USDC_TOKEN,
            1 //blocksNeededForQueue
        );

        distributor = new Distributor(
            address(treasury),
            address(beraReserveToken),
            14_400, //epochLength
            block.number + 14_400 //nextEpochBlock
        );

        warmup = new StakingWarmup(address(staking), address(sBeraReserveToken));

        feeDistributor = new BeraReserveFeeDistributor(
            BERA_RESERVE_ADMIN, PROTOCOL_TREASURY, BERA_RESERVE_POL, BERA_RESERVE_TEAM, address(beraReserveToken)
        );

        usdcBondDepository = new BeraReserveBondDepository(
            address(beraReserveToken),
            USDC_TOKEN,
            address(treasury),
            address(feeDistributor),
            address(0) //if not LP tokens
        );

        preSaleClaims =
            new BeraReservePreBondClaims(address(beraReserveToken), BERA_RESERVE_ADMIN, BOND_PRESALE_CONTRACT);

        ///@notice configs
        beraReserveToken.setVault(address(treasury));

        beraReserveToken.setTwentyFivePercentBelowFees(1_600);

        beraReserveToken.setTenPercentBelowFees(1_200);

        beraReserveToken.setBelowTreasuryValueFees(1_000);

        ///@dev set mcap in usdc
        beraReserveToken.setMarketCap(200_000e6);

        beraReserveToken.setStaking(address(staking));

        beraReserveToken.setTreasuryAllocation(40_000e9);

        beraReserveToken.setProtocolTreasury(PROTOCOL_TREASURY);

        contracts = BeraReserveStaking.CONTRACTS.WARMUP;

        staking.setContract(contracts, address(warmup));

        contracts = BeraReserveStaking.CONTRACTS.DISTRIBUTOR;

        staking.setContract(contracts, address(distributor));

        contracts = BeraReserveStaking.CONTRACTS.LOCKER;

        staking.setContract(contracts, address(lockUp));

        distributor.addRecipient(address(staking), 4_300); // the recipient gets 1% of the distributable BRR per epoch.

        usdcBondDepository.setStaking(address(staking), false);

        bondingCalculator = new BeraReserveBondingCalculator(address(beraReserveToken));

        usdcBondDepository.initializeBondTerms(
            2, //controlVariable
            216_000, //vestingTerm
            101, //minimumPrice //$1.01
            500, //maxPayout(0.5%)
            10, //fee (1%)
            40_000e9,
            0
        );

        sBeraReserveToken.initialize(address(staking));

        sBeraReserveToken.setIndex(1e9);

        BeraReserveTreasury.MANAGING _managing = BeraReserveTreasury.MANAGING.RESERVEDEPOSITOR;

        BeraReserveTreasury.MANAGING distributorManager = BeraReserveTreasury.MANAGING.REWARDMANAGER;

        BeraReserveTreasury.MANAGING sBRR_ = BeraReserveTreasury.MANAGING.SBRR;

        treasury.queue(distributorManager, address(distributor));

        treasury.queue(sBRR_, address(sBeraReserveToken));

        treasury.queue(_managing, address(usdcBondDepository));

        beraReserveToken.setFeeDistributor(address(feeDistributor));

        ///@dev exclude accounts from fees and decay
        beraReserveToken.excludeAccountFromFeesAndDecay(address(usdcBondDepository), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(staking), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(feeDistributor), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(preSaleClaims), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(lockUp), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(treasury), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_POL, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_TEAM, true);

        //set mint allocations
        beraReserveToken.setAllocationLimit(address(lockUp), VESTING_TOTAL_BRR_AMOUNT);
        beraReserveToken.setAllocationLimit(address(preSaleClaims), TREASURY_TOTAL_BRR_AMOUNT);

        lockUp.mintAndStakeBRR();

        preSaleClaims.mintBRR();

        //!Commented out for testing.
        // preSaleClaims.pause();

        //Vest team , marketing and presalers.
        _vestTeam();
        _vestMarketing();
        _vestPresalers();

        vm.roll(block.number + 2);

        treasury.toggle(sBRR_, address(sBeraReserveToken), address(0));

        treasury.toggle(_managing, address(usdcBondDepository), address(0));

        treasury.toggle(distributorManager, address(distributor), address(0));

        assertEq(beraReserveToken.totalSupply(), 160_000e9);

        vm.stopPrank();

        createPairAndAddLiquidity();
    }

    /**
     * HELPER FUNCTIONS
     */
    function _vestTeam() internal {
        lockUp.addTeamMember(BERA_RESERVE_TEAM, lockUp.TEAM_TOTAL_BRR_AMOUNT());
    }

    function _vestMarketing() internal {
        address[] memory marketingAddresses = new address[](5);

        marketingAddresses[0] = 0xDa759c3f480a0Cc8859CC8ba7bB35211ead95161;
        marketingAddresses[1] = 0x2b7C3052349500b059D80cb614355900369A9c77;
        marketingAddresses[2] = 0x8b5d3e6FD56488c7Bc4F31b93Fa2f2E219fDfb38;
        marketingAddresses[3] = 0xCFf874C7b8496451A34775AcBf34d96C612Adc38;
        marketingAddresses[4] = 0x25d7876bFE3ae2441509D206A1b69D999a8681d7;

        uint128[] memory totalAmounts = new uint128[](5); //10_000e9
        totalAmounts[0] = 2_000e9;
        totalAmounts[1] = 1_000e9;
        totalAmounts[2] = 1_000e9;
        totalAmounts[3] = 1_000e9;
        totalAmounts[4] = 5_000e9;

        lockUp.addMultipleMarketingMembers(marketingAddresses, totalAmounts);
    }

    function _vestPresalers() internal {
        address[] memory presalersAddresses = new address[](8);
        presalersAddresses[0] = 0x2f9cFBd2bcB597530B7fFD54Eb71C4cc92036c58;
        presalersAddresses[1] = 0x3e3638cB24b88C2059F52cfD91C383635Ee05FC2;
        presalersAddresses[2] = 0xb4EC99681894D71c2210AccCcdf02A57dc57C394;
        presalersAddresses[3] = 0xCb736662688275120A6eA7dB4bE8950855f85ADc;
        presalersAddresses[4] = 0xF703A4ADeD9797587e795eE12862dc3Bab7F8146;
        presalersAddresses[5] = 0x5bBB3680F72082bA4ED06F75e1d297E972c44A93;
        presalersAddresses[6] = 0xF94Ea8Cda180F44A130Dc834E75BB72643088c23;
        presalersAddresses[7] = 0x6334546f6D6079d6276C8124389decF4C7A26d12;

        uint128[] memory totalAmounts = new uint128[](8); //40_000e9
        totalAmounts[0] = 7_000e9;
        totalAmounts[1] = 3_000e9;
        totalAmounts[2] = 2_000e9;
        totalAmounts[3] = 3_000e9;
        totalAmounts[4] = 10_000e9;
        totalAmounts[5] = 7_000e9;
        totalAmounts[6] = 3_000e9;
        totalAmounts[7] = 5_000e9;

        lockUp.addMultipleSeedRoundMembers(presalersAddresses, totalAmounts);
    }

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

        //add LP to treasury
        BeraReserveTreasury.MANAGING liquidityToken = BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN;
        BeraReserveTreasury.MANAGING liquidityDepositor = BeraReserveTreasury.MANAGING.LIQUIDITYDEPOSITOR;
        treasury.queue(liquidityToken, address(uniswapV2Pair));
        treasury.queue(liquidityDepositor, BERA_RESERVE_LIQUIDITY_WALLET);

        vm.roll(block.number + 1);

        treasury.toggle(liquidityToken, address(uniswapV2Pair), address(bondingCalculator));
        treasury.toggle(liquidityDepositor, BERA_RESERVE_LIQUIDITY_WALLET, address(0));

        vm.stopPrank();

        uint256 lpBalance = IERC20(uniswapV2Pair).balanceOf(BERA_RESERVE_LIQUIDITY_WALLET);
        vm.startPrank(BERA_RESERVE_LIQUIDITY_WALLET);
        IERC20(uniswapV2Pair).approve(address(treasury), lpBalance);
        treasury.deposit(lpBalance, address(uniswapV2Pair), 0);
        vm.stopPrank();
    }
}
