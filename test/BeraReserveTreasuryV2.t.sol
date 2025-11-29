// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console2 } from "lib/forge-std/src/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BeraReserveTreasuryV2 } from "../src/BeraReserveTreasuryV2.sol";

contract BeraReserveTreasuryV2Test is BeraReserveBaseTestV2 {
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public virtual override {
        super.setUp();
        vm.roll(4_654_157);
    }

    error OwnableUnauthorizedAccount(address account);

    /*//////////////////////////////////////////////////////////////
                       NORMAL TESTS - CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testBrrTokensIsSetCorrectly() external view {
        assertEq(address(treasury.BRR_TOKEN()), address(beraReserveToken), "BRR_TOKEN is not set correctly");
    }

    function testUSDCIsSetCorrectly() external view {
        assertEq(treasury.isReserveToken(USDC_TOKEN), true, "USDC_TOKEN is not set correctly");
    }

    function testLPTokenIsSetCorrectly() external view {
        assertEq(treasury.isLiquidityToken(uniswapV2Pair), true, "LP_TOKEN is not set correctly");
    }

    /*//////////////////////////////////////////////////////////////
                     NORMAL TESTS - OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testShouldFailSetReservesManagerIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        treasury.setReservesManager(ALICE);
    }

    function testSetReservesManager() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReservesManager(ALICE);

        assertEq(treasury.reservesManager(), ALICE, "Reserves manager is not set correctly");
    }

    function testShouldFailSetReserveDepositorIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        treasury.setReserveDepositor(ALICE, true);
    }

    function testSetReserveDepositor() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveDepositor(ALICE, true);

        assertEq(treasury.isReserveDepositor(ALICE), true, "Reserve depositor is not set correctly");
    }

    function testShouldFailSetLiquidityDepositorIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        treasury.setLiquidityDepositor(ALICE, true);
    }

    function testSetLiquidityDepositor() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setLiquidityDepositor(ALICE, true);

        assertEq(treasury.isLiquidityDepositor(ALICE), true, "Liquidity depositor is not set correctly");
    }

    function testShouldFailSetReserveTokenIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        treasury.setReserveToken(DAI, true);
    }

    function testSetReserveToken() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveToken(DAI, true);

        assertEq(treasury.isReserveToken(DAI), true, "Reserve token is not set correctly");
    }

    function testSetLiquidityToken() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setLiquidityToken(DAI, true);

        assertEq(treasury.isLiquidityToken(DAI), true, "Liquidity token is not set correctly");
    }

    function testShouldFailSetLiquidityTokenIfNotOwner() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ALICE));
        treasury.setLiquidityToken(DAI, true);
    }

    /*//////////////////////////////////////////////////////////////
                        NORMAL TESTS - DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function testShouldFailDepositWithInvalidReserveToken() external {
        vm.startPrank(ALICE);

        vm.expectRevert(BeraReserveTreasuryV2.InvalidToken.selector);
        treasury.deposit(1_000e18, DAI, 0);
    }

    function testShouldFailDepositWithInvalidLiquidityToken() external {
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReserveTreasuryV2.InvalidToken.selector);
        treasury.deposit(1_000e18, DAI, 0);
    }

    function testShouldFailDepositWithInvalidReserveDepositor() external {
        vm.startPrank(ALICE);

        vm.expectRevert(BeraReserveTreasuryV2.InvalidReserveDepositor.selector);
        treasury.deposit(1_000e6, USDC_TOKEN, 0);
    }

    function testShouldFailDepositWithInvalidLiquidityDepositor() external {
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReserveTreasuryV2.InvalidLiquidityDepositor.selector);
        treasury.deposit(1_000e18, uniswapV2Pair, 0);
    }

    function testDepositReserveToken() external {
        transferUSDC(ALICE, 2_000e6);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveDepositor(ALICE, true);

        uint256 totalSupplyBefore = beraReserveToken.totalSupply();

        vm.startPrank(ALICE);
        IERC20(USDC_TOKEN).approve(address(treasury), 2_000e6);

        (uint256 value1, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);

        treasury.deposit(1_000e6, USDC_TOKEN, value1);

        assertEq(value1, 1_000e9, "Deposit value is not correct");

        (uint256 value2, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);

        treasury.deposit(1_000e6, USDC_TOKEN, value1);

        assertEq(treasury.totalReserves(USDC_TOKEN), 2_000e6, "Total reserves is not correct");

        assertEq(beraReserveToken.balanceOf(ALICE), value1 + value2, "BRR_TOKEN balance is not correct");

        assertEq(beraReserveToken.totalSupply(), totalSupplyBefore + value1 + value2, "BRR_TOKEN total supply is not correct");
    }

    function testDepositLiquidityToken() external {
        transferLP(ALICE, 0.2e18);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setLiquidityDepositor(ALICE, true);

        uint256 totalSupplyBefore = beraReserveToken.totalSupply();

        vm.startPrank(ALICE);
        IERC20(uniswapV2Pair).approve(address(treasury), 0.2e18);

        (uint256 value, ) = usdcDepository.valueOf(uniswapV2Pair, 0.2e18);

        treasury.deposit(0.2e18, uniswapV2Pair, value);

        assertEq(treasury.totalReserves(uniswapV2Pair), 0.2e18, "Total reserves is not correct");
        assertEq(beraReserveToken.totalSupply(), totalSupplyBefore + value, "BRR_TOKEN total supply is not correct");
    }

    /*//////////////////////////////////////////////////////////////
                     NORMAL TESTS - MANAGE RESERVES
    //////////////////////////////////////////////////////////////*/
    function testShouldFailborrowReservesIfNotReserveManager() external {
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReserveTreasuryV2.UnAuthorizedReserveManager.selector);
        treasury.borrowReserves(1_000e6, USDC_TOKEN);
    }

    function testShouldFailborrowReservesIfNotReserveToken() external {
        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReservesManager(ALICE);

        vm.startPrank(ALICE);
        vm.expectRevert(BeraReserveTreasuryV2.InvalidToken.selector);
        treasury.borrowReserves(1_000e6, DAI);
    }

    function testborrowReservesWithReserveToken() external {
        transferUSDC(ALICE, 2_000e6);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveDepositor(ALICE, true);

        vm.startPrank(ALICE);
        IERC20(USDC_TOKEN).approve(address(treasury), 2_000e6);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);

        treasury.deposit(1_000e6, USDC_TOKEN, value);

        assertEq(value, 1_000e9, "Deposit value is not correct");

        vm.stopPrank();

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReservesManager(ALICE);

        vm.startPrank(ALICE);
        treasury.borrowReserves(500e6, USDC_TOKEN);

        assertEq(beraReserveToken.balanceOf(ALICE), 1_000e9, "BRR_TOKEN balance is not correct");

        assertEq(treasury.totalReserves(USDC_TOKEN), 500e6, "Total reserves is not correct");

        assertEq(IERC20(USDC_TOKEN).balanceOf(ALICE), 1_500e6, "USDC_TOKEN balance is not correct");
    }

    function testRepayReservesWithReserveToken() external {
        transferUSDC(ALICE, 2_000e6);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveDepositor(ALICE, true);

        vm.startPrank(ALICE);
        IERC20(USDC_TOKEN).approve(address(treasury), 2_000e6);

        (uint256 value, ) = usdcDepository.valueOf(USDC_TOKEN, 1_000e6);

        treasury.deposit(1_000e6, USDC_TOKEN, value);

        assertEq(value, 1_000e9, "Deposit value is not correct");

        vm.stopPrank();

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReservesManager(ALICE);

        uint256 totalAmountBorrowedPrior = treasury.totalBorrowed(USDC_TOKEN);
        uint256 totalReservesPrior = treasury.totalReserves(USDC_TOKEN);

        vm.startPrank(ALICE);
        treasury.borrowReserves(500e6, USDC_TOKEN);

        uint256 totalAmountBorrowedAfter = treasury.totalBorrowed(USDC_TOKEN);
        uint256 totalReservesAfter = treasury.totalReserves(USDC_TOKEN);

        assertEq(totalAmountBorrowedAfter, totalAmountBorrowedPrior + 500e6, "!Total Borrowed");

        assertEq(totalReservesAfter, totalReservesPrior - 500e6, "!Total Reserves");

        treasury.repayReserves(500e6, USDC_TOKEN);

        uint256 totalAmountBorrowedAfterRepay = treasury.totalBorrowed(USDC_TOKEN);
        uint256 totalReservesAfterRepay = treasury.totalReserves(USDC_TOKEN);

        assertEq(totalAmountBorrowedAfterRepay, totalAmountBorrowedAfter - 500e6, "!Total Borrowed");
        assertEq(totalReservesAfterRepay, totalReservesAfter + 500e6, "!Total Reserves");
    }

    function testborrowReservesWithLiquidityToken() external {
        transferLP(ALICE, 0.2e18);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setLiquidityDepositor(ALICE, true);

        vm.startPrank(ALICE);
        IERC20(uniswapV2Pair).approve(address(treasury), 0.2e18);

        (uint256 value, ) = bRRHoneyDepository.valueOf(uniswapV2Pair, 0.2e18);

        treasury.deposit(0.2e18, uniswapV2Pair, value);

        vm.stopPrank();

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReservesManager(ALICE);

        uint256 totalReservesBefore = treasury.totalReserves(uniswapV2Pair);

        vm.startPrank(ALICE);
        treasury.borrowReserves(0.16e18, uniswapV2Pair);

        assertEq(beraReserveToken.balanceOf(ALICE), value, "BRR_TOKEN balance is not correct");
        assertLt(treasury.totalReserves(uniswapV2Pair), totalReservesBefore, "Total reserves is not correct");
        assertEq(IERC20(uniswapV2Pair).balanceOf(ALICE), 0.16e18, "uniswapV2Pair balance is not correct");
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ_TESTS - DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function testFuzzDepositReserveToken(uint256 amount) external {
        amount = bound(amount, 1e6, 10_000e6);

        transferUSDC(ALICE, amount);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setReserveDepositor(ALICE, true);

        uint256 totalSupplyBefore = beraReserveToken.totalSupply();

        vm.startPrank(ALICE);
        IERC20(USDC_TOKEN).approve(address(treasury), amount);

        (uint256 value1, ) = usdcDepository.valueOf(USDC_TOKEN, amount);

        treasury.deposit(amount, USDC_TOKEN, value1);

        assertEq(treasury.totalReserves(USDC_TOKEN), amount, "Total reserves is not correct");

        assertEq(beraReserveToken.balanceOf(ALICE), value1, "BRR_TOKEN balance is not correct");

        assertEq(beraReserveToken.totalSupply(), totalSupplyBefore + value1, "BRR_TOKEN total supply is not correct");
    }

    function testFuzzDepositLiquidityToken(uint256 amount) external {
        amount = bound(amount, 0.01e18, IERC20(uniswapV2Pair).balanceOf(BERA_RESERVE_LIQUIDITY_WALLET));

        transferLP(ALICE, amount);

        vm.prank(BERA_RESERVE_ADMIN);
        treasury.setLiquidityDepositor(ALICE, true);

        uint256 totalSupplyBefore = beraReserveToken.totalSupply();

        vm.startPrank(ALICE);
        IERC20(uniswapV2Pair).approve(address(treasury), amount);

        (uint256 value, ) = bRRHoneyDepository.valueOf(uniswapV2Pair, amount);

        treasury.deposit(amount, uniswapV2Pair, value);

        assertEq(treasury.totalReserves(uniswapV2Pair), amount, "Total reserves is not correct");
        assertEq(beraReserveToken.totalSupply(), totalSupplyBefore + value, "BRR_TOKEN total supply is not correct");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function transferUSDC(address user, uint256 amount) public {
        vm.prank(USDC_WHALE);
        IERC20(USDC_TOKEN).transfer(user, amount);
    }

    function transferLP(address user, uint256 amount) public {
        vm.startPrank(BERA_RESERVE_LIQUIDITY_WALLET);
        IERC20(uniswapV2Pair).transfer(user, amount);
        vm.stopPrank();
    }
}
