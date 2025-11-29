// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { BeraReserveToken } from "../../src/BeraReserveToken.sol";
import { sBeraReserve } from "../../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../../src/Staking.sol";
import { StakingWarmup } from "../../src/StakingWarmup.sol";
import { DistributorV2 } from "../../src/StakingDistributorV2.sol";
import { BeraReserveLockUp } from "../../src/BeraReserveLockUp.sol";
import { BeraReserveFeeDistributor } from "../../src/BeraReserveFeeDistributor.sol";
import { BeraReservePreBondClaims } from "../../src/BeraReservePreBondClaims.sol";

//!remove before deployment
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IUniswapV2Factory } from "src/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "src/interfaces/IUniswapV2Router02.sol";

contract BeraReserveDeploymentScriptV2 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    address public constant BERA_RESERVE_POL = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_TEAM = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    address public constant BERA_RESERVE_REWARD_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_AIRDROP_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    address public constant BERA_RESERVE_LIQUIDITY_WALLET = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    address public constant BERA_RESERVE_TREASURY_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    uint256 internal constant LIQUIDITY_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint256 internal constant AIRDROP_TOTAL_BRR_AMOUNT = 24_000e9; //24,000 (12% of total supply)
    uint256 internal constant REWARDS_TOTAL_BRR_AMOUNT = 26_000e9; // 26,000 BRR (13% of total supply)
    uint256 internal constant MARKETING_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint256 internal constant TEAM_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    uint256 internal constant SEED_ROUND_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    uint256 public constant VESTING_TOTAL_BRR_AMOUNT = 90_000e9;
    uint256 public constant PRE_BONDS_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    address public constant USDC_TOKEN = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address public constant BOND_PRESALE_CONTRACT = 0xb90200C9b292e5a1C348baeb050c1dAF2D3f739a;

    //!remove before deployment
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022);
    address public constant HONEY_WHALE = 0xD6D83e479359766f21A63b20d6AF43A138356EbA;
    address public constant HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address public uniswapV2Pair;

    BeraReserveToken public beraReserveToken;
    sBeraReserve public sBeraReserveToken;
    BeraReserveStaking public staking;
    BeraReserveStaking.CONTRACTS public contracts;
    StakingWarmup public warmup;
    DistributorV2 public distributor;
    BeraReserveFeeDistributor public feeDistributor;
    BeraReserveLockUp public lockUp;
    BeraReservePreBondClaims public preSaleClaims;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        beraReserveToken =
            new BeraReserveToken(BERA_RESERVE_ADMIN, BERA_RESERVE_REWARD_WALLET, BERA_RESERVE_AIRDROP_WALLET);

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

        distributor = new DistributorV2(
            address(beraReserveToken),
            14_400, //epochLength
            block.number + 14_400 //nextEpochBlock
        );

        warmup = new StakingWarmup(address(staking), address(sBeraReserveToken));

        feeDistributor = new BeraReserveFeeDistributor(
            BERA_RESERVE_ADMIN,
            BERA_RESERVE_TREASURY_WALLET,
            BERA_RESERVE_POL,
            BERA_RESERVE_TEAM,
            address(beraReserveToken)
        );

        preSaleClaims =
            new BeraReservePreBondClaims(address(beraReserveToken), BERA_RESERVE_ADMIN, BOND_PRESALE_CONTRACT);

        ///@notice configs
        beraReserveToken.setProtocolTreasury(BERA_RESERVE_TREASURY_WALLET);

        beraReserveToken.setTwentyFivePercentBelowFees(1_600);

        beraReserveToken.setTenPercentBelowFees(1_200);

        beraReserveToken.setBelowTreasuryValueFees(1_000);

        ///@dev set mcap in usdc
        beraReserveToken.setMarketCap(200_000e6);

        beraReserveToken.setStaking(address(staking));

        beraReserveToken.setTreasuryAllocation(40_000e9);

        beraReserveToken.setDecayRatio(0);

        contracts = BeraReserveStaking.CONTRACTS.WARMUP;

        staking.setContract(contracts, address(warmup));

        contracts = BeraReserveStaking.CONTRACTS.DISTRIBUTOR;

        staking.setContract(contracts, address(distributor));

        contracts = BeraReserveStaking.CONTRACTS.LOCKER;

        staking.setContract(contracts, address(lockUp));

        distributor.addRecipient(address(staking), 4_300); // the recipient gets 1% of the distributable BRR per epoch.

        sBeraReserveToken.initialize(address(staking));

        sBeraReserveToken.setIndex(1e9);

        beraReserveToken.setFeeDistributor(address(feeDistributor));

        ///@dev exclude accounts from fees and decay
        beraReserveToken.excludeAccountFromFeesAndDecay(address(staking), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(feeDistributor), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(preSaleClaims), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(distributor), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(address(lockUp), true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_POL, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BERA_RESERVE_TEAM, true);

        //set mint allocations
        beraReserveToken.setAllocationLimit(address(lockUp), VESTING_TOTAL_BRR_AMOUNT);
        beraReserveToken.setAllocationLimit(address(preSaleClaims), PRE_BONDS_TOTAL_BRR_AMOUNT);
        beraReserveToken.setAllocationLimit(address(distributor), type(uint256).max);

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

        //remove before deployment
        // _testStakingRebasing();
        // _testSwapAndFees();
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
        console2.log("BRR token :", address(beraReserveToken));
        console2.log("sBRR token :", address(sBeraReserveToken));
        console2.log("Staking :", address(staking));
        console2.log("Staking distributor", address(distributor));
        console2.log("Fee Distributor", address(feeDistributor));
        console2.log("PreSaleClaims", address(preSaleClaims));
        console2.log("LockUp", address(lockUp));
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
        require(
            beraReserveToken.protocolTreasuryAddress() == BERA_RESERVE_TREASURY_WALLET,
            "Invalid protocol treasury on token"
        );
        require(beraReserveToken.buyFee() == 300, "Buy fee !300");
        require(beraReserveToken.sellFee() == 300, "Sell fee !300");
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
        require(beraReserveToken.isExcludedAccountsFromDecay(address(lockUp)), "LockUp contract in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(address(staking)), "Staking contract in decay");
        require(beraReserveToken.isExcludedAccountsFromDecay(address(distributor)), "Distributor contract in decay");
        require(
            beraReserveToken.isExcludedAccountsFromDecay(address(feeDistributor)), "FeeDistributor contract in decay"
        );
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_AIRDROP_WALLET), "Airdrop wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_REWARD_WALLET), "Reward wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_TEAM), "Team wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_POL), "POL wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(BERA_RESERVE_LIQUIDITY_WALLET), "Liquidity wallet in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(preSaleClaims)), "Pre-bond contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(lockUp)), "LockUp contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(staking)), "Staking contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(distributor)), "Distributor contract in fees");
        require(beraReserveToken.isExcludedAccountsFromFees(address(feeDistributor)), "FeeDistributor contract in fees");

        /*//////////////////////////////////////////////////////////////
                              SBRR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(sBeraReserveToken.index() == 1e9, "Index != 1BRR");
        require(sBeraReserveToken.stakingContract() == address(staking), "Staking contract != staking");

        /*//////////////////////////////////////////////////////////////
                             WARMUP CHECKS
        //////////////////////////////////////////////////////////////*/
        require(warmup.staking() == address(staking), "Staking contract != staking");
        require(warmup.sBRR() == address(sBeraReserveToken), " warmup: sBRR contract != sBRR");

        /*//////////////////////////////////////////////////////////////
                             DISTRIBUTOR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(distributor.BRR() == address(beraReserveToken), "BRR contract != beraReserveToken");

        (uint256 rate, address recipient) = distributor.info(0);
        require(recipient == address(staking), "Staking contract != recipient");
        require(rate == 4_300, "Staking contract != rate");

        /*//////////////////////////////////////////////////////////////
                             STAKING CHECKS
        //////////////////////////////////////////////////////////////*/
        require(staking.BRR() == address(beraReserveToken), "Invalid BRR token in staking");
        require(staking.distributor() == address(distributor), "Invalid distributor in staking");
        require(staking.sBRR() == address(sBeraReserveToken), "Invalid sBRR in staking");
        require(staking.warmupContract() == address(warmup), "Invalid warmup in staking");

        (uint256 length, uint256 number, uint256 endBlock, uint256 distribute) = staking.epoch();
        require(length == 14_400, "Epoch length != 14400");
        require(number == 1, "Epoch number != 1");
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
                         FEE DISTRIBUTOR CHECKS
        //////////////////////////////////////////////////////////////*/
        require(
            address(feeDistributor.beraReserveToken()) == address(beraReserveToken), "BRR contract != beraReserveToken"
        );
        require(address(feeDistributor.pol()) == address(BERA_RESERVE_POL), "POL contract != BeraReservePOL");
        require(address(feeDistributor.treasury()) == BERA_RESERVE_TREASURY_WALLET, "Treasury contract != treasury");
        require(feeDistributor.team() == address(BERA_RESERVE_TEAM), "Team contract != team");

        /*//////////////////////////////////////////////////////////////
                            PRE-SALE CLAIMS
        //////////////////////////////////////////////////////////////*/
        require(address(preSaleClaims.brrToken()) == address(beraReserveToken), "BRR contract != beraReserveToken");
        require(address(preSaleClaims.preBondSaleContract()) == BOND_PRESALE_CONTRACT, "Prebond != preBondPurchase");
        require(preSaleClaims.paused() == true, "PreClaims !paused");
    }

    //!remove before deployment
    function _testStakingRebasing() internal {
        vm.startPrank(address(lockUp));
        staking.claim(address(lockUp));
        vm.stopPrank();

        uint256 sBRRBalanceBefore = sBeraReserveToken.balanceOf(address(lockUp));
        uint256 brrStakingBalanceBefore = beraReserveToken.balanceOf(address(staking));

        vm.roll(block.number + 14_400);
        vm.startPrank(BERA_RESERVE_POL);
        //approve BRR
        beraReserveToken.approve(address(staking), 1_000e9);
        staking.stake(1_000e9, BERA_RESERVE_POL);
        vm.stopPrank();

        vm.roll(block.number + 1);
        //second rebase
        vm.roll(block.number + 14_400);
        vm.startPrank(BERA_RESERVE_POL);
        //approve BRR
        beraReserveToken.approve(address(staking), 1_000e9);
        staking.stake(1_000e9, BERA_RESERVE_POL);
        vm.stopPrank();

        uint256 sBRRBalanceAfter = sBeraReserveToken.balanceOf(address(lockUp));
        uint256 brrStakingBalanceAfter = beraReserveToken.balanceOf(address(staking));

        require(sBRRBalanceAfter > sBRRBalanceBefore, "sBRR balance should increase");
        require(brrStakingBalanceAfter > brrStakingBalanceBefore, "Staking balance should increase");
        require(sBeraReserveToken.index() > 1e9, "sBRR index should increase");
    }

    function _testSwapAndFees() internal {
        createPairAndAddLiquidity();

        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_ADMIN, 1_000e18);

        vm.prank(BERA_RESERVE_ADMIN);
        //approve honey
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        uint256 feeDistributorBalancePriorBuy = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 buyerBRR_BalanceBefore = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_ADMIN);
        uint256 buyerHoneyBalanceBefore = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_ADMIN);

        /**
         * BUY BRR
         */
        vm.startPrank(BERA_RESERVE_ADMIN);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            100e18, 10e9, path, BERA_RESERVE_ADMIN, block.timestamp + 1000
        );

        uint256 feeDistributorBalanceAfterBuy = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 buyerBRR_BalanceAfterBuy = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_ADMIN);
        uint256 buyerHoneyBalanceAfterBuy = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_ADMIN);

        require(
            feeDistributorBalanceAfterBuy > feeDistributorBalancePriorBuy, "Fee Distributor balance should increase"
        );
        require(buyerBRR_BalanceAfterBuy > buyerBRR_BalanceBefore, "BRR Balance should increase");
        require(buyerHoneyBalanceBefore > buyerHoneyBalanceAfterBuy, "Honey Balance should increase");

        /**
         * SELL BRR
         */
        //swap brr for Honey
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(beraReserveToken);
        buyPath[1] = HONEY_TOKEN;

        vm.startPrank(BERA_RESERVE_ADMIN);

        IERC20(address(beraReserveToken)).approve(address(uniswapRouter), 90e9);

        //5% slippage
        uint256 amountOut = uniswapRouter.getAmountsOut(90e9, buyPath)[1];
        uint256 slippage = (95 * amountOut) / 100;
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            90e9, slippage, buyPath, BERA_RESERVE_ADMIN, block.timestamp + 1000
        );

        uint256 feeDistributorBalanceAfterSell = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 buyerBRR_BalanceAfterSell = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_ADMIN);
        uint256 buyerHoneyBalanceAfterSell = IERC20(HONEY_TOKEN).balanceOf(BERA_RESERVE_ADMIN);

        require(
            feeDistributorBalanceAfterSell > feeDistributorBalanceAfterBuy,
            "Fee distributor bRR Increase after Sell BRR"
        );
        require(buyerBRR_BalanceAfterBuy > buyerBRR_BalanceAfterSell, "BRR Balance should increase after Sell BRR");
        require(buyerHoneyBalanceAfterSell > buyerHoneyBalanceAfterBuy, "Honey Balance should increase after Sell BRR");
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

        vm.stopPrank();
    }
}
