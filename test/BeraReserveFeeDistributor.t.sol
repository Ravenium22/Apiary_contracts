// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console2 } from "lib/forge-std/src/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

contract BeraReserveFeeDistributorTest is BeraReserveBaseTestV2 {
    uint256 amountToOffsetPOL = 49_000e9; //(rewards allocation + airdrop - (1_000e9 - to feeDistributor))

    function fundDistributor() public {
        vm.startPrank(BERA_RESERVE_REWARD_WALLET);
        IERC20(address(beraReserveToken)).transfer(address(feeDistributor), 1_000e9);
        vm.stopPrank();

        console2.log("POL balance: ", beraReserveToken.balanceOf(BERA_RESERVE_POL));
        console2.log("Team balance: ", beraReserveToken.balanceOf(BERA_RESERVE_TEAM));
    }

    function testUpdateContractAddresses() public {
        vm.prank(BERA_RESERVE_ADMIN);
        feeDistributor.updateAddresses(BERA_RESERVE_TEAM, BERA_RESERVE_POL, address(0));

        assertEq(feeDistributor.pol(), BERA_RESERVE_POL, "pol contract should be newTeam");
        assertEq(feeDistributor.treasury(), PROTOCOL_TREASURY, "treasury contract should be unchanged");
        assertEq(feeDistributor.team(), BERA_RESERVE_TEAM, "team contract should be newTeam");

        int256 previousTeamShareDebt = feeDistributor.getShareDebt(BERA_RESERVE_TEAM);
        int256 previousPOLShareDebt = feeDistributor.getShareDebt(BERA_RESERVE_POL);

        assertEq(feeDistributor.getShareDebt(BERA_RESERVE_TEAM), previousTeamShareDebt);
        assertEq(feeDistributor.getShareDebt(BERA_RESERVE_POL), previousPOLShareDebt);
    }

    function testAllocateTreasury() public {
        fundDistributor();
        uint256 balanceOfDistributor = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 accumulatedPerShare = balanceOfDistributor / 10_000;

        uint256 allocatedAmount = (3_400 * accumulatedPerShare);

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 amount = feeDistributor.allocateTreasury();

        vm.prank(BERA_RESERVE_ADMIN);
        feeDistributor.updateAddresses(address(0), address(0), PROTOCOL_TREASURY);

        int256 previousTreasuryShareDebt = feeDistributor.getShareDebt(PROTOCOL_TREASURY);

        uint256 treasuryBRRbalance = IERC20(address(beraReserveToken)).balanceOf(PROTOCOL_TREASURY);
        assertEq(treasuryBRRbalance, amount);
        assertEq(amount, allocatedAmount, "allocateTreasury() should be equal");
        assertEq(feeDistributor.getShareDebt(PROTOCOL_TREASURY), previousTreasuryShareDebt);
    }

    function testAllocatePOL() public {
        fundDistributor();
        uint256 balanceOfDistributor = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 accumulatedPerShare = balanceOfDistributor / 10_000;

        uint256 allocatedAmount = (3_300 * accumulatedPerShare);

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 amount = feeDistributor.allocatePOL();

        vm.prank(BERA_RESERVE_ADMIN);
        feeDistributor.updateAddresses(address(0), makeAddr("newPol"), address(0));

        int256 previousPOLShareDebt = feeDistributor.getShareDebt(BERA_RESERVE_POL);

        uint256 polBRRbalance = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_POL) - amountToOffsetPOL;

        assertEq(polBRRbalance, amount);
        assertEq(amount, allocatedAmount, "allocatePOL() should be equal");
        assertEq(feeDistributor.getShareDebt(makeAddr("newPol")), previousPOLShareDebt);
    }

    function testAllocateTeam() public {
        fundDistributor();
        uint256 balanceOfDistributor = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 accumulatedPerShare = balanceOfDistributor / 10_000;

        uint256 allocatedAmount = (3_300 * accumulatedPerShare);

        uint256 teamBalanceBefore = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 amount = feeDistributor.allocateTeam();

        vm.prank(BERA_RESERVE_ADMIN);
        feeDistributor.updateAddresses(BERA_RESERVE_TEAM, address(0), address(0));

        int256 previousTeamShareDebt = feeDistributor.getShareDebt(BERA_RESERVE_TEAM);

        uint256 teamBRRbalance = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);
        assertEq(teamBRRbalance, teamBalanceBefore + amount, "team brr balance should be equal");
        assertEq(amount, allocatedAmount, "allocateTeam() should be equal");
        assertEq(
            feeDistributor.getShareDebt(BERA_RESERVE_TEAM), previousTeamShareDebt, "team share debt should be equal"
        );
    }

    function testComplexAllocations() public {
        fundDistributor();
        uint256 balanceOfDistributor = IERC20(address(beraReserveToken)).balanceOf(address(feeDistributor));
        uint256 firstAccumulatedPerShare = balanceOfDistributor / 10_000;

        uint256 teamFirstAllocatedAmount = (3_300 * firstAccumulatedPerShare);

        uint256 teamBalanceBefore = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 firstTeamAllocation = feeDistributor.allocateTeam();

        uint256 teamFirstBRRbalance = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);
        assertEq(teamFirstBRRbalance, teamBalanceBefore + firstTeamAllocation, "team brr balance should be equal");
        assertEq(firstTeamAllocation, teamFirstAllocatedAmount, "allocateTeam() should be equal");

        console2.log("first allocation done");
        console2.log("balance of distributor: ", beraReserveToken.balanceOf(address(feeDistributor)));

        vm.warp(block.timestamp + 1 minutes);

        vm.startPrank(BERA_RESERVE_REWARD_WALLET);
        IERC20(address(beraReserveToken)).transfer(address(feeDistributor), 1_000e9);
        vm.stopPrank();

        skip(5 minutes);

        uint256 teamBalanceAfterFirstAllocation = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 secondTeamAllocation = feeDistributor.allocateTeam();

        uint256 teamSecondBRRbalance = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_TEAM);

        assertEq(secondTeamAllocation, 330e9, "allocateTeam() should return 33e6");
        assertEq(
            teamSecondBRRbalance,
            teamBalanceAfterFirstAllocation + secondTeamAllocation,
            "team BRR balance should return 66e9"
        );
        assertEq(firstTeamAllocation + secondTeamAllocation, 660e9, "total allocated to team should return 66e9");

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 firstTreasuryAllocation = feeDistributor.allocateTreasury();

        uint256 treasuryFirstBRRbalance = IERC20(address(beraReserveToken)).balanceOf(PROTOCOL_TREASURY);
        assertEq(treasuryFirstBRRbalance, firstTreasuryAllocation, "treasury BRR balance should return 68e9");
        assertEq(firstTreasuryAllocation, 680e9, "allocateTreasury() should return 68e9");

        vm.prank(BERA_RESERVE_ADMIN);
        uint256 firstPOLAccAllocation = feeDistributor.allocatePOL();
        uint256 polFirstBRRbalance = IERC20(address(beraReserveToken)).balanceOf(BERA_RESERVE_POL) - 48_000e9;
        assertEq(polFirstBRRbalance, firstPOLAccAllocation, "POL brr balance should return 660e9");
        assertEq(firstPOLAccAllocation, 660e9, "allocatePOL() should return 660e9");

        assertEq(firstTeamAllocation + secondTeamAllocation + firstTreasuryAllocation + firstPOLAccAllocation, 2000e9);
    }
}
