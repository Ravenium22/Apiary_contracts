// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console } from "lib/forge-std/src/Test.sol";
import { BeraReserveBaseTestV2 } from "./setup/BeraReserveBaseV2.t.sol";
import { BeraReserveLockUp } from "src/BeraReserveLockUp.sol";
import { VestingSchedule, MemberType } from "src/types/BeraReserveTypes.sol";

contract BeraReserveLockUpTest is BeraReserveBaseTestV2 {
    address public DAVE = 0x1D345CF1B2B0A23001F0090C80EDDff4d46B4448;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.excludeAccountFromFeesAndDecay(ALICE, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BOB, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(CHARLIE, true);

        vm.stopPrank();

        assertEq(beraReserveToken.totalSupply(), 160_000e9);

        assertEq(beraReserveToken.balanceOf(address(lockUp)), 90_000e9 - 78_000e9);
    }

    function testBeraStakingContractSetCorrectly() public view {
        assertEq(address(lockUp.beraStaking()), address(staking));
    }

    function testBrrTokenContractSetCorrectly() public view {
        assertEq(address(lockUp.brrToken()), address(beraReserveToken));
    }

    function testAddTeamMembers() public {
        vm.prank(BERA_RESERVE_ADMIN);

        lockUp.addTeamMember(ALICE, 10_000e9);
    }

    function testAddSeedRoundMembersWithTGEUnlock() public {
        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addSeedRoundMember(ALICE, 10_000e9);

        VestingSchedule memory aliceSchedule = lockUp.getSeedRoundSchedules(ALICE);
        assertEq(aliceSchedule.amountUnlockedAtTGE, 3_000e9, "Alice should have 3_000e9 BRR unlocked at TGE");

        //alice unlock at tge
        vm.prank(ALICE);
        lockUp.initiateTGEUnlock();

        VestingSchedule memory aliceScheduleAfter = lockUp.getSeedRoundSchedules(ALICE);
        assertEq(aliceScheduleAfter.amountUnlockedAtTGE, 0, "Alice should have 0 BRR unlocked at TGE");
    }

    function testAddSeedRoundMembersShouldUnlockZeroIfNotASeedMember() public {
        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addSeedRoundMember(ALICE, 10_000e9);

        VestingSchedule memory aliceSchedule = lockUp.getSeedRoundSchedules(ALICE);
        assertEq(aliceSchedule.amountUnlockedAtTGE, 3_000e9, "Alice should have 3_000e9 BRR unlocked at TGE");

        //alice unlock at tge
        vm.prank(CHARLIE);
        lockUp.initiateTGEUnlock();
    }

    function testAddMultipleSeedRoundMembers() public {
        address[] memory members = new address[](2);

        members[0] = ALICE;
        members[1] = CHARLIE;

        uint128[] memory totalAmounts = new uint128[](2);
        totalAmounts[0] = 30_000e9;
        totalAmounts[1] = 10_000e9;

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addMultipleSeedRoundMembers(members, totalAmounts);
    }

    function testAddMultipleMarketMembersShouldRevertIfArrayMismatch() public {
        address[] memory members = new address[](2);

        members[0] = ALICE;
        members[1] = CHARLIE;

        uint128[] memory totalAmounts = new uint128[](1);
        totalAmounts[0] = 30_000e9;

        vm.startPrank(BERA_RESERVE_ADMIN);
        vm.expectRevert(BeraReserveLockUp.BERA_RESERVE_LENGTH_MISMATCH.selector);
        lockUp.addMultipleMarketingMembers(members, totalAmounts);
    }

    function testAddMultipleTeamMembers() public {
        address[] memory members = new address[](2);
        members[0] = ALICE;
        members[1] = CHARLIE;

        uint128[] memory totalAmounts = new uint128[](2);
        totalAmounts[0] = 3_000e9;
        totalAmounts[1] = 1_000e9;

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addMultipleMarketingMembers(members, totalAmounts);
    }

    function testUnlockTeamBrr() public {
        addTeamMember(BOB, 10_000e9);

        VestingSchedule memory bobSchedule = lockUp.getTeamSchedules(BOB);

        assertEq(bobSchedule.duration, lockUp.TEAM_VESTING_DURATION());
        assertEq(bobSchedule.cliff, block.timestamp + lockUp.TEAM_VESTING_CLIFF());
        assertEq(bobSchedule.totalAmount, 10_000e9);

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);
        /**
         * user can start vesting after 3 months
         */
        skip(91 * 24 * 60 * 60 seconds);

        uint256 bobSbrrBalancePrior = sBeraReserveToken.balanceOf(BOB);

        vm.startPrank(BOB);
        lockUp.unlockSbrr(MemberType.TEAM);

        uint256 bobSbrrBalanceAfter = sBeraReserveToken.balanceOf(BOB);

        uint256 timePassed = (block.timestamp - bobSchedule.cliff);

        uint256 bobVestedAmount = (timePassed * bobSchedule.totalAmount) / bobSchedule.duration;

        assertEq(bobSbrrBalanceAfter, bobSbrrBalancePrior + bobVestedAmount);
    }

    function testUnlockSeedRoundBrr() public {
        addSeedRoundMember(CHARLIE, 10_000e9);

        uint256 seedDuration = lockUp.SEED_ROUND_VESTING_DURATION();

        VestingSchedule memory charlieSchedule = lockUp.getSeedRoundSchedules(CHARLIE);

        assertEq(charlieSchedule.duration, seedDuration);
        assertEq(charlieSchedule.cliff, 0);
        /**
         * 30% of 10_000e9 is immediately accessible
         * 10_000e9 - 3_000e9 = 7_000e9 is vested.
         */
        assertEq(charlieSchedule.totalAmount, 7_000e9);

        skip(5 minutes);

        vm.prank(CHARLIE);
        lockUp.initiateTGEUnlock();

        uint256 charlieBrrBalancePrior = beraReserveToken.balanceOf(CHARLIE);

        assertEq(charlieBrrBalancePrior, 3_000e9);

        uint256 charlieSbrrBalancePrior = sBeraReserveToken.balanceOf(CHARLIE);

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);

        skip(1 days);

        vm.startPrank(CHARLIE);
        lockUp.unlockSbrr(MemberType.SEED_ROUND);

        uint256 timePassed = (block.timestamp - charlieSchedule.start);

        uint256 charlieVestedAmount = (timePassed * charlieSchedule.totalAmount) / charlieSchedule.duration;

        uint256 charlieSbrrBalanceAfter = sBeraReserveToken.balanceOf(CHARLIE);

        assertEq(charlieSbrrBalanceAfter, charlieSbrrBalancePrior + charlieVestedAmount);
    }

    function testReVestingMarketingTeamMultipleOps() public {
        addMarketMember(CHARLIE, 5_000e9);

        VestingSchedule memory charlieFirstSchedule = lockUp.getMarketSchedules(CHARLIE);
        assertEq(charlieFirstSchedule.duration, lockUp.MARKETING_VESTING_DURATION());
        assertEq(charlieFirstSchedule.cliff, 0);
        assertEq(charlieFirstSchedule.start, block.timestamp);
        assertEq(charlieFirstSchedule.amountClaimed, 0);
        assertEq(charlieFirstSchedule.totalAmount, 5_000e9);

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);

        skip(366 * 24 * 60 * 60 seconds); //over a year

        //claim everything
        vm.startPrank(CHARLIE);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        VestingSchedule memory charlieAfterFirstUnlockSchedule = lockUp.getMarketSchedules(CHARLIE);
        assertEq(charlieAfterFirstUnlockSchedule.amountClaimed, 5_000e9);

        assertEq(sBeraReserveToken.balanceOf(CHARLIE), 5_000e9);

        uint256 charliePriorSbrrBalance = sBeraReserveToken.balanceOf(CHARLIE);
        //new vest
        addMarketMember(CHARLIE, 5_000e9);

        VestingSchedule memory charlieSecondSchedule = lockUp.getMarketSchedules(CHARLIE);
        assertEq(charlieSecondSchedule.duration, lockUp.MARKETING_VESTING_DURATION());
        assertEq(charlieSecondSchedule.cliff, 0);
        assertEq(charlieSecondSchedule.start, block.timestamp);
        assertEq(charlieSecondSchedule.amountClaimed, 0);
        assertEq(charlieSecondSchedule.totalAmount, 5_000e9);

        skip(366 * 24 * 60 * 60 seconds); //over year

        vm.startPrank(CHARLIE);
        sBeraReserveToken.approve(address(staking), 5_000e9);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        VestingSchedule memory charlieAfterSecondUnlockSchedule = lockUp.getMarketSchedules(CHARLIE);
        assertEq(charlieAfterSecondUnlockSchedule.amountClaimed, 5_000e9);

        assertEq(sBeraReserveToken.balanceOf(CHARLIE), charliePriorSbrrBalance + 5_000e9);
    }

    function testUnlockMarketingBrr() public {
        addMarketMember(ALICE, 10_000e9);

        VestingSchedule memory aliceSchedule = lockUp.getMarketSchedules(ALICE);
        assertEq(aliceSchedule.cliff, 0);
        assertEq(aliceSchedule.totalAmount, 10_000e9);
        assertEq(aliceSchedule.duration, lockUp.MARKETING_VESTING_DURATION());

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);

        skip(1 days);

        uint256 aliceSbrrBalancePrior = sBeraReserveToken.balanceOf(ALICE);

        vm.startPrank(ALICE);
        lockUp.unlockSbrr(MemberType.MARKETING);

        uint256 aliceSbrrBalanceAfter = sBeraReserveToken.balanceOf(ALICE);

        uint256 timePassed = (block.timestamp - aliceSchedule.start);

        uint256 aliceVestedAmount = (timePassed * aliceSchedule.totalAmount) / aliceSchedule.duration;

        assertEq(aliceSbrrBalanceAfter, aliceSbrrBalancePrior + aliceVestedAmount);
    }

    function testCreateSchedulesForMembersMultipleOps() public {
        skip(5 minutes);

        uint256 startTime = block.timestamp;

        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.addMarketingMember(ALICE, 1_000e9);
        lockUp.addMarketingMember(BOB, 1_000e9);
        vm.stopPrank();

        console.log("Alice sBRR balance before unlock", sBeraReserveToken.balanceOf(ALICE));
        console.log("Bob sBRR balance before unlock", sBeraReserveToken.balanceOf(BOB));

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);

        skip(1 days);

        uint256 aliceDurationPassed = block.timestamp - startTime;

        uint256 aliceTotalAmountUnlocked = (1_000e9 * aliceDurationPassed) / lockUp.MARKETING_VESTING_DURATION();

        assertEq(lockUp.unlockedAmount(ALICE, MemberType.MARKETING), aliceTotalAmountUnlocked);

        vm.startPrank(ALICE);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        assertEq(aliceTotalAmountUnlocked, sBeraReserveToken.balanceOf(ALICE));

        skip(5 days);

        uint256 bobDurationPassed = block.timestamp - startTime;

        uint256 bobTotalAmountUnlocked = (1_000e9 * bobDurationPassed) / lockUp.MARKETING_VESTING_DURATION();

        assertEq(lockUp.unlockedAmount(BOB, MemberType.MARKETING), bobTotalAmountUnlocked);

        vm.startPrank(BOB);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        assertEq(bobTotalAmountUnlocked, sBeraReserveToken.balanceOf(BOB));

        skip(365 * 24 * 60 * 60 seconds);

        //alice unlocks 1 year later
        vm.startPrank(ALICE);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        //bob unlocks 1 year later
        vm.startPrank(BOB);
        lockUp.unlockSbrr(MemberType.MARKETING);
        vm.stopPrank();

        assertEq(1_000e9, sBeraReserveToken.balanceOf(ALICE));
        assertEq(1_000e9, sBeraReserveToken.balanceOf(BOB));
    }

    function testCreateScheduleForSeedRoundInvestorsMultipleOps() public {
        skip(5 minutes);

        uint128 aliceAmount = 16550273910227;
        uint128 bobAmount = 15122010213579;

        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.addSeedRoundMember(ALICE, aliceAmount);
        lockUp.addSeedRoundMember(BOB, bobAmount);
        vm.stopPrank();

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReserveToken.excludeAccountFromFeesAndDecay(ALICE, true);
        beraReserveToken.excludeAccountFromFeesAndDecay(BOB, true);
        vm.stopPrank();

        skip(5 minutes);

        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.claimSbrr();

        assertEq(sBeraReserveToken.balanceOf(address(lockUp)), 78_000e9);

        skip(1 days);

        console.log("Alice sBRR Balance Before First Unlock", sBeraReserveToken.balanceOf(ALICE));
        console.log("Alice First Unlocks After 1 days");

        //alice unlocks
        vm.startPrank(ALICE);
        lockUp.unlockSbrr(MemberType.SEED_ROUND);
        vm.stopPrank();
        console.log("Alice sBRR Balance After 1 days", sBeraReserveToken.balanceOf(ALICE));

        skip(10 days);

        console.log();
        console.log("Bob sBRR Balance Before First Unlock", sBeraReserveToken.balanceOf(BOB));
        console.log("BoB First Unlocks After 10 days");

        vm.startPrank(BOB);
        lockUp.unlockSbrr(MemberType.SEED_ROUND);
        vm.stopPrank();

        console.log("BoB sBRR Balance After 10 days", sBeraReserveToken.balanceOf(BOB));

        skip(180 * 24 * 60 * 60 seconds);

        console.log();

        console.log("Alice + Bob fully unlocks after 6 months");

        vm.startPrank(ALICE);
        lockUp.unlockSbrr(MemberType.SEED_ROUND);
        vm.stopPrank();

        console.log("Alice sBRR Balance After 6 months days", sBeraReserveToken.balanceOf(ALICE));

        //alice unlock BRR at TGE
        vm.prank(ALICE);
        lockUp.initiateTGEUnlock();

        /**
         * seed round member gets 30% of total amount immediately
         */
        assertEq(
            sBeraReserveToken.balanceOf(ALICE),
            aliceAmount - beraReserveToken.balanceOf(ALICE),
            "alice sBRR should be equal"
        );

        vm.startPrank(BOB);
        lockUp.unlockSbrr(MemberType.SEED_ROUND);
        vm.stopPrank();

        console.log("BoB sBRR Balance After 6 months days", sBeraReserveToken.balanceOf(BOB));

        //bob unlock BRR at TGE
        vm.prank(BOB);
        lockUp.initiateTGEUnlock();

        assertEq(
            sBeraReserveToken.balanceOf(BOB), bobAmount - beraReserveToken.balanceOf(BOB), "bob sBRR should be equal"
        );
    }

    function testIfAmountAllocatedToMarketingMemberIsZero() public {
        skip(5 minutes);
        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.addMarketingMember(ALICE, 5_000e9);
        lockUp.addMarketingMember(BOB, 5_000e9);

        //should fail since the allocated - totalMarketingBRR = 0
        //ie 50_000e9 - 50_000e9 = 0
        vm.expectRevert(BeraReserveLockUp.BRR_INVALID_AMOUNT.selector);
        lockUp.addMarketingMember(DAVE, 1_000e9);
        vm.stopPrank();
    }

    function testIfAmountAllocatedToTeamMemberIsZero() public {
        skip(5 minutes);
        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.addTeamMember(ALICE, 10_000e9);
        lockUp.addTeamMember(BOB, 30_000e9);

        //should fail since the allocated - totalTeamBRR = 0
        //ie 200_000e9 - 200_000e9 = 0
        vm.expectRevert(BeraReserveLockUp.BRR_INVALID_AMOUNT.selector);
        lockUp.addTeamMember(DAVE, 1_000e9);
        vm.stopPrank();
    }

    function testIfAmountAllocatedToSeedRoundMemberIsZero() public {
        skip(5 minutes);
        vm.startPrank(BERA_RESERVE_ADMIN);
        lockUp.addSeedRoundMember(ALICE, 10_000e9);
        lockUp.addSeedRoundMember(BOB, 30_000e9);

        //should fail since the allocated - totalSeedRoundBRR = 0
        //ie 200_000e9 - 200_000e9 = 0
        vm.expectRevert(BeraReserveLockUp.BRR_INVALID_AMOUNT.selector);
        lockUp.addSeedRoundMember(DAVE, 1_000e9);
        vm.stopPrank();
    }

    function addMarketMember(address user, uint128 totalAmount) public {
        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addMarketingMember(user, totalAmount);
    }

    function addSeedRoundMember(address user, uint128 totalAmount) public {
        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addSeedRoundMember(user, totalAmount);
    }

    function addTeamMember(address user, uint128 totalAmount) public {
        vm.prank(BERA_RESERVE_ADMIN);
        lockUp.addTeamMember(user, totalAmount);
    }

    /**
     * HELPER FUNCTIONS
     */
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
}
