// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

// import { Test, console } from "lib/forge-std/src/Test.sol";
// import { BeraReserveBaseTest } from "./setup/BeraReserveBase.t.sol";
// import { BeraReserveTreasury } from "src/Treasury.sol";
// import { IERC20 } from "forge-std/interfaces/IERC20.sol";

// contract TreasuryTest is BeraReserveBaseTest {
//     function setUp() public virtual override {
//         super.setUp();

//         vm.startPrank(BERA_RESERVE_ADMIN);
//         treasury.queue(BeraReserveTreasury.MANAGING.DEBTOR, DEBTOR);
//         treasury.queue(BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN, uniswapV2Pair);

//         vm.roll(block.number + 2);

//         treasury.toggle(BeraReserveTreasury.MANAGING.DEBTOR, DEBTOR, address(0));
//         treasury.toggle(BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN, uniswapV2Pair, address(0));

//         vm.stopPrank();
//     }

//     function testIfDebtorTransferAmountIsGreaterThanDebt() public {
//         //transfer sBRR to debtor
//         vm.startPrank(address(staking));
//         sBeraReserveToken.transfer(DEBTOR, 100e9);
//         vm.stopPrank();

//         mintUSDC(10_000e6, "ALICE");
//         //user buys some bonds to increase treasury value
//         vm.startPrank(ALICE);
//         IERC20(USDC_TOKEN).approve(address(usdcBondDepository), 1_500e6);
//         usdcBondDepository.deposit(100e6, 1349918559, ALICE);
//         vm.stopPrank();

//         //debtor borrows some funds
//         vm.startPrank(DEBTOR);
//         treasury.incurDebt(50e6, USDC_TOKEN);
//         vm.stopPrank();

//         //debtor tries to transfer 60 sBRR should fail cuz there's a debt of 50 sBRR
//         //debtor should only be able to transfer only 50 sBRR or less.
//         vm.startPrank(DEBTOR);

//         vm.expectRevert(bytes("!REPAY_DEBT"));
//         sBeraReserveToken.transfer(ALICE, 60e9);
//         vm.stopPrank();
//     }

//     function testIfAReserveTokenIsAddedAsLiquidityToken() public {
//         BeraReserveTreasury.MANAGING lT_TOKEN = BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN;

//         vm.startPrank(BERA_RESERVE_ADMIN);
//         treasury.queue(lT_TOKEN, USDC_TOKEN);

//         vm.roll(block.number + 2);

//         vm.expectRevert(bytes("TOKEN IS RESERVE TOKEN"));
//         treasury.toggle(lT_TOKEN, USDC_TOKEN, address(0));
//         vm.stopPrank();
//     }

//     function testIfALiquidityTokenIsAddedAsReserveToken() public {
//         BeraReserveTreasury.MANAGING reserveToken = BeraReserveTreasury.MANAGING.RESERVETOKEN;

//         vm.startPrank(BERA_RESERVE_ADMIN);
//         treasury.queue(reserveToken, address(uniswapV2Pair));

//         vm.roll(block.number + 2);

//         vm.expectRevert(bytes("TOKEN IS LIQUIDITY TOKEN"));
//         treasury.toggle(reserveToken, address(uniswapV2Pair), address(0));
//         vm.stopPrank();
//     }

//     function mintUSDC(uint256 amount, string memory name) public {
//         skip(5 minutes);
//         vm.prank(USDC_WHALE);
//         IERC20(USDC_TOKEN).transfer(makeAddr(name), amount);
//     }
// }
