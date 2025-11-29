// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { BeraReserveToken } from "../src/BeraReserveToken.sol";
import { sBeraReserve } from "../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../src/Staking.sol";
import { BeraReserveTreasury } from "../src/Treasury.sol";
import { BeraReserveBondDepository } from "../src/BondDepository.sol";
import { StakingWarmup } from "../src/StakingWarmup.sol";
import { BeraReserveBondingCalculator } from "../src/BeraReserveBondingCalculator.sol";
import { Distributor } from "../src/StakingDistributor.sol";
// import { StakingHelper } from "../src/StakingHelper.sol";
import { BeraReserveLockUp } from "../src/BeraReserveLockUp.sol";
// import { BeraReservePreSaleBond } from "../src/BeraReservePreSaleBond.sol";
import { BeraReserveFeeDistributor } from "../src/BeraReserveFeeDistributor.sol";
import { BeraReservePreBondClaims } from "../src/BeraReservePreBondClaims.sol";

contract BeraReserveDeploymentScriptV1 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    address public constant BERA_RESERVE_TREASURY_WALLET = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0; //!change
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

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        beraReserveToken =
            new BeraReserveToken(BERA_RESERVE_ADMIN, BERA_RESERVE_REWARD_WALLET, BERA_RESERVE_AIRDROP_WALLET);

        bondingCalculator = new BeraReserveBondingCalculator(address(beraReserveToken));

        sBeraReserveToken = new sBeraReserve();

        staking = new BeraReserveStaking(
            address(beraReserveToken),
            address(sBeraReserveToken),
            14_400, //epochLength
            1, //firstEpochNumber
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
            BERA_RESERVE_ADMIN, address(treasury), BERA_RESERVE_POL, BERA_RESERVE_TEAM, address(beraReserveToken)
        );

        //address _brr, address _principle, address _treasury, address _DAO, address _bondCalculator
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

        beraReserveToken.setProtocolTreasury(BERA_RESERVE_TREASURY_WALLET);

        contracts = BeraReserveStaking.CONTRACTS.WARMUP;

        staking.setContract(contracts, address(warmup));

        contracts = BeraReserveStaking.CONTRACTS.DISTRIBUTOR;

        staking.setContract(contracts, address(distributor));

        contracts = BeraReserveStaking.CONTRACTS.LOCKER;

        staking.setContract(contracts, address(lockUp));

        distributor.addRecipient(address(staking), 4300); // the recipient gets 1% of the distributable BRR per epoch.

        usdcBondDepository.setStaking(address(staking), false);

        usdcBondDepository.initializeBondTerms(
            2, //controlVariable
            216_000, //vestingTerm
            101, //minimumPrice //$1.01
            500, //maxPayout(0.5%)
            100, //fee (1%)
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
        beraReserveToken.setAllocationLimit(address(preSaleClaims), PRE_BONDS_TOTAL_BRR_AMOUNT);

        lockUp.mintAndStakeBRR();

        preSaleClaims.mintBRR();

        preSaleClaims.pause();

        //Vest team , marketing and presalers.
        _vestTeam();
        _vestMarketing();
        _vestPresalers();

        _logDeployedContracts();

        _postDeploymentChecks();

        vm.stopBroadcast();
    }

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

    function _logDeployedContracts() internal view {
        console.log("beraReserveToken :", address(beraReserveToken));
        console.log("sBeraReserveToken :", address(sBeraReserveToken));
        console.log("staking :", address(staking));
        console.log("treasury :", address(treasury));
        console.log("usdcBondDepository :", address(usdcBondDepository));
        console.log("distributor", address(distributor));
        console.log("Fee Distributor", address(feeDistributor));
        console.log("bondingCalculator", address(bondingCalculator));
        console.log("LockUp", address(lockUp));
    }

    //solhint-disable gas-custom-errors
    function _postDeploymentChecks() internal view {
        ///@dev check circulating supply == 160k
        uint256 circulatingSupply = beraReserveToken.totalSupply();
        require(circulatingSupply == 160_000e9, "Circulating supply !160k");

        /*//////////////////////////////////////////////////////////////
                           ALLOCATIONS CHECKS
        //////////////////////////////////////////////////////////////*/
        require(
            beraReserveToken.balanceOf(BERA_RESERVE_AIRDROP_WALLET) >= AIRDROP_TOTAL_BRR_AMOUNT,
            "Airdrop total BRR balance !24k"
        );
        require(
            beraReserveToken.balanceOf(BERA_RESERVE_REWARD_WALLET) >= REWARDS_TOTAL_BRR_AMOUNT,
            "Reward total BRR balance !26k"
        );
        require(
            beraReserveToken.balanceOf(BERA_RESERVE_LIQUIDITY_WALLET) >= LIQUIDITY_TOTAL_BRR_AMOUNT,
            "Liquidity total BRR balance !10k"
        );

        require(
            beraReserveToken.balanceOf(address(preSaleClaims)) == PRE_BONDS_TOTAL_BRR_AMOUNT,
            "Pre-bond total BRR balance !10k"
        );
        require(beraReserveToken.balanceOf(address(lockUp)) == 12_000e9, "LockUp total BRR balance !12k");
        //@notice The 12K BRR is available for presaler at TGE. (30% of 40k) allocated to Presalers.
        require(
            beraReserveToken.balanceOf(address(staking)) == VESTING_TOTAL_BRR_AMOUNT - 12_000e9,
            "Vesting total BRR balance !78k"
        );

        /*//////////////////////////////////////////////////////////////
                       BERA RESERVE TOKEN CHECKS
        //////////////////////////////////////////////////////////////*/
        require(beraReserveToken.treasuryAllocation() == 40_000e9, "Treasury allocation !40k");
        require(beraReserveToken.staking() == address(staking), "Invalid staking on token");
        require(beraReserveToken.feeDistributor() == address(feeDistributor), "Invalid feeDistributor on token");
        require(beraReserveToken.protocolTreasuryAddress() == BERA_RESERVE_TREASURY_WALLET, "Invalid treasury on token");
        require(beraReserveToken.vault() == address(treasury), "Invalid vault on token");
        require(beraReserveToken.buyFee() == 300, "Buy fee !300");
        require(beraReserveToken.sellFee() == 300, "Sell fee !300");
        require(beraReserveToken.decayRatio() == 2_000, "Decay ratio !2_000");
        require(beraReserveToken.marketCap() == 200_000e6, "Market cap !200k");
        require(beraReserveToken.tenPercentBelowFees() == 1_200, "Ten percent below fees !1200");
        require(beraReserveToken.twentyFivePercentBelowFees() == 1_600, "25% below fees !1600");
        require(beraReserveToken.belowTreasuryValueFees() == 1_000, "Below treasury value fees !1000");

        /*//////////////////////////////////////////////////////////////
                         FEES AND DECAY CHECKS
        //////////////////////////////////////////////////////////////*/
        require(beraReserveToken.isExcludedAccountsFromDecay(BERA_RESERVE_AIRDROP_WALLET), "AirdropWallet in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(BERA_RESERVE_REWARD_WALLET), "Reward wallet in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(BERA_RESERVE_TEAM), "Team wallet in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(BERA_RESERVE_POL), "POL wallet in decay");
        require(
            beraReserveToken.isExcludedAccountsFromDecay(BERA_RESERVE_LIQUIDITY_WALLET), "Liquidity wallet in decay"
        );
        require(beraReserveToken.isExcludedAccountsFromDecay(address(preSaleClaims)), "Pre-bond contract in decay");
        require(
            beraReserveToken.isExcludedAccountsFromDecay(address(usdcBondDepository)), "USDCBondDepository in decay"
        );
        require(beraReserveToken.isExcludedAccountsFromDecay(address(lockUp)), "LockUp contract in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(address(staking)), "Staking contract in decay");
        require(
            beraReserveToken.isExcludedAccountsFromDecay(address(feeDistributor)), "FeeDistributor contract in decay"
        );
        require(beraReserveToken.isExcludedAccountsFromDecay(address(treasury)), "Treasury contract in decay");

        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_AIRDROP_WALLET), "Airdrop wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_REWARD_WALLET), "Reward wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_TEAM), "Team wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_POL), "POL wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_LIQUIDITY_WALLET), "Liquidity wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(preSaleClaims)), "Pre-bond contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(usdcBondDepository)), "USDCBondDepository in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(lockUp)), "LockUp contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(staking)), "Staking contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(feeDistributor)), "FeeDistributor contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(treasury)), "Treasury contract in fees");

        /*//////////////////////////////////////////////////////////////
                              SBRR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(sBeraReserveToken.index() == 0, "Index != 0");
        require(sBeraReserveToken.stakingContract() == address(staking), "Staking contract != staking");

        /*//////////////////////////////////////////////////////////////
                             WARMUP CHECKS
        //////////////////////////////////////////////////////////////*/
        require(warmup.staking() == address(staking), "Staking contract != staking");
        require(warmup.sBRR() == address(sBeraReserveToken), " warmup: sBRR contract != sBRR");

        /*//////////////////////////////////////////////////////////////
                             DISTRIBUTOR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(distributor.treasury() == address(treasury), "Treasury contract != treasury");
        require(distributor.BRR() == address(beraReserveToken), "BRR contract != beraReserveToken");

        (uint256 rate, address recipient) = distributor.info(0);
        require(recipient == address(staking), "Staking contract != recipient");
        require(rate == 4300, "Staking contract != rate");

        /*//////////////////////////////////////////////////////////////
                             STAKING CHECKS
        //////////////////////////////////////////////////////////////*/
        require(staking.BRR() == address(beraReserveToken), "Invalid BRR token in staking");
        require(staking.distributor() == address(distributor), "Invalid distributor in staking");
        require(staking.sBRR() == address(sBeraReserveToken), "Invalid sBRR in staking");
        require(staking.warmupContract() == address(warmup), "Invalid warmup in staking");

        (uint256 length, uint256 number, uint256 endBlock, uint256 distribute) = staking.epoch();
        require(length == 14_400, "Epoch length != 14400");
        require(number == 0, "Epoch number != 0");
        require(endBlock == block.number + 14_400, "Epoch endBlock != block.number");
        require(distribute == 0, "Epoch distribute != 0");

        /*//////////////////////////////////////////////////////////////
                                 LOCK-UP CHECKS
        //////////////////////////////////////////////////////////////*/
        require(address(lockUp.beraStaking()) == address(staking), "Staking contract != staking");
        require(address(lockUp.brrToken()) == address(beraReserveToken), "BRR contract != beraReserveToken");
        require(address(lockUp.sBrrToken()) == address(sBeraReserveToken), "sBRR contract != sBRR");
        require(lockUp.totalMarketingBRRAllocated() == MARKETING_TOTAL_BRR_AMOUNT, "Marketing BRR balance != 10k");
        require(lockUp.totalTeamBRRAllocated() == TEAM_TOTAL_BRR_AMOUNT, "Team BRR balance != 40k");
        require(lockUp.totalSeedRoundBRRAllocated() == SEED_ROUND_TOTAL_BRR_AMOUNT, "Presalers BRR balance != 40k");

        /*//////////////////////////////////////////////////////////////
                            TREASURY CHECKS
        //////////////////////////////////////////////////////////////*/
        require(address(treasury.BRR()) == address(beraReserveToken), "BRR contract != beraReserveToken");
        require(treasury.totalDebt() == 160_000e9, "Total debt != 160k");

        /*//////////////////////////////////////////////////////////////
                         FEE DISTRIBUTOR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(
            address(feeDistributor.beraReserveToken()) == address(beraReserveToken), "BRR contract != beraReserveToken"
        );
        require(address(feeDistributor.pol()) == address(BERA_RESERVE_POL), "POL contract != BeraReservePOL");
        require(address(feeDistributor.treasury()) == address(treasury), "Treasury contract != treasury");
        require(feeDistributor.team() == address(BERA_RESERVE_TEAM), "Team contract != team");

        /*//////////////////////////////////////////////////////////////
                      USDC BOND DEPOSITORY CHECKS
        //////////////////////////////////////////////////////////////*/
        require(address(usdcBondDepository.BRR()) == address(beraReserveToken), "BRR contract != beraReserveToken");
        require(address(usdcBondDepository.staking()) == address(staking), "Staking contract != staking");
        require(address(usdcBondDepository.DAO()) == address(feeDistributor), "DAO contract != feeDistributor");
        require(usdcBondDepository.principle() == USDC_TOKEN, "principle != USDC");
        require(address(usdcBondDepository.staking()) == address(staking), "Staking contract != staking");

        (
            uint256 controlVariable,
            uint256 vestingTerm,
            uint256 minimumPrice,
            uint256 maxPayout,
            uint256 fee,
            uint256 maxDebt
        ) = usdcBondDepository.terms();
        require(usdcBondDepository.totalDebt() == 0, "Total debt != 0");
        require(controlVariable == 2, "Control variable != 2");
        require(vestingTerm == 216_000, "Vesting term != 216000");
        require(minimumPrice == 101, "Minimum price != 101");
        require(maxPayout == 500, "Max payout != 500");
        require(fee == 100, "Fee != 100");
        require(maxDebt == 40_000e9, "Max debt != 40k");

        /*//////////////////////////////////////////////////////////////
                            PRE-SALE CLAIMS
        //////////////////////////////////////////////////////////////*/
        require(address(preSaleClaims.brrToken()) == address(beraReserveToken), "BRR contract != beraReserveToken");
        require(address(preSaleClaims.preBondSaleContract()) == BOND_PRESALE_CONTRACT, "Prebond != preBondPurchase");
    }
}
