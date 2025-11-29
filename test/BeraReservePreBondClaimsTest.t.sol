// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { console } from "forge-std/Test.sol";
import { BeraReservePreSaleBond } from "src/BeraReservePreSaleBond.sol";
import { BeraReservePreBondClaims } from "src/BeraReservePreBondClaims.sol";
import { BeraReserveToken } from "src/BeraReserveToken.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { InvestorBondInfo } from "src/types/BeraReserveTypes.sol";

contract PreSaleClaimsTest is BeraReserveBaseTestV2 {
    address public PRESALER_WHALE = 0x1D345CF1B2B0A23001F0090C80EDDff4d46B4448;
    uint256 tgeStartTime;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(BERA_RESERVE_ADMIN);
        preSaleClaims.setTgeStartTime();

        tgeStartTime = block.timestamp;
    }

    function testShouldFailIfNoVestingSchedule() public {
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReservePreBondClaims.BERA_RESERVE__NO_VESTING_SCHEDULE_FOUND.selector);
        preSaleClaims.unlockBRR();
        vm.stopPrank();
    }

    function testUnlockBRR() public {
        uint256 brrAmountClaimable = preSaleClaims.unlockedAmount(PRESALER_WHALE);

        InvestorBondInfo memory userInfo = preSaleClaims.investorAllocations(PRESALER_WHALE);
        assertGt(userInfo.totalAmount, 0, "!Total amount");
        assertEq(userInfo.duration, 5 days, "Duration should be 5 days");
        assertEq(userInfo.unlockedAmount, 0, "Unlocked amount should be 0");

        skip(1 days);

        brrAmountClaimable = preSaleClaims.unlockedAmount(PRESALER_WHALE);

        console.log("BRR amount claimable after 1 day:", brrAmountClaimable);
        uint256 timePassed = block.timestamp - tgeStartTime;
        uint256 amountClaimableAfter1Day = (userInfo.totalAmount * timePassed) / (5 days);
        assertEq(
            brrAmountClaimable,
            amountClaimableAfter1Day,
            "BRR amount claimable after 1 day should be equal to amount claimable"
        );

        vm.prank(PRESALER_WHALE);
        preSaleClaims.unlockBRR();

        assertEq(
            brrAmountClaimable,
            beraReserveToken.balanceOf(PRESALER_WHALE),
            "BRR amount claimable after 1 day should be equal to total amount"
        );
    }

    function testUnlockBRRAfter5Days() public {
        skip(5 days);

        vm.prank(PRESALER_WHALE);
        preSaleClaims.unlockBRR();

        InvestorBondInfo memory userInfo = preSaleClaims.investorAllocations(PRESALER_WHALE);
        assertEq(userInfo.unlockedAmount, userInfo.totalAmount, "Unlocked amount should be equal to total amount");

        assertEq(
            beraReserveToken.balanceOf(PRESALER_WHALE),
            userInfo.totalAmount,
            "!User balance should be equal to total amount"
        );
    }
}
