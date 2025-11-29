// // SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { BeraReserveToken } from "../src/BeraReserveToken.sol";
import { VaultOwned } from "../src/VaultOwned.sol";
import { SafeMath } from "../src/libs/SafeMath.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";

//solhint-disable-next-line func-name-mixedcase
contract BeraReserveERC20Test is BeraReserveBaseTestV2 {
    using SafeMath for uint256;
    using SafeMath for uint48;

    uint256 constant ONE_YEAR_DECAY_PERIOD = 1 * 365 * 24 * 60 * 60 seconds;
    uint256 constant TWO_YEAR_DECAY_PERIOD = 2 * 365 * 24 * 60 * 60 seconds;

    //solhint-disable
    address public DOE = makeAddr("DOE");
    uint256 constant INITIAL_AMOUNT = 10_000e9;

    function setUp() public override {
        super.setUp();

        vm.prank(BERA_RESERVE_ADMIN);
        beraReserveToken.setDecayRatio(2_000);
    }

    function mintAddr(address account_, uint256 amount_) internal {
        vm.prank(address(staking));
        beraReserveToken.transfer(account_, amount_);
    }

    function test_transferTokensToBOB() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        vm.prank(BERA_RESERVE_ADMIN);
        address[] memory addresses = new address[](1);
        addresses[0] = ALICE;
        beraReserveToken.excludeMultipleAccountsFromDecay(addresses, true);

        assertEq(beraReserveToken.balanceOf(ALICE), INITIAL_AMOUNT);

        vm.prank(ALICE);
        beraReserveToken.transfer(BOB, 1000e9);

        assertEq(beraReserveToken.balanceOf(ALICE), 9000e9);
        assertEq(beraReserveToken.balanceOf(BOB), 1000e9);
    }

    function test_MintBeraReserveToken() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        assertEq(beraReserveToken.balanceOf(ALICE), INITIAL_AMOUNT);
    }

    function testExcludeAddressTokenDecay() public {
        address excludedAddress = makeAddr("excludeAddress");

        mintAddr(excludedAddress, INITIAL_AMOUNT);

        vm.prank(BERA_RESERVE_ADMIN);

        address[] memory addresses = new address[](1);
        addresses[0] = excludedAddress;
        beraReserveToken.excludeMultipleAccountsFromDecay(addresses, true);

        assertEq(beraReserveToken.isExcludedAccountsFromDecay(excludedAddress), true);

        vm.prank(excludedAddress);
        beraReserveToken.transfer(BOB, 100e9);

        assertEq(beraReserveToken.balanceOf(excludedAddress), 9.9e12);
        assertEq(beraReserveToken.balanceOf(BOB), 100e9);
    }

    function testExcludeAddressFeesButNotFromDecay() public {
        address JANE = makeAddr("JANE");
        skip(1 hours);
        mintAddr(JANE, INITIAL_AMOUNT);
        vm.prank(BERA_RESERVE_ADMIN);

        address[] memory addresses = new address[](1);
        addresses[0] = JANE;

        beraReserveToken.excludeMultipleAccountsFromFees(addresses, true);

        assertEq(beraReserveToken.isExcludedAccountsFromFees(JANE), true);

        skip(1 hours);

        // skip(1 year); //this will cause senders to trigger a decay.
        console.log("Skipping 1 year");
        skip(ONE_YEAR_DECAY_PERIOD);

        vm.prank(JANE);
        beraReserveToken.transfer(BOB, 100e9);

        uint256 ONE_HOUR_DECAY_PERIOD = 1 hours;

        uint256 amountDebased = _calculateDebasedAmount(INITIAL_AMOUNT, ONE_YEAR_DECAY_PERIOD + ONE_HOUR_DECAY_PERIOD); //amount transferred to BOB
        console.log("amountDebased", amountDebased);

        uint256 amountAfterDecay = INITIAL_AMOUNT - amountDebased;

        assertApproxEqAbs(beraReserveToken.balanceOf(JANE), amountAfterDecay - 100e9, 300, "!JANE balance");
        assertEq(beraReserveToken.balanceOf(BOB), 100e9, "!BOB balance");
    }

    function testDebaseWhenUsersStake() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        //skip(8 hours);
        // vm.prank(address(staking));
        // beraReserveToken.updateLastStakedTime(ALICE);

        skip(11 hours);
        vm.prank(ALICE);
        beraReserveToken.transfer(DOE, 1_000e9);

        uint256 decayAmount = _calculateDebasedAmount(INITIAL_AMOUNT, 11 hours);

        uint256 amountAfterDecay = INITIAL_AMOUNT - decayAmount;

        assertApproxEqAbs(beraReserveToken.balanceOf(ALICE), amountAfterDecay - 1_000e9, 300);
        assertEq(beraReserveToken.balanceOf(DOE), 1_000e9);
    }
    //1826484018
    //1826484018
    //3652968036

    /**
     * 1. Test before 8 hours
     * 2. After 8 hours
     * 3. More than 8 hours
     */
    function testDebaseBefore8Hours() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        skip(2 hours);
        vm.prank(ALICE);
        beraReserveToken.transfer(DOE, 1_000e9);

        //no decay since its every 8 hours elapsed
        assertEq(beraReserveToken.balanceOf(ALICE), INITIAL_AMOUNT - 1_000e9);
        assertEq(beraReserveToken.balanceOf(DOE), 1_000e9);
    }

    function testDebaseRatioSetToZero() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        vm.prank(BERA_RESERVE_ADMIN);
        beraReserveToken.setDecayRatio(0);

        skip(11 hours);
        vm.prank(ALICE);
        beraReserveToken.transfer(DOE, 1_000e9);

        //no decay since its every 8 hours elapsed
        assertEq(beraReserveToken.balanceOf(ALICE), INITIAL_AMOUNT - 1_000e9);
        assertEq(beraReserveToken.balanceOf(DOE), 1_000e9);
    }

    function testDebaseAfter2days() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        // vm.prank(BERA_RESERVE_ADMIN);
        // beraReserveToken.setDecayRatio(0);

        skip(2 days);
        vm.prank(ALICE);
        beraReserveToken.transfer(DOE, 1_000e9);

        uint256 decayAmount = _calculateDebasedAmount(INITIAL_AMOUNT, 2 days);

        console.log("decayAmount", decayAmount);

        uint256 amountAfterDecay = INITIAL_AMOUNT - decayAmount;

        assertApproxEqAbs(beraReserveToken.balanceOf(ALICE), amountAfterDecay - 1_000e9, 300);
        assertEq(beraReserveToken.balanceOf(DOE), 1_000e9);
    }

    function tesDebase2_Quirks() public {
        mintAddr(ALICE, INITIAL_AMOUNT);
    }

    function testDebaseAfterAYear() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        skip(ONE_YEAR_DECAY_PERIOD);
        vm.prank(ALICE);
        beraReserveToken.transfer(DOE, 1_000e9);

        uint256 decayAmountAfterYear = (2_000 * INITIAL_AMOUNT) / 10_000;

        uint256 amountAfterDecay = INITIAL_AMOUNT - decayAmountAfterYear;

        assertApproxEqAbs(beraReserveToken.balanceOf(ALICE), amountAfterDecay - 1_000e9, 300);
        assertEq(beraReserveToken.balanceOf(DOE), 1_000e9);
    }

    function testDebaseShouldFailAfter5Years() public {
        mintAddr(ALICE, INITIAL_AMOUNT);

        skip(10 * ONE_YEAR_DECAY_PERIOD);
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReserveToken.BERA_RESERVE__TRANSFER_AMOUNT_EXCEEDS_BALANCE.selector);
        beraReserveToken.transfer(DOE, 1_000e9);
        vm.stopPrank();
    }

    function _calculateDebasedAmount(uint256 amount_, uint256 decayPeriod) internal view returns (uint256) {
        uint256 elapsedEpoch = decayPeriod / beraReserveToken.decayInterval();
        uint256 decayRatePerEpoch =
            (beraReserveToken.decayRatio() * beraReserveToken.decayInterval() * 1e18) / (10_000 * ONE_YEAR_DECAY_PERIOD);
        uint256 decayAmountPerPeriod = (amount_ * decayRatePerEpoch) / 1e18;
        uint256 decayAmount = decayAmountPerPeriod * elapsedEpoch;

        return decayAmount;
    }
}
