// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";

contract TestTransferOwnership is BeraReserveBaseTestV2 {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function testBeraReserveTokenOwnershipTransfer() public {
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.grantRole(DEFAULT_ADMIN_ROLE, ALICE);
        vm.stopPrank();

        vm.prank(ALICE);
        beraReserveToken.setBuyFee(2_000);
    }

    function testDistributorOwnershipTransfer() public {
        vm.startPrank(BERA_RESERVE_ADMIN);
        distributorV2.pushPolicy(ALICE);
        vm.stopPrank();

        vm.prank(ALICE);
        distributorV2.pullPolicy();

        vm.prank(ALICE);
        distributorV2.addRecipient(address(lockUp), 23);
    }

    function testStakingOwnershipTransfer() public {
        vm.startPrank(BERA_RESERVE_ADMIN);
        staking.pushManagement(ALICE);
        vm.stopPrank();

        vm.prank(ALICE);
        staking.pullManagement();

        vm.prank(ALICE);
        staking.pause();
    }
}
