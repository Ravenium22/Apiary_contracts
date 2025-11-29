// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

// import { Test, console ,console2} from "forge-std/Test.sol";
// import { BeraReserveBaseTest } from "./setup/BeraReserveBase.t.sol";
// import { IERC20 } from "forge-std/interfaces/IERC20.sol";
// import { BeraReserveStaking } from "src/Staking.sol";
// import { BeraReserveBondDepository } from "src/BondDepository.sol";
// import { BeraReserveTreasury } from "src/Treasury.sol";

// contract BeraReserveUSDCBondDepositoryTest is BeraReserveBaseTest {
//     function setUp() public override {
//         super.setUp();

//         console.log("BRR Supply", beraReserveToken.totalSupply());
//     }

//     function testBuyBRRBonds() public {
//         mintUSDC(10_000e6, "ALICE");
//         vm.startPrank(makeAddr("ALICE"));
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 1_500e6);
//         usdcBondDepository.deposit(100e6, 10_000, makeAddr("ALICE"));

//         usdcBondDepository.deposit(100e6, 10_000, makeAddr("ALICE"));

//         usdcBondDepository.deposit(150e6, 10_000, ALICE);

//         usdcBondDepository.deposit(150e6, 10_000, ALICE);
//         vm.stopPrank();
//     }

//     function testFuzz_BondPurchases(uint256 numOfPurchases, uint256 amount) public {
//         numOfPurchases = bound(numOfPurchases, 1, 10);
//         amount = bound(amount, 1e6, 150e6);

//         mintToUsers(numOfPurchases, amount);

//         for (uint256 i = 0; i < numOfPurchases; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));

//             uint256 currentPrice = usdcBondDepository.bondPriceInUSD();

//             vm.prank(user);
//             usdcBondDepository.deposit(amount, 500_000, user);

//             (uint256 amountBonded, uint256 payout, uint256 vesting, uint256 lastBlock, uint256 pricePaid) =
//                 usdcBondDepository.bondInfo(user);

//             //assertions
//             assertEq(amountBonded, amount, "Amount bonded should be equal to amount");
//             uint256 calculatedPayout = (amount * 1e9) / currentPrice;
//             assertEq(payout, calculatedPayout, "Payout should be equal to calculatedPayout");
//             assertEq(vesting, 216_000, "Vesting should be equal to 216000(~5 days)");
//             assertEq(lastBlock, block.number, "Last block should be equal to block number");
//             assertEq(pricePaid, currentPrice, "Price paid should be equal to current price");
//         }
//         vm.stopPrank();
//     }

//     function testFuzz_ClaimPayOutsAndStake(uint256 numOfPurchases, uint256 amount) public {
//         numOfPurchases = bound(numOfPurchases, 1, 10);
//         amount = bound(amount, 1e6, 150e6);
//         mintToUsers(numOfPurchases, amount);

//         for (uint256 i = 0; i < numOfPurchases; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));
//             vm.prank(user);
//             usdcBondDepository.deposit(amount, 500_000, user);
//         }

//         //rebasing hasn't occurred yet
//         vm.roll(block.number + 10_000);

//         for (uint256 i = 0; i < numOfPurchases; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));
//             vm.prank(user);
//             usdcBondDepository.redeem(user, true);
//         }
//     }

//     function testFuzz_ClaimPayOutsNoStaking(uint256 numOfPurchases, uint256 amount) public {
//         numOfPurchases = bound(numOfPurchases, 1, 10);
//         amount = bound(amount, 1e6, 150e6);
//         mintToUsers(numOfPurchases, amount);

//         for (uint256 i = 0; i < numOfPurchases; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));
//             vm.prank(user);
//             usdcBondDepository.deposit(amount, 500_000, user);
//         }

//         //rebasing hasn't occurred yet
//         vm.roll(block.number + 10_000);

//         for (uint256 i = 0; i < numOfPurchases; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));

//             (, uint256 payout, uint256 vesting, uint256 lastBlock,) = usdcBondDepository.bondInfo(user);

//             //check brr balance before redeem
//             uint256 brrBalanceBefore = beraReserveToken.balanceOf(user);

//             vm.prank(user);
//             usdcBondDepository.redeem(user, false);

//             uint256 percentVested = ((block.number - lastBlock) * 10000) / vesting;

//             uint256 claimableAmount = (percentVested * payout) / 10000;

//             //check brr balance after redeem
//             uint256 brrBalanceAfter = beraReserveToken.balanceOf(user);
//             assertEq(brrBalanceAfter, brrBalanceBefore + claimableAmount);
//         }
//     }

//     /**
//      * Control Variable Testing
//      */
//     //   function testControlVariableAdjustmentAdding() public mintUSDC(10_000e6, ALICE) {
//     //     vm.roll(block.number + 17);

//     //     vm.startPrank(BERA_RESERVE_ADMIN);
//     //     usdcBondDepository.setAdjustment(true, 5, 10, 2);

//     //     BeraReserveBondDepository.Terms memory termsPrior = usdcBondDepository.getTerms();

//     //     vm.startPrank(ALICE);
//     //     usdc.approve(address(usdcBondDepository), 1_700e6);

//     //     vm.roll(block.number + 10);

//     //     usdcBondDepository.deposit(100e6, 14500500, ALICE);

//     //     BeraReserveBondDepository.Terms memory termsAfter = usdcBondDepository.getTerms();

//     //     assertEq(termsAfter.controlVariable, termsPrior.controlVariable + 5);
//     // }

//     // function testControlVariableAdjustmentMoreThanTarget() public mintUSDC(10_000e6, ALICE) {
//     //     vm.roll(block.number + 17);

//     //     vm.startPrank(BERA_RESERVE_ADMIN);
//     //     usdcBondDepository.setAdjustment(true, 5, 11, 2);

//     //     vm.startPrank(ALICE);
//     //     usdc.approve(address(usdcBondDepository), 100e6);

//     //     vm.roll(block.number + 10);

//     //     usdcBondDepository.deposit(100e6, 14500500, ALICE);

//     //     BeraReserveBondDepository.Terms memory termsAfter = usdcBondDepository.getTerms();

//     //     assertEq(termsAfter.controlVariable, 11);
//     // }

//     // function testControlVariableAdjustmentSub() public mintUSDC(10_000e6, ALICE) {
//     //     vm.roll(block.number + 17);

//     //     vm.startPrank(BERA_RESERVE_ADMIN);
//     //     usdcBondDepository.setAdjustment(false, 5, 11, 2);

//     //     BeraReserveBondDepository.Terms memory termsPrior = usdcBondDepository.getTerms();

//     //     vm.startPrank(ALICE);
//     //     usdc.approve(address(usdcBondDepository), 100e6);

//     //     vm.roll(block.number + 10);

//     //     usdcBondDepository.deposit(100e6, 14500500, ALICE);

//     //     BeraReserveBondDepository.Terms memory termsAfter = usdcBondDepository.getTerms();

//     //     assertEq(termsAfter.controlVariable, termsPrior.controlVariable - 5);
//     // }

//     // function testControlVariableAdjustmentLessThanTarget() public mintUSDC(10_000e6, ALICE) {
//     //     vm.roll(block.number + 17);

//     //     vm.startPrank(BERA_RESERVE_ADMIN);
//     //     usdcBondDepository.setAdjustment(false, 5, 1, 1);

//     //     vm.startPrank(ALICE);
//     //     usdc.approve(address(usdcBondDepository), 100e6);

//     //     vm.roll(block.number + 10);

//     //     usdcBondDepository.deposit(100e6, 14500500, ALICE);

//     //     BeraReserveBondDepository.Terms memory termsAfter = usdcBondDepository.getTerms();

//     //     assertEq(termsAfter.controlVariable, 1);
//     // }

//     /**
//      * REBASING TESTS
//      */
//     function testRebasing_sBRR() public {
//         mintUSDC(250_000e6, "ALICE");
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(ALICE, 150e6, 1349918559, 1);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 40);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 55); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(200_000e6, "BOB");
//         vm.startPrank(BOB);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 200_000e6);
//         depositMultiple(BOB, 150e6, 1349918559, 60); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(180_000e6, "CHARLIE");
//         vm.startPrank(CHARLIE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 180_000e6);
//         depositMultiple(CHARLIE, 150e6, 1349918559, 70);
//         // depositMultiple(CHARLIE, 150e6, 1349918559, 38); // Combined all repetitive deposits
//         vm.stopPrank();

//         console.log("Treasury total reserve", treasury.totalReserves());
//         console.log("TS", beraReserveToken.totalSupply());

//         // console.log("First Rebasing....................");
//         redeemAndStake();
//         redeemAndStake();
//         redeemAndStake();
//         redeemAndStake();
//     }

//     /**
//      * Invariant Rebasing Tests
//      */

//     //Invariant Tests: Total supply increases only by the rebase amount during staking epochs.
//     function testRebasingIncreasesTotalSupply() public {
//         mintUSDC(250_000e6, "ALICE");
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(ALICE, 150e6, 1349918559, 1);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 40);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 55); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(200_000e6, "BOB");
//         vm.startPrank(BOB);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 200_000e6);
//         depositMultiple(BOB, 150e6, 1349918559, 60); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(180_000e6, "CHARLIE");
//         vm.startPrank(CHARLIE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 180_000e6);
//         depositMultiple(CHARLIE, 150e6, 1349918559, 70);
//         // depositMultiple(CHARLIE, 150e6, 1349918559, 38); // Combined all repetitive deposits
//         vm.stopPrank();

//         uint256 totalSupplyBefore = beraReserveToken.totalSupply();

//         redeemAndStake();

//         uint256 totalSupplyAfter = beraReserveToken.totalSupply();
//         assertGt(totalSupplyAfter, totalSupplyBefore);
//     }

//     //Invariant: If the rebase rate is set to zero, staking should no longer mint tokens.
//     function testRebasingShouldNotMintNewTokensIfRewardRateIsZero() public {
//         mintUSDC(250_000e6, "ALICE");
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(ALICE, 150e6, 1349918559, 1);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 40);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 55); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(200_000e6, "BOB");
//         vm.startPrank(BOB);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 200_000e6);
//         depositMultiple(BOB, 150e6, 1349918559, 60); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(180_000e6, "CHARLIE");
//         vm.startPrank(CHARLIE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 180_000e6);
//         depositMultiple(CHARLIE, 150e6, 1349918559, 70);
//         // depositMultiple(CHARLIE, 150e6, 1349918559, 38); // Combined all repetitive deposits
//         vm.stopPrank();

//         vm.startPrank(BERA_RESERVE_ADMIN);
//         distributor.removeRecipient(0, address(staking));
//         vm.stopPrank();

//         uint256 totalSupplyBefore = beraReserveToken.totalSupply();

//         redeemAndStake();

//         uint256 totalSupplyAfter = beraReserveToken.totalSupply();
//         assertEq(totalSupplyAfter, totalSupplyBefore);
//     }

//     //Invariant: The total amount of BRR sold via bonds must not exceed the 20% cap(40_000e9) unless explicitly increased.
//     function testShouldFailIfBondingExceeds20PercentCap() public {
//         mintUSDC(250_000e6, "ALICE");
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(ALICE, 150e6, 1349918559, 1);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 40);
//         skip(5 hours);
//         depositMultiple(ALICE, 150e6, 1349918559, 55); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(200_000e6, "BOB");
//         vm.startPrank(BOB);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 200_000e6);
//         depositMultiple(BOB, 150e6, 1349918559, 60); // Combined all repetitive deposits
//         vm.stopPrank();

//         mintUSDC(180_000e6, "CHARLIE");
//         vm.startPrank(CHARLIE);

//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 180_000e6);

//         depositMultiple(CHARLIE, 170e6, 1349918559, 97);
//         vm.stopPrank();

//         vm.startPrank(CHARLIE);

//         usdcBondDepository.deposit(170e6, 1349918559, CHARLIE);

//         vm.expectRevert("Bond max capacity reached");
//         usdcBondDepository.deposit(170e6, 1349918559, CHARLIE);
//         vm.stopPrank();
//     }

//     /**
//      * test not excess reserves for rebase
//      */
//     function testNotExcessReservesForRebase() public {
//         mintUSDC(250_000e6, "ALICE");
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(ALICE, 200e6, 1349918559, 1);
//         vm.stopPrank();

//         skip(5 hours);

//         mintUSDC(250_000e6, "BOB");

//         vm.startPrank(BOB);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 250_000e6);
//         depositMultiple(BOB, 200e6, 1349918559, 1);
//         vm.stopPrank();

//         console2.log("Staking BRR balance", beraReserveToken.balanceOf(address(staking)));

//         console.log("First rebase");

//         redeemAndStake();

//         console.log("Staking BRR balance", beraReserveToken.balanceOf(address(staking)));

//         console.log("Second rebase");

//         vm.roll(block.number + 14_400);

//         vm.startPrank(ALICE);
//         usdcBondDepository.redeem(ALICE, true);
//         vm.stopPrank();

//         vm.startPrank(BOB);
//         usdcBondDepository.redeem(BOB, true);
//         vm.stopPrank();

//         console.log("Staking BRR balance", beraReserveToken.balanceOf(address(staking)));

//         // console.log("Third rebase");

//         // vm.roll(block.number + 14_400);

//         // vm.startPrank(ALICE);
//         // usdcBondDepository.redeem(ALICE, true);
//         // vm.stopPrank();

//         // vm.startPrank(BOB);
//         // usdcBondDepository.redeem(BOB, true);
//         // vm.stopPrank();

//     }

//     /**
//      * HELPERS
//      */
//     function mintToUsers(uint256 numOfUsers, uint256 amount) public {
//         for (uint256 i = 0; i < numOfUsers; i++) {
//             address user = makeAddr(string(abi.encodePacked("user", i)));
//             vm.prank(USDC_WHALE);
//             IERC20(USDC_TOKEN).transfer(user, amount);

//             vm.prank(user);
//             IERC20(USDC_TOKEN).approve(address(usdcBondDepository), amount);
//         }
//     }

//     function depositMultiple(address user, uint256 amount, uint256 expiry, uint256 times) internal {
//         for (uint256 i = 0; i < times; i++) {
//             usdcBondDepository.deposit(amount, expiry, user);
//             skip(5 hours);
//         }
//     }

//     function redeemAndStake() internal {
//         vm.roll(block.number + 14_400);

//         vm.startPrank(ALICE);
//         usdcBondDepository.redeem(ALICE, true);
//         vm.stopPrank();

//         vm.startPrank(BOB);
//         usdcBondDepository.redeem(BOB, true);
//         vm.stopPrank();

//         // vm.prank(CHARLIE);
//         // usdcBondDepository.redeem(CHARLIE, true);

//         // vm.roll(block.number + 14_400);

//         // vm.prank(ALICE);
//         // staking.claim(ALICE);

//         // vm.prank(BOB);
//         // staking.claim(BOB);

//         // vm.prank(CHARLIE);
//         // staking.claim(CHARLIE);

//         // console.log("BOB sBRR Balance", sBeraReserveToken.balanceOf(BOB));
//         // console.log("Alice sBRR Balance", sBeraReserveToken.balanceOf(ALICE));
//         // console.log("Charlie sBRR Balance", sBeraReserveToken.balanceOf(CHARLIE));
//     }

//     function mintUSDC(uint256 amount, string memory name) public {
//         skip(5 minutes);
//         vm.prank(USDC_WHALE);
//         IERC20(USDC_TOKEN).transfer(makeAddr(name), amount);
//     }
// }
