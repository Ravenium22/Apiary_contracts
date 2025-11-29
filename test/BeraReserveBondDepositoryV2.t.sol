// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { console2, Test } from "forge-std/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { BeraReserveBondDepositoryV2 } from "../src/BeraReserveBondDepositoryV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BeraReserveBondDepositoryV2Test is BeraReserveBaseTestV2 {
    struct PreDepositState {
        uint256 daoBalance;
        uint256 treasuryBalance;
        uint256 totalDebt;
        uint256 brrSupply;
    }

    struct PreRedeemState {
        uint256 bobBRRBalance;
        uint256 depositoryBRRBalance;
    }

    struct PreMultiRedeemState {
        uint256 bobBRRBalance;
        uint256 aliceBRRBalance;
        uint256 depositoryBRRBalance;
    }

    struct PostDepositState {
        uint256 daoBalance;
        uint256 treasuryBalance;
        uint256 totalDebt;
        uint256 brrSupply;
    }

    struct PostRedeemState {
        uint256 bobBRRBalance;
        uint256 depositoryBRRBalance;
    }

    struct PostMultiRedeemState {
        uint256 bobBRRBalance;
        uint256 aliceBRRBalance;
        uint256 depositoryBRRBalance;
    }

    error OwnableUnauthorizedAccount(address account);
    error EnforcedPause();

    function setUp() public virtual override {
        super.setUp();
        vm.roll(4733102);

        // updateTwapPrices();
    }

    /*//////////////////////////////////////////////////////////////
                       NORMAL TESTS - CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorParamsSetCorrectlyForUSDC_BondDepository() external view {
        assertEq(usdcDepository.BRR(), address(beraReserveToken), "BRR address mismatch");
        assertEq(usdcDepository.treasury(), address(treasury), "Treasury address mismatch");
        assertEq(usdcDepository.dao(), address(feeDistributor), "DAO address mismatch");
        assertEq(usdcDepository.principle(), address(USDC_TOKEN), "Principle address mismatch");
    }

    function testConstructorParamsSetCorrectlyForBRR_HONEY_BondDepository() external view {
        assertEq(bRRHoneyDepository.BRR(), address(beraReserveToken), "BRR address mismatch");
        assertEq(bRRHoneyDepository.treasury(), address(treasury), "Treasury address mismatch");
        assertEq(bRRHoneyDepository.dao(), address(feeDistributor), "DAO address mismatch");
        assertEq(bRRHoneyDepository.principle(), address(uniswapV2Pair), "Principle address mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                  NORMAL TESTS - INITIALIZE BOND TERMS
    //////////////////////////////////////////////////////////////*/

    function testShouldFailInitializeBondTermsIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        usdcDepository.initializeBondTerms(1, 1, 1, 1, 1);
        vm.stopPrank();
    }

    function testShouldFailInitializeBondTermsIfAlreadyInitialized() external {
        vm.prank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(1, 1, 1, 1, 1);

        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.AlreadyInitialized.selector);
        usdcDepository.initializeBondTerms(1, 1, 1, 1, 1);
        vm.stopPrank();
    }

    function testShouldInitializeBondTermsCorrectly() external {
        vm.prank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 50, 100, 50, 40_000e9);

        (uint256 vestingTerm, uint256 maxPayout, uint256 fee, uint256 discountRate, uint256 maxDebt) = usdcDepository.terms();

        assertEq(vestingTerm, 216_000, "Vesting term mismatch");
        assertEq(maxPayout, 50, "Max payout mismatch");
        assertEq(fee, 100, "Fee mismatch");
        assertEq(discountRate, 50, "Discount rate mismatch");
        assertEq(maxDebt, 40_000e9, "Max debt mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                     NORMAL TESTS - SET BOND TERMS
    //////////////////////////////////////////////////////////////*/
    function testShouldFailSetBondTermsIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));

        BeraReserveBondDepositoryV2.PARAMETER param = BeraReserveBondDepositoryV2.PARAMETER.VESTING;

        usdcDepository.setBondTerms(param, 1);
        vm.stopPrank();
    }

    function testShouldFailSetBondTermsIfVestingTermTooLow() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidVestingTerm.selector);
        usdcDepository.setBondTerms(BeraReserveBondDepositoryV2.PARAMETER.VESTING, 60_000);
        vm.stopPrank();
    }

    function testShouldFailSetBondTermsIfMaxPayoutTooHigh() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidMaxPayout.selector);
        usdcDepository.setBondTerms(BeraReserveBondDepositoryV2.PARAMETER.PAYOUT, 101);
        vm.stopPrank();
    }

    function testShouldFailSetBondTermsIfFeeTooHigh() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidFee.selector);
        usdcDepository.setBondTerms(BeraReserveBondDepositoryV2.PARAMETER.FEE, 10_001);
        vm.stopPrank();
    }

    function testShouldFailIfSetBondTermsIfDiscountRateTooHigh() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidDiscountRate.selector);
        usdcDepository.setBondTerms(BeraReserveBondDepositoryV2.PARAMETER.DISCOUNT_RATE, 10_001);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         NORMAL TESTS - SET DAO
    //////////////////////////////////////////////////////////////*/
    function testShouldFailSetDAOIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        usdcDepository.setDAO(ALICE);
        vm.stopPrank();
    }

    function testShouldFailSetDAOIfZeroAddress() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.ZeroAddress.selector);
        usdcDepository.setDAO(address(0));
        vm.stopPrank();
    }

    function testShouldSetDAOCorrectly() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.setDAO(ALICE);
        assertEq(usdcDepository.dao(), ALICE, "DAO address mismatch");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    NORMAL TESTS - PAUSE AND UNPAUSE
    //////////////////////////////////////////////////////////////*/

    function testShouldFailPauseIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        usdcDepository.pause();
        vm.stopPrank();
    }

    function testShouldFailUnpauseIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        usdcDepository.unpause();
        vm.stopPrank();
    }

    function testShouldPauseCorrectly() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.pause();
        assertTrue(usdcDepository.paused(), "Contract should be paused");
        vm.stopPrank();
    }

    function testShouldUnpauseCorrectly() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.pause();
        usdcDepository.unpause();
        assertFalse(usdcDepository.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function testShouldFailDepositIfPaused() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.pause();
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(EnforcedPause.selector);
        usdcDepository.deposit(1e6, 1.2e18);
        vm.stopPrank();
    }

    function testShouldFailRedeemIfPaused() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.pause();
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(EnforcedPause.selector);
        usdcDepository.redeem();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        NORMAL TESTS - CLAW-BACK
    //////////////////////////////////////////////////////////////*/
    function testShouldFailClawBackIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        usdcDepository.clawBackTokens(address(USDC_TOKEN), 1e6);
        vm.stopPrank();
    }

    function testShouldFailClawBackIfZeroAmount() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidAmount.selector);
        usdcDepository.clawBackTokens(address(USDC_TOKEN), 0);
        vm.stopPrank();
    }

    function testShouldFailClawBackIfZeroAddress() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.ZeroAddress.selector);
        usdcDepository.clawBackTokens(address(0), 1e6);
        vm.stopPrank();
    }

    function testShouldFailIfClawBackAmountExceedsBalance() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidAmount.selector);
        usdcDepository.clawBackTokens(address(USDC_TOKEN), 1e18);
        vm.stopPrank();
    }

    function testShouldClawBackTokensCorrectly() external {
        uint256 initialBalance = IERC20(USDC_TOKEN).balanceOf(BERA_RESERVE_ADMIN);
        uint256 clawBackAmount = 1e6;

        vm.prank(USDC_WHALE);
        IERC20(USDC_TOKEN).transfer(address(usdcDepository), clawBackAmount);

        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.clawBackTokens(address(USDC_TOKEN), clawBackAmount);
        vm.stopPrank();

        uint256 finalBalance = IERC20(USDC_TOKEN).balanceOf(BERA_RESERVE_ADMIN);
        assertEq(finalBalance, initialBalance + clawBackAmount, "Claw-back amount mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                        NORMAL TESTS - DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function testShouldFailDepositIfTotalDebtExceedsMaxDebt() external {
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer USDC to BOB
        transferUSDC(BOB, 42_000e6);

        //approve USDC for deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), 42_000e6);
        vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
        usdcDepository.deposit(42_000e6, 1.2e18);
        vm.stopPrank();
    }

    function testShouldFailDepositIfAmountIsZero() external {
        vm.startPrank(BOB);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidAmount.selector);
        usdcDepository.deposit(0, 1.2e18);
        vm.stopPrank();
    }

    function testShouldFailDepositIfMaxPriceIsZero() external {
        vm.startPrank(BOB);
        vm.expectRevert(BeraReserveBondDepositoryV2.InvalidMaxPrice.selector);
        usdcDepository.deposit(1e6, 0);
        vm.stopPrank();
    }

    function testShouldFailDepositIfPriceInHoneyExceedsMaxPrice() external {
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 50, 100, 50, 40_000e9);
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(BeraReserveBondDepositoryV2.SlippageLimitExceeded.selector);
        usdcDepository.deposit(1e6, 0.2e9);
        vm.stopPrank();
    }

    function testShouldFailDepositIfPayoutTooSmall() external {
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 50, 100, 50, 40_000e9);
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(BeraReserveBondDepositoryV2.BondTooSmall.selector);
        usdcDepository.deposit(0.001e6, 1.2e18);
        vm.stopPrank();
    }

    function testShouldFailDepositIfPayoutExceedsMaxPayout() external {
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
        usdcDepository.deposit(4_200e6, 1.2e18);
        vm.stopPrank();
    }

    function testUSDCDepositShouldWorkCorrectly() external {
        updateTwapPrices();

        skip(1 hours);
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer USDC to BOB
        transferUSDC(BOB, 1_000e6);

        uint256 daoBalanceBefore = beraReserveToken.balanceOf(address(feeDistributor));
        uint256 treasuryBalanceBefore = IERC20(USDC_TOKEN).balanceOf(address(treasury));
        uint256 totalDebtBefore = usdcDepository.totalDebt();
        uint256 brrTotalSupplyBefore = beraReserveToken.totalSupply();

        //approve USDC for deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), 1_000e6);
        usdcDepository.deposit(1_000e6, 1.2e18);
        vm.stopPrank();

        uint256 daoBalanceAfter = beraReserveToken.balanceOf(address(feeDistributor));
        uint256 treasuryBalanceAfter = IERC20(USDC_TOKEN).balanceOf(address(treasury));
        uint256 totalDebtAfter = usdcDepository.totalDebt();
        uint256 brrTotalSupplyAfter = beraReserveToken.totalSupply();

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);
        uint256 fee = (value * 100) / 10_000; // 1% fee

        assertEq(daoBalanceAfter, daoBalanceBefore + fee, "DAO BRR balance mismatch");
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore + 1_000e6, "Treasury USDC balance mismatch");
        assertEq(totalDebtAfter, totalDebtBefore + value, "Total debt mismatch");
        assertEq(brrTotalSupplyAfter, brrTotalSupplyBefore + value, "BRR total supply mismatch");

        // Check if the bond info is set correctly
        (uint256 amountBonded, uint256 payout, uint256 vesting, uint256 lastBlock, uint256 pricePaid) = usdcDepository.bondInfo(BOB);

        assertEq(payout, value - fee, "Payout mismatch");
        assertEq(amountBonded, 1_000e6, "Amount bonded mismatch");

        uint256 currentPrice = simpleTwap.consult(1e9);
        assertEq(pricePaid, getBondPrice(currentPrice, 50), "Price paid mismatch");

        assertEq(vesting, 216_000, "Vesting term mismatch");
        assertEq(lastBlock, block.number, "Last block mismatch");
    }

    function testBRRHoneyDepositShouldWorkCorrectly() external {
        updateTwapPrices();
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        bRRHoneyDepository.initializeBondTerms(216_000, 2000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer LP to BOB
        transferLP(BOB, 0.07e18);

        uint256 daoBalanceBefore = beraReserveToken.balanceOf(address(feeDistributor));
        uint256 treasuryBalanceBefore = IERC20(uniswapV2Pair).balanceOf(address(treasury));
        uint256 totalDebtBefore = bRRHoneyDepository.totalDebt();
        uint256 brrTotalSupplyBefore = beraReserveToken.totalSupply();

        //approve LP for deposit
        vm.startPrank(BOB);
        IERC20(uniswapV2Pair).approve(address(bRRHoneyDepository), 0.07e18);
        bRRHoneyDepository.deposit(0.07e18, 1.5e18);
        vm.stopPrank();

        uint256 daoBalanceAfter = beraReserveToken.balanceOf(address(feeDistributor));
        uint256 treasuryBalanceAfter = IERC20(uniswapV2Pair).balanceOf(address(treasury));
        uint256 totalDebtAfter = bRRHoneyDepository.totalDebt();
        uint256 brrTotalSupplyAfter = beraReserveToken.totalSupply();

        (uint256 value, ) = bRRHoneyDepository.valueOf(uniswapV2Pair, 0.07e18);
        uint256 fee = (value * 100) / 10_000; // 1% fee

        assertEq(daoBalanceAfter, daoBalanceBefore + fee, "DAO BRR balance mismatch");
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore + 0.07e18, "Treasury LP balance mismatch");
        assertEq(totalDebtAfter, totalDebtBefore + value, "Total debt mismatch");
        assertEq(brrTotalSupplyAfter, brrTotalSupplyBefore + value, "BRR total supply mismatch");

        // Check if the bond info is set correctly
        (uint256 amountBonded, uint256 payout, uint256 vesting, uint256 lastBlock, uint256 pricePaid) = bRRHoneyDepository.bondInfo(BOB);

        assertEq(payout, value - fee, "Payout mismatch");
        assertEq(amountBonded, 0.07e18, "Amount bonded mismatch");

        uint256 currentPrice = simpleTwap.consult(1e9);
        assertEq(pricePaid, getBondPrice(currentPrice, 50), "Price paid mismatch");

        assertEq(vesting, 216_000, "Vesting term mismatch");
        assertEq(lastBlock, block.number, "Last block mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                         NORMAL TESTS - REDEEMS
    //////////////////////////////////////////////////////////////*/

    function testUserRedeemShouldReceiveNoBRRIfVestingIsZero() external {
        uint256 bobBRRBalanceBefore = beraReserveToken.balanceOf(BOB);
        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        uint256 bobBRRBalanceAfter = beraReserveToken.balanceOf(BOB);

        assertEq(bobBRRBalanceAfter, bobBRRBalanceBefore, "Bob should not receive any BRR");
    }

    function testRedeemFullyIfPercentVestedIs100() external {
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer USDC to BOB
        transferUSDC(BOB, 1_000e6);

        //approve USDC for deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), 1_000e6);
        usdcDepository.deposit(1_000e6, 1.2e18);
        vm.stopPrank();

        //(5 days) blocks later
        vm.roll(block.number + 216_000);

        uint256 bobBRRBalanceBefore = beraReserveToken.balanceOf(BOB);
        uint256 depositoryBRRBalanceBefore = beraReserveToken.balanceOf(address(usdcDepository));

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        (
            uint256 amountBondedAfter,
            uint256 payoutAfter,
            uint256 vestingAfter,
            uint256 lastBlockAfter,
            uint256 pricePaidAfter
        ) = usdcDepository.bondInfo(BOB);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);
        uint256 fee = (value * 100) / 10_000; // 1% fee

        uint256 payout = value - fee;

        uint256 bobBRRBalanceAfter = beraReserveToken.balanceOf(BOB);
        uint256 depositoryBRRBalanceAfter = beraReserveToken.balanceOf(address(usdcDepository));

        assertEq(bobBRRBalanceAfter, bobBRRBalanceBefore + payout, "Bob should receive full payout");
        assertEq(depositoryBRRBalanceAfter, depositoryBRRBalanceBefore - payout, "Depository should pay out BRR");
        assertEq(amountBondedAfter, 0, "Amount bonded mismatch");
        assertEq(payoutAfter, 0, "Payout mismatch");
        assertEq(vestingAfter, 0, "Vesting term mismatch");
        assertEq(lastBlockAfter, 0, "Last block mismatch");
        assertEq(pricePaidAfter, 0, "Price paid mismatch");
    }

    function testRedeemPartiallyIfPercentVestedIsLessThan100() external {
        updateTwapPrices();

        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer USDC to BOB
        transferUSDC(BOB, 1_000e6);

        //approve USDC for deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), 1_000e6);
        usdcDepository.deposit(1_000e6, 1.2e18);
        vm.stopPrank();

        uint256 depositoryBRRBalanceBefore = beraReserveToken.balanceOf(address(usdcDepository));

        // (2.5 days) blocks later
        vm.roll(block.number + 108_000);

        uint256 bobBRRBalanceBefore = beraReserveToken.balanceOf(BOB);

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        uint256 depositoryBRRBalanceAfter = beraReserveToken.balanceOf(address(usdcDepository));

        (
            uint256 amountBondedAfter,
            uint256 payoutAfter,
            uint256 vestingAfter,
            uint256 lastBlockAfter,
            uint256 pricePaidAfter
        ) = usdcDepository.bondInfo(BOB);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);
        uint256 fee = (value * 100) / 10_000; // 1% fee

        uint256 payout = value - fee;

        uint256 bobBRRBalanceAfter = beraReserveToken.balanceOf(BOB);

        assertEq(bobBRRBalanceAfter, bobBRRBalanceBefore + payout / 2, "Bob should receive partial payout");
        assertEq(depositoryBRRBalanceAfter, depositoryBRRBalanceBefore - (payout / 2), "Depository should pay out BRR");
        assertEq(amountBondedAfter, 1_000e6, "Amount bonded mismatch");
        assertEq(payoutAfter, payout / 2, "Payout mismatch");
        assertEq(vestingAfter, 108_000, "Vesting term mismatch");
        assertEq(lastBlockAfter, block.number, "Last block mismatch");

        uint256 currentPrice = simpleTwap.consult(1e9);
        assertEq(pricePaidAfter, getBondPrice(currentPrice, 50), "Price paid mismatch");
    }

    function testRedeemFullyAndCalledTwice() external {
        //initialize bond terms
        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 1000, 100, 50, 40_000e9);
        vm.stopPrank();

        //transfer USDC to BOB
        transferUSDC(BOB, 1_000e6);

        //approve USDC for deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), 1_000e6);
        usdcDepository.deposit(1_000e6, 1.2e18);
        vm.stopPrank();

        // (5 days) blocks later
        vm.roll(block.number + 216_000);

        uint256 bobBRRBalanceBefore = beraReserveToken.balanceOf(BOB);

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);
        uint256 fee = (value * 100) / 10_000; // 1% fee

        uint256 payout = value - fee;

        uint256 bobBRRBalanceAfter1stRedeem = beraReserveToken.balanceOf(BOB);

        assertEq(bobBRRBalanceAfter1stRedeem, bobBRRBalanceBefore + payout, "Bob should receive full payout");

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        uint256 bobBRRBalanceAfter2ndRedeem = beraReserveToken.balanceOf(BOB);

        assertEq(bobBRRBalanceAfter1stRedeem, bobBRRBalanceAfter2ndRedeem, "Bob should not receive any BRR");
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ_TESTS - DEPOSITS
    //////////////////////////////////////////////////////////////*/
    function testFuzzUSDCDepositShouldWorkCorrectly(uint256 amount, uint256 fee, uint256 discountRate) external {
        updateTwapPrices();

        fee = bound(fee, 0, 10_000);
        discountRate = bound(discountRate, 0, 10_000);

        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 2000, fee, discountRate, 40_000e9);
        vm.stopPrank();

        amount = bound(amount, 1e6, 200e6);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, amount);

        // Transfer USDC to BOB
        transferUSDC(BOB, amount);

        PreDepositState memory preDepositState = PreDepositState({
            daoBalance: beraReserveToken.balanceOf(address(feeDistributor)),
            treasuryBalance: IERC20(USDC_TOKEN).balanceOf(address(treasury)),
            totalDebt: usdcDepository.totalDebt(),
            brrSupply: beraReserveToken.totalSupply()
        });

        // Approve USDC and deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), amount);

        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else if (value > usdcDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else {
            usdcDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        PostDepositState memory postDepositState = PostDepositState({
            daoBalance: beraReserveToken.balanceOf(address(feeDistributor)),
            treasuryBalance: IERC20(USDC_TOKEN).balanceOf(address(treasury)),
            totalDebt: usdcDepository.totalDebt(),
            brrSupply: beraReserveToken.totalSupply()
        });

        uint256 feeAmount = (value * fee) / 10_000;
        uint256 expectedPayOut = value - feeAmount;

        if (value > usdcDepository.maxPayout()) return;
        assertEq(postDepositState.daoBalance, preDepositState.daoBalance + feeAmount, "DAO BRR balance mismatch");
        assertEq(postDepositState.treasuryBalance, preDepositState.treasuryBalance + amount, "Treasury USDC balance mismatch");
        assertEq(postDepositState.totalDebt, preDepositState.totalDebt + value, "Total debt mismatch");
        assertEq(postDepositState.brrSupply, preDepositState.brrSupply + value, "BRR total supply mismatch");

        (uint256 amountBonded, uint256 payout, , , uint256 pricePaid) = usdcDepository.bondInfo(BOB);
        assertEq(payout, expectedPayOut, "Payout mismatch");
        assertEq(amountBonded, amount, "Amount bonded mismatch");

        uint256 currentPrice = simpleTwap.consult(1e9);
        assertEq(pricePaid, getBondPrice(currentPrice, discountRate), "Price paid mismatch");
    }

    function testFuzzBRRHoneyDepositShouldWorkCorrectly(uint256 amount, uint256 fee, uint256 discountRate) external {
        updateTwapPrices();

        fee = bound(fee, 0, 10_000);
        discountRate = bound(discountRate, 0, 10_000);

        vm.startPrank(BERA_RESERVE_ADMIN);
        bRRHoneyDepository.initializeBondTerms(216_000, 2000, fee, discountRate, 40_000e9);
        vm.stopPrank();

        amount = bound(amount, 0.001e18, 0.07e18);

        (uint256 value, ) = bRRHoneyDepository.valueOf(uniswapV2Pair, amount);

        // Transfer LP to BOB
        transferLP(BOB, amount);

        PreDepositState memory preDepositState = PreDepositState({
            daoBalance: beraReserveToken.balanceOf(address(feeDistributor)),
            treasuryBalance: IERC20(uniswapV2Pair).balanceOf(address(treasury)),
            totalDebt: bRRHoneyDepository.totalDebt(),
            brrSupply: beraReserveToken.totalSupply()
        });

        // Approve LP and deposit
        vm.startPrank(BOB);
        IERC20(uniswapV2Pair).approve(address(bRRHoneyDepository), amount);

        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            bRRHoneyDepository.deposit(amount, 1.2e18);
        } else if (value > bRRHoneyDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            bRRHoneyDepository.deposit(amount, 1.2e18);
        } else {
            bRRHoneyDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        PostDepositState memory postDepositState = PostDepositState({
            daoBalance: beraReserveToken.balanceOf(address(feeDistributor)),
            treasuryBalance: IERC20(uniswapV2Pair).balanceOf(address(treasury)),
            totalDebt: bRRHoneyDepository.totalDebt(),
            brrSupply: beraReserveToken.totalSupply()
        });

        uint256 feeAmount = (value * fee) / 10_000;
        uint256 expectedPayOut = value - feeAmount;

        if (value > usdcDepository.maxPayout()) return;

        assertEq(postDepositState.daoBalance, preDepositState.daoBalance + feeAmount, "DAO BRR balance mismatch");
        assertEq(postDepositState.treasuryBalance, preDepositState.treasuryBalance + amount, "Treasury LP balance mismatch");
        assertEq(postDepositState.totalDebt, preDepositState.totalDebt + value, "Total debt mismatch");
        assertEq(postDepositState.brrSupply, preDepositState.brrSupply + value, "BRR total supply mismatch");

        {
            (uint256 amountBonded, uint256 payout, , , uint256 pricePaid) = bRRHoneyDepository.bondInfo(BOB);
            assertEq(payout, expectedPayOut, "Payout mismatch");
            assertEq(amountBonded, amount, "Amount bonded mismatch");
            uint256 currentPrice = simpleTwap.consult(1e9);
            assertEq(pricePaid, getBondPrice(currentPrice, discountRate), "Price paid mismatch");
        }
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ_TESTS - REDEEMS
    //////////////////////////////////////////////////////////////*/
    function testFuzzRedeemShouldWorkCorrectlyForUSDCDepository(
        uint256 amount,
        uint256 fee,
        uint256 discountRate,
        uint256 numberOfBlocksPassed
    ) external {
        fee = bound(fee, 0, 10_000);
        discountRate = bound(discountRate, 0, 10_000);
        numberOfBlocksPassed = bound(numberOfBlocksPassed, 0, 216_000);

        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 2000, fee, discountRate, 40_000e9);
        vm.stopPrank();

        amount = bound(amount, 1e6, 200e6);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, amount);

        // Transfer USDC to BOB
        transferUSDC(BOB, amount);

        // Approve USDC and deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), amount);

        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else if (value > usdcDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else {
            usdcDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        (, uint256 payoutBefore, uint256 vestingRemaining, , ) = usdcDepository.bondInfo(BOB);

        // (5 days) blocks later
        vm.roll(block.number + numberOfBlocksPassed);

        PreRedeemState memory preRedeemState = PreRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(usdcDepository))
        });

        if (value > usdcDepository.maxPayout()) return;

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        PostRedeemState memory postRedeemState = PostRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(usdcDepository))
        });

        uint256 expectedPayOut = expectedPayOutPerBlocksPassed(vestingRemaining, numberOfBlocksPassed, payoutBefore);

        assertEq(postRedeemState.bobBRRBalance, preRedeemState.bobBRRBalance + expectedPayOut, "Bob should receive BRR");
        assertEq(
            postRedeemState.depositoryBRRBalance,
            preRedeemState.depositoryBRRBalance - expectedPayOut,
            "Depository should pay out BRR"
        );
    }

    function testFuzzMultipleUsersRedeemShouldWorkCorrectlyForUSDCDepository(
        uint256 amount,
        uint256 fee,
        uint256 discountRate,
        uint256 numberOfBlocksPassed
    ) external {
        fee = bound(fee, 0, 10_000);
        discountRate = bound(discountRate, 0, 10_000);
        numberOfBlocksPassed = bound(numberOfBlocksPassed, 0, 216_000);

        vm.startPrank(BERA_RESERVE_ADMIN);
        usdcDepository.initializeBondTerms(216_000, 2000, fee, discountRate, 40_000e9);
        vm.stopPrank();

        amount = bound(amount, 1e6, 200e6);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, amount);

        // Transfer USDC to BOB
        transferUSDC(BOB, amount);

        // Approve USDC and deposit
        vm.startPrank(BOB);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), amount);

        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else if (value > usdcDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else {
            usdcDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        vm.roll(block.number + numberOfBlocksPassed);

        // Transfer USDC to ALICE
        transferUSDC(ALICE, amount);

        // Approve USDC and deposit
        vm.startPrank(ALICE);
        IERC20(USDC_TOKEN).approve(address(usdcDepository), amount);
        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else if (value > usdcDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            usdcDepository.deposit(amount, 1.2e18);
        } else {
            usdcDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        if (value > usdcDepository.maxPayout()) return;

        (, uint256 bobPayoutBefore, uint256 bobVestingRemaining, , ) = usdcDepository.bondInfo(BOB);
        (, uint256 alicePayoutBefore, uint256 aliceVestingRemaining, , ) = usdcDepository.bondInfo(ALICE);

        PreMultiRedeemState memory preRedeemState = PreMultiRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            aliceBRRBalance: beraReserveToken.balanceOf(ALICE),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(usdcDepository))
        });

        vm.roll(block.number + numberOfBlocksPassed);

        vm.startPrank(BOB);
        usdcDepository.redeem();
        vm.stopPrank();

        vm.startPrank(ALICE);
        usdcDepository.redeem();
        vm.stopPrank();

        PreMultiRedeemState memory postRedeemState = PreMultiRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            aliceBRRBalance: beraReserveToken.balanceOf(ALICE),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(usdcDepository))
        });
        uint256 expectedBobPayOut = expectedPayOutPerBlocksPassed(bobVestingRemaining, 2 * numberOfBlocksPassed, bobPayoutBefore);

        uint256 expectedAlicePayOut = expectedPayOutPerBlocksPassed(aliceVestingRemaining, numberOfBlocksPassed, alicePayoutBefore);
        assertEq(postRedeemState.bobBRRBalance, preRedeemState.bobBRRBalance + expectedBobPayOut, "Bob should receive BRR");
        assertEq(postRedeemState.aliceBRRBalance, preRedeemState.aliceBRRBalance + expectedAlicePayOut, "Alice should receive BRR");
        assertEq(
            postRedeemState.depositoryBRRBalance,
            preRedeemState.depositoryBRRBalance - (expectedBobPayOut + expectedAlicePayOut),
            "Depository should pay out BRR"
        );
    }

    function testFuzzRedeemShouldWorkCorrectlyForBRRHoneyDepository(
        uint256 amount,
        uint256 fee,
        uint256 discountRate,
        uint256 numberOfBlocksPassed
    ) external {
        fee = bound(fee, 0, 10_000);
        discountRate = bound(discountRate, 0, 10_000);
        numberOfBlocksPassed = bound(numberOfBlocksPassed, 0, 216_000);

        vm.startPrank(BERA_RESERVE_ADMIN);
        bRRHoneyDepository.initializeBondTerms(216_000, 2000, fee, discountRate, 40_000e9);
        vm.stopPrank();

        amount = bound(amount, 0.001e18, 0.07e18);

        (uint256 value, ) = bRRHoneyDepository.valueOf(uniswapV2Pair, amount);

        // Transfer LP to BOB
        transferLP(BOB, amount);

        // Approve LP and deposit
        vm.startPrank(BOB);
        IERC20(uniswapV2Pair).approve(address(bRRHoneyDepository), amount);

        if (value > 40_000e9) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondSoldOut.selector);
            bRRHoneyDepository.deposit(amount, 1.2e18);
        } else if (value > bRRHoneyDepository.maxPayout()) {
            vm.expectRevert(BeraReserveBondDepositoryV2.BondTooLarge.selector);
            bRRHoneyDepository.deposit(amount, 1.2e18);
        } else {
            bRRHoneyDepository.deposit(amount, 1.2e18);
        }

        vm.stopPrank();

        (, uint256 payoutBefore, uint256 vestingRemaining, , ) = bRRHoneyDepository.bondInfo(BOB);

        // (5 days) blocks later
        vm.roll(block.number + numberOfBlocksPassed);

        PreRedeemState memory preRedeemState = PreRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(bRRHoneyDepository))
        });

        if (value > usdcDepository.maxPayout()) return;

        vm.startPrank(BOB);
        bRRHoneyDepository.redeem();
        vm.stopPrank();

        PostRedeemState memory postRedeemState = PostRedeemState({
            bobBRRBalance: beraReserveToken.balanceOf(BOB),
            depositoryBRRBalance: beraReserveToken.balanceOf(address(bRRHoneyDepository))
        });
        uint256 expectedPayOut = expectedPayOutPerBlocksPassed(vestingRemaining, numberOfBlocksPassed, payoutBefore);
        assertEq(postRedeemState.bobBRRBalance, preRedeemState.bobBRRBalance + expectedPayOut, "Bob should receive BRR");
        assertEq(
            postRedeemState.depositoryBRRBalance,
            preRedeemState.depositoryBRRBalance - expectedPayOut,
            "Depository should pay out BRR"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function transferUSDC(address to, uint256 amount) internal {
        vm.startPrank(USDC_WHALE);
        IERC20(USDC_TOKEN).transfer(to, amount);
        vm.stopPrank();
    }

    function transferLP(address to, uint256 amount) internal {
        vm.startPrank(BERA_RESERVE_LIQUIDITY_WALLET);
        IERC20(uniswapV2Pair).transfer(to, amount);
        vm.stopPrank();
    }

    function updateTwapPrices() internal {
        skip(1 hours);
        vm.prank(HONEY_WHALE);
        IERC20(HONEY_TOKEN).transfer(BERA_RESERVE_WORKER, 1_000e18);

        vm.prank(BERA_RESERVE_WORKER);
        //approve honey
        IERC20(HONEY_TOKEN).approve(address(uniswapRouter), 1_000e18);

        address[] memory path = new address[](2);
        path[0] = HONEY_TOKEN;
        path[1] = address(beraReserveToken);

        vm.startPrank(BERA_RESERVE_WORKER);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            100e18,
            10e9,
            path,
            BERA_RESERVE_WORKER,
            block.timestamp + 1000
        );

        vm.stopPrank();

        simpleTwap.update();

        console2.log("Price After Update", simpleTwap.consult(1e9));
    }

    function getBondPrice(uint256 price, uint256 discountRate) public pure returns (uint256) {
        return (price * (10_000 - discountRate)) / 10_000;
    }

    function expectedPayOutPerBlocksPassed(uint256 vestingTerm, uint256 blocksPassed, uint256 payout) public pure returns (uint256) {
        uint256 calculateVestPercentage = (blocksPassed * 10_000) / vestingTerm;
        if (calculateVestPercentage > 10_000) {
            return payout;
        } else if (calculateVestPercentage == 0) {
            return 0;
        } else {
            return (payout * calculateVestPercentage) / 10_000;
        }
    }
}
