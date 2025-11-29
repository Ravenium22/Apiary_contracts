// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";

contract BeraReserveStakingTest is BeraReserveBaseTestV2 {
    /**
     * helper functions
     */
    function mintBRR(address user, uint256 amount) public {
        vm.prank(BERA_RESERVE_REWARD_WALLET);
        beraReserveToken.transfer(user, amount);
    }

    function testCheckLockUpContractWithRebase() public {
        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();
        vm.stopPrank();

        console2.log("LockUp sBRR Before", sBeraReserveToken.balanceOf(address(lockUp)));

        vm.roll(block.number + 14_400);

        mintBRR(makeAddr("ALICE"), 1_000e9);

        vm.startPrank(makeAddr("ALICE"));
        beraReserveToken.approve(address(staking), 1_000e9);
        staking.stake(1_000e9, makeAddr("ALICE"));

        skip(5 days);

        console2.log("LockUp sBRR Before", sBeraReserveToken.balanceOf(address(lockUp)));
    }

    function testFuzzStakeAfterRebaseBlocksPassed(uint256 numOfPurchases, uint256 amount) public {
        numOfPurchases = bound(numOfPurchases, 1, 10);
        amount = bound(amount, 1e9, 100e9);

        vm.roll(block.number + 14_400);

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            mintBRR(user, amount);

            vm.startPrank(user);
            beraReserveToken.approve(address(staking), amount);
            staking.stake(amount, user);
            vm.stopPrank();
        }
    }

    function testFuzzStake(uint256 numOfPurchases, uint256 amount) public {
        numOfPurchases = bound(numOfPurchases, 1, 10);
        amount = bound(amount, 1e9, 100e9);

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            mintBRR(user, amount);

            vm.startPrank(user);
            beraReserveToken.approve(address(staking), amount);
            staking.stake(amount, user);
            vm.stopPrank();
        }

        skip(5 days);

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            mintBRR(user, amount);

            vm.startPrank(user);
            staking.claim(user);
            vm.stopPrank();
        }

        //assert users sbRR balance
        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            assertEq(sBeraReserveToken.balanceOf(user), amount);
        }
    }

    function testFuzzStakeWithRebasingMultipleOps(uint256 numOfPurchases, uint256 amount)
        public
        returns (uint256[] memory user_brr_priorStake, uint256[] memory users_sbrr_prior)
    {
        numOfPurchases = bound(numOfPurchases, 1, 20);
        amount = bound(amount, 1e9, 100e9);

        user_brr_priorStake = new uint256[](numOfPurchases);
        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            mintBRR(user, amount);

            user_brr_priorStake[i] = beraReserveToken.balanceOf(user);

            vm.startPrank(user);
            beraReserveToken.approve(address(staking), amount);
            staking.stake(amount, user);
            vm.stopPrank();
        }

        vm.roll(block.number + 14_401);

        uint256 stakingContractBalanceBeforeFirstRebasing = beraReserveToken.balanceOf(address(staking));

        console2.log("First Rebasing");

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            mintBRR(user, amount);

            vm.startPrank(user);
            beraReserveToken.approve(address(staking), amount);
            staking.stake(amount, user);
            vm.stopPrank();
        }

        skip(5 days);

        //claim sbRR
        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            vm.startPrank(user);
            staking.claim(user);
            vm.stopPrank();
        }

        users_sbrr_prior = new uint256[](numOfPurchases);

        //check user sbRR balance
        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users_sbrr_prior[i] = sBeraReserveToken.balanceOf(user);
        }

        uint256 stakingContractBalanceAfterFirstRebasing = beraReserveToken.balanceOf(address(staking));

        assertGt(stakingContractBalanceAfterFirstRebasing, stakingContractBalanceBeforeFirstRebasing);

        vm.roll(block.number + 14_400);

        console2.log("Second Rebasing");

        mintBRR(ALICE, amount);

        vm.startPrank(ALICE);
        beraReserveToken.approve(address(staking), amount);
        staking.stake(amount, ALICE);
        vm.stopPrank();

        uint256[] memory users_sbrr_after = new uint256[](numOfPurchases);

        //check user sbRR balance
        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users_sbrr_after[i] = sBeraReserveToken.balanceOf(user);
            assertGt(sBeraReserveToken.balanceOf(user), users_sbrr_prior[i], "User sbrr balance should increase");
        }

        return (user_brr_priorStake, users_sbrr_after);
    }

    function testFuzz_UnstakeAllAfterMultipleRebases_BalanceIncreased(uint256 numOfPurchases, uint256 amount) public {
        numOfPurchases = bound(numOfPurchases, 1, 20);
        amount = bound(amount, 1e9, 100e9);

        (uint256[] memory users_brr_priorStake, uint256[] memory users_sbrr_prior) =
            testFuzzStakeWithRebasingMultipleOps(numOfPurchases, amount);

        //unstake
        uint256[] memory users_brr_after = new uint256[](numOfPurchases);

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            uint256 sbrrBalance = users_sbrr_prior[i];

            vm.startPrank(user);
            sBeraReserveToken.approve(address(staking), sbrrBalance);
            staking.unstake(sbrrBalance, false);
            vm.stopPrank();

            users_brr_after[i] = beraReserveToken.balanceOf(user);

            console2.log("user brr after", users_brr_after[i]);
            assertGt(beraReserveToken.balanceOf(user), users_brr_priorStake[i], "User BRR should increase after rebase");
        }

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            assertEq(sBeraReserveToken.balanceOf(user), 0, "User sBRR should be 0 before rebase");
        }

        //another rebase users should receive no extra rewards, since they unstaked full
        vm.roll(block.number + 14_400);

        mintBRR(makeAddr("ALICE"), 1_000e9);

        vm.startPrank(makeAddr("ALICE"));
        beraReserveToken.approve(address(staking), 1_000e9);
        staking.stake(1_000e9, makeAddr("ALICE"));

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            assertApproxEqAbs(sBeraReserveToken.balanceOf(user), 0, 1, "User sBRR should be 0 before rebase");
        }
    }

    function testFuzz_UnstakePartialAfterMultipleRebases_BRRBalanceIncreased(uint256 numOfPurchases, uint256 amount)
        public
    {
        numOfPurchases = bound(numOfPurchases, 1, 20);

        amount = bound(amount, 1e9, 100e9);

        (uint256[] memory users_brr_priorStake, uint256[] memory users_sbrr_prior) =
            testFuzzStakeWithRebasingMultipleOps(numOfPurchases, amount);

        //unstake
        uint256[] memory users_brr_after = new uint256[](numOfPurchases);

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            uint256 sbrrBalance = users_sbrr_prior[i];

            vm.startPrank(user);
            sBeraReserveToken.approve(address(staking), sbrrBalance);
            staking.unstake(sbrrBalance / 2, false);
            vm.stopPrank();

            users_brr_after[i] = beraReserveToken.balanceOf(user);

            console2.log("user brr after", users_brr_after[i]);
            assertGt(beraReserveToken.balanceOf(user), users_brr_priorStake[i]);
        }

        //another rebase users should receive additional extra rewards, since they unstaked partially
        vm.roll(block.number + 14_400);

        mintBRR(makeAddr("ALICE"), 1_000e9);

        vm.startPrank(makeAddr("ALICE"));
        beraReserveToken.approve(address(staking), 1_000e9);
        staking.stake(1_000e9, makeAddr("ALICE"));

        for (uint256 i = 0; i < numOfPurchases; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));

            assertGt(sBeraReserveToken.balanceOf(user), 0, "User sBRR should still > 0");
        }
    }
}
