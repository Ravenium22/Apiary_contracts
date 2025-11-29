// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { BeraReservePreSaleBond } from "src/BeraReservePreSaleBond.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
import { BeraReserveToken } from "src/BeraReserveToken.sol";
import { USDC } from "src/mocks/USDC.sol";
import { Test } from "forge-std/Test.sol";
import { InvestorBondInfo } from "src/types/BeraReserveTypes.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

contract BeraReservePreSaleBondTest is Test {
    using Math for uint256;

    BeraReservePreSaleBond public beraReservePreSaleBond;
    BeraReserveToken public beraReserveToken;
    USDC public usdc;
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022);

    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    address public BERA_NATIVE_TOKEN = 0x6969696969696969696969696969696969696969;
    address public USDC_BERA = 0x549943e04f40284185054145c6E4e9568C1D3241;
    /**
     * 0x0959a16d89a039BB5e63b3904D4EBd5D946DED01
     * 0x55422cabb16e16cB84397Ed606076607b00aA2e5
     * 0xd68D714154B033934dF470DA1D8ff89Ac4987eB8
     */
    address public ALICE = 0x0959a16d89a039BB5e63b3904D4EBd5D946DED01;
    address public BOB = 0x55422cabb16e16cB84397Ed606076607b00aA2e5;
    address public CHARLIE = 0xd68D714154B033934dF470DA1D8ff89Ac4987eB8;
    address public DAVE = makeAddr("DAVE");

    uint256 internal constant PRE_BONDS_TOTAL_BRR_AMOUNT = 50_000e9;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");

    function setUp() public {
        uint256 berachainFork = vm.createFork(vm.envString("BERACHAIN_RPC_URL"));

        vm.selectFork(berachainFork);

        vm.startPrank(BERA_RESERVE_ADMIN);

        beraReserveToken = new BeraReserveToken(BERA_RESERVE_ADMIN, BERA_RESERVE_ADMIN, BERA_RESERVE_ADMIN);

        usdc = new USDC(80094);

        /**
         * constructor(address _honey, address _protocolMultisig, address _admin, bytes32 _merkleRoot) Ownable(_admin) {
         */
        bytes32 root = 0x74be2246401d7dd0daa27b8ebf5ca50984dee08fa9aa215d800ff00076486976;
        beraReservePreSaleBond = new BeraReservePreSaleBond(address(usdc), BERA_RESERVE_ADMIN, BERA_RESERVE_ADMIN, root);

        beraReserveToken.grantRole(MINTER_ROLE, address(beraReservePreSaleBond));
        beraReserveToken.grantRole(BURNER_ROLE, address(beraReservePreSaleBond));

        beraReserveToken.excludeAccountFromFeesAndDecay(address(beraReservePreSaleBond), true);

        beraReserveToken.setAllocationLimit(address(beraReservePreSaleBond), PRE_BONDS_TOTAL_BRR_AMOUNT);

        usdc.mint(ALICE, 10_000e18);
        usdc.mint(BOB, 10_000e18);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              NORMAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testPurchaseShouldFailIfPreBondStartIsNotLIVE() public {
        bytes32[] memory merkleProof = new bytes32[](2);
        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 2_000e18);

        vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__PRE_BOND_SALE_NOT_LIVE.selector);
        beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);
    }

    function testPurchaseShouldFailIFInvalidMerkleProof() public {
        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        bytes32[] memory merkleProof = new bytes32[](2);
        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 2_000e18);

        vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__INVALID_PROOF.selector);
        beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);
    }

    function testUnlockShouldFailIfUserHasNoInvestments() public {
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__NO_VESTING_SCHEDULE_FOUND.selector);
        beraReservePreSaleBond.unlockBRR();
    }

    // function testUnlockShouldFailIfNoUnlocksYet() public {
    //     bytes32[] memory merkleProof = new bytes32[](2);
    //     merkleProof[0] = 0x899ede71e295aa9565c91428298a9f9dc32ec0a7c4e0b41bf9c228c0c163d449;
    //     merkleProof[1] = 0x121eb9ce49e5477845fe32908c37f978910ef8da4d715dfc908aed204efb7b28;

    //     vm.prank(BERA_RESERVE_ADMIN);
    //     beraReservePreSaleBond.startPreSaleBond();

    //     skip(5 minutes);
    //     vm.startPrank(ALICE);
    //     usdc.approve(address(beraReservePreSaleBond), 2_000e18);

    //     beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);

    //     vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__NO_BRR_TO_UNLOCK.selector);
    //     beraReservePreSaleBond.unlockBRR();
    // }

    // function testUnlockShouldFailIfTgeNotStarted() public {
    //     bytes32[] memory merkleProof = new bytes32[](2);
    //     merkleProof[0] = 0x899ede71e295aa9565c91428298a9f9dc32ec0a7c4e0b41bf9c228c0c163d449;
    //     merkleProof[1] = 0x121eb9ce49e5477845fe32908c37f978910ef8da4d715dfc908aed204efb7b28;

    //     vm.prank(BERA_RESERVE_ADMIN);
    //     beraReservePreSaleBond.startPreSaleBond();

    //     vm.startPrank(ALICE);
    //     usdc.approve(address(beraReservePreSaleBond), 2_000e18);

    //     beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);

    //     skip(10 days);
    //     vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__NO_BRR_TO_UNLOCK.selector);
    //     beraReservePreSaleBond.unlockBRR();
    // }

    function testWhitelistDisabled() public {
        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.setWhitelistEnabled(false);
        beraReservePreSaleBond.startPreSaleBond();
        vm.stopPrank();

        bytes32[] memory merkleProof = new bytes32[](2);

        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 2_000e18);

        beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);
    }

    function testPurchaseBRR__MultipleOps() public {
        bytes32[] memory merkleProof = new bytes32[](2);
        /**
         * Proof: ["0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111","0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e"]
         */
        merkleProof[0] = 0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111;
        merkleProof[1] = 0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e;
        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        skip(5 minutes);
        uint256 firstPurchaseTime = uint32(block.timestamp);

        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 1_000e18);

        beraReservePreSaleBond.purchaseBRR(200e18, merkleProof);
        vm.stopPrank();
        InvestorBondInfo memory userInfoPrimary = beraReservePreSaleBond.investorAllocations(ALICE);

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.setTgeStartTime();

        beraReservePreSaleBond.setBRRToken(address(beraReserveToken));

        beraReservePreSaleBond.mintBRR();
        vm.stopPrank();

        skip(3 days);
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();
        console.log("ALICE BRR balance first unlock: %d", beraReserveToken.balanceOf(ALICE));
        /**
         * Reason: total amount of brr = 200e9
         * 200e9 / 0.2 = 1000e9 in total
         * per day = 1000e9 / 5 = 200e9
         * for 3 days = 200e9 * 3 = 600e9
         */
        uint256 brrAmountFirstUnlock =
            userInfoPrimary.totalAmount * (block.timestamp - firstPurchaseTime) / userInfoPrimary.duration;
        assertEq(
            beraReserveToken.balanceOf(ALICE), brrAmountFirstUnlock, "ALICE BRR balance first unlock should be 600e9"
        );

        skip(5 minutes);
        uint256 amountUnlockedBeforeSecondUnlock = beraReservePreSaleBond.unlockedAmount(ALICE);
        // uint256 secondPurchaseTime = uint32(block.timestamp);

        vm.prank(ALICE);
        beraReservePreSaleBond.purchaseBRR(200e18, merkleProof);

        InvestorBondInfo memory userInfo = beraReservePreSaleBond.investorAllocations(ALICE);
        assertEq(userInfo.totalAmount, 2_000e9, "Total amount should be 2_000e9");
        assertEq(
            userInfo.unlockedAmount,
            600e9 + amountUnlockedBeforeSecondUnlock,
            "Unlocked amount should be greater than 600e9"
        );

        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.mintBRR();

        skip(2 days);
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        assertEq(
            beraReserveToken.balanceOf(ALICE), userInfo.totalAmount, "ALICE BRR balance second unlock should be 800e9"
        );
    }

    function testPurchaseBRR__MoreThanMaxWalletAllocation() public {
        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        bytes32[] memory merkleProof = new bytes32[](2);
        merkleProof[0] = 0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111;
        merkleProof[1] = 0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e;

        skip(5 minutes);
        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 10_000e18);
        beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);
        vm.stopPrank();

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.setTgeStartTime();

        beraReservePreSaleBond.setBRRToken(address(beraReserveToken));

        beraReservePreSaleBond.mintBRR();
        vm.stopPrank();

        skip(1 days);
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        skip(5 minutes);
        vm.startPrank(ALICE);
        vm.expectRevert(BeraReservePreSaleBond.BERA_RESERVE__PRE_BOND_SALE__MAX_BOND.selector);
        beraReservePreSaleBond.purchaseBRR(1_500e18, merkleProof);
    }

    function testPurchaseBRR__BurnAllUnsoldBRR() public {
        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        bytes32[] memory merkleProof = new bytes32[](2);
        merkleProof[0] = 0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111;
        merkleProof[1] = 0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e;

        skip(5 minutes);
        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), 1_000e18);
        beraReservePreSaleBond.purchaseBRR(500e18, merkleProof);
        vm.stopPrank();

        InvestorBondInfo memory userInfo = beraReservePreSaleBond.investorAllocations(ALICE);
        assertEq(userInfo.totalAmount, 2_500e9, "Total amount should be 2_500e9");
        assertEq(userInfo.duration, 5 days, "Duration should be 5 days");
        assertEq(userInfo.unlockedAmount, 0, "Unlocked amount should be 0");

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.setTgeStartTime();
        uint48 tgeStartTime = beraReservePreSaleBond.tgeStartTime();

        beraReservePreSaleBond.setBRRToken(address(beraReserveToken));

        beraReservePreSaleBond.mintBRR();
        vm.stopPrank();

        skip(1 days);
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        userInfo = beraReservePreSaleBond.investorAllocations(ALICE);
        assertEq(userInfo.unlockedAmount, 500e9, "Unlocked amount should be 500e9");

        uint256 aliceBRRafterFirstUnlockAmount =
            (userInfo.totalAmount * (block.timestamp - tgeStartTime)) / userInfo.duration;
        assertEq(
            beraReserveToken.balanceOf(ALICE),
            aliceBRRafterFirstUnlockAmount,
            "ALICE BRR after first unlock (1 day) should be 500e9"
        );

        skip(5 minutes);
        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.endPreSaleBond();

        assertEq(
            beraReserveToken.balanceOf(address(beraReservePreSaleBond)) - 2_000e9,
            0,
            "BRR tokens available excluding ALICE's BRR should be burned"
        );

        skip(1 days);
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        uint256 aliceBRRafterSecondUnlockAmount =
            (userInfo.totalAmount * (block.timestamp - tgeStartTime)) / userInfo.duration;
        assertEq(
            beraReserveToken.balanceOf(ALICE),
            aliceBRRafterSecondUnlockAmount,
            "ALICE BRR after second unlock (1 day + 5 minutes) "
        );

        userInfo = beraReservePreSaleBond.investorAllocations(ALICE);
        assertEq(
            userInfo.unlockedAmount,
            aliceBRRafterFirstUnlockAmount + (aliceBRRafterSecondUnlockAmount - aliceBRRafterFirstUnlockAmount),
            "Unlocked amount be equal to first unlock + (second unlock - first unlock)"
        );
    }

    /*//////////////////////////////////////////////////////////////
                               FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz__BRRPurchaseAllocationAndUnlocking(uint256 alicePurchaseAmount, uint256 bobPurchaseAmount)
        public
    {
        alicePurchaseAmount = bound(alicePurchaseAmount, 1e18, usdc.balanceOf(ALICE));
        bobPurchaseAmount = bound(bobPurchaseAmount, 1e18, usdc.balanceOf(BOB));

        vm.assume(alicePurchaseAmount != bobPurchaseAmount);

        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        bytes32[] memory aliceMerkleProof = new bytes32[](2);
        aliceMerkleProof[0] = 0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111;
        aliceMerkleProof[1] = 0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e;

        bytes32[] memory bobMerkleProof = new bytes32[](3);

        bobMerkleProof[0] = 0x865691bb9d0da996e195701fa966f9e49fd926d43741e9ee2e315c2e48634975;
        bobMerkleProof[1] = 0xf5e216537885c6784fa9337c71858ba1ad15eeee33bf5449f3e09e462fe1c660;
        bobMerkleProof[2] = 0xaf43dfbc8da21120f0a049b6c60858e1cb75b6f6852f8e70688037fe58bb047b;

        // uint256 aliceUsdcBalancePrior = usdc.balanceOf(ALICE);
        // uint256 bobUsdcBalancePrior = usdc.balanceOf(BOB);

        skip(1 days);
        vm.startPrank(ALICE);

        uint256 aliceRefund;
        uint256 bobRefund;

        if (alicePurchaseAmount > 500e18) aliceRefund = alicePurchaseAmount - 500e18;

        if (bobPurchaseAmount > 500e18) bobRefund = bobPurchaseAmount - 500e18;

        usdc.approve(address(beraReservePreSaleBond), alicePurchaseAmount);
        beraReservePreSaleBond.purchaseBRR(alicePurchaseAmount, aliceMerkleProof);

        vm.stopPrank();

        InvestorBondInfo memory aliceInfo = beraReservePreSaleBond.investorAllocations(ALICE);

        skip(1 days);
        vm.startPrank(BOB);

        usdc.approve(address(beraReservePreSaleBond), bobPurchaseAmount);
        beraReservePreSaleBond.purchaseBRR(bobPurchaseAmount, bobMerkleProof);

        InvestorBondInfo memory bobInfo = beraReservePreSaleBond.investorAllocations(BOB);

        vm.stopPrank();

        vm.startPrank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.setTgeStartTime();
        uint48 tgeStartTime = beraReservePreSaleBond.tgeStartTime();

        beraReservePreSaleBond.setBRRToken(address(beraReserveToken));

        beraReservePreSaleBond.mintBRR();
        vm.stopPrank();

        skip(5 hours);

        //Alice can unlock some of her BRR tokens
        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        uint256 aliceBRRafterFirstUnlockAmount =
            (aliceInfo.totalAmount * (block.timestamp - tgeStartTime)) / aliceInfo.duration;

        assertEq(
            beraReserveToken.balanceOf(ALICE), aliceBRRafterFirstUnlockAmount, "Alice BRR after first unlock should"
        );

        skip(5 hours);
        vm.prank(BOB);
        beraReservePreSaleBond.unlockBRR();

        uint256 bobBRRafterFirstUnlockAmount =
            (bobInfo.totalAmount * (block.timestamp - tgeStartTime)) / bobInfo.duration;

        assertEq(beraReserveToken.balanceOf(BOB), bobBRRafterFirstUnlockAmount, "Bob BRR after first unlock should");

        skip(2 days);

        vm.prank(BOB);
        beraReservePreSaleBond.unlockBRR();

        uint256 bobBRRafterSecondUnlockAmount =
            (bobInfo.totalAmount * (block.timestamp - tgeStartTime)) / bobInfo.duration;

        assertEq(beraReserveToken.balanceOf(BOB), bobBRRafterSecondUnlockAmount, "Bob BRR after second unlock should");

        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        uint256 aliceBRRafterSecondUnlockAmount =
            (aliceInfo.totalAmount * (block.timestamp - tgeStartTime)) / aliceInfo.duration;

        assertEq(
            beraReserveToken.balanceOf(ALICE), aliceBRRafterSecondUnlockAmount, "Alice BRR after second unlock should"
        );

        //skip over 5 days to unlock all BRR.
        skip(10 days);

        vm.prank(BOB);
        beraReservePreSaleBond.unlockBRR();

        assertEq(beraReserveToken.balanceOf(BOB), bobInfo.totalAmount, "Bob BRR after third unlock should be 2_500e9");

        vm.prank(ALICE);
        beraReservePreSaleBond.unlockBRR();

        assertEq(
            beraReserveToken.balanceOf(ALICE), aliceInfo.totalAmount, "Alice BRR after third unlock should be 2_500e9"
        );
    }

    function testFuzz__ExcessBRRPurchaseTriggersCappingAndRefund(uint256 initialUsdcAmount, uint256 finalUsdcAmount)
        public
    {
        initialUsdcAmount = bound(initialUsdcAmount, 1e18, 500e18); // Bound initial purchase to a reasonable range
        finalUsdcAmount = bound(finalUsdcAmount, 1e18, 10_000e18); // Bound final purchase to ensure it can exceed available BRR

        vm.prank(BERA_RESERVE_ADMIN);
        beraReservePreSaleBond.startPreSaleBond();

        bytes32[] memory aliceMerkleProof = new bytes32[](2);
        aliceMerkleProof[0] = 0xbb0745f54018a76d4ca8a8655b17f292e8c9b0c2d5cb259512fa1357ef1b2111;
        aliceMerkleProof[1] = 0x2e8058287f647a7e8c8f2d388d1a09a208fdd8429d084bda5fb88dbb1de9330e;

        bytes32[] memory bobMerkleProof = new bytes32[](3);
        bobMerkleProof[0] = 0x865691bb9d0da996e195701fa966f9e49fd926d43741e9ee2e315c2e48634975;
        bobMerkleProof[1] = 0xf5e216537885c6784fa9337c71858ba1ad15eeee33bf5449f3e09e462fe1c660;
        bobMerkleProof[2] = 0xaf43dfbc8da21120f0a049b6c60858e1cb75b6f6852f8e70688037fe58bb047b;

        //uint256 totalBRRBefore = beraReservePreSaleBond.bRRTokensAvailable();

        // ALICE makes an initial purchase
        vm.startPrank(ALICE);
        usdc.approve(address(beraReservePreSaleBond), initialUsdcAmount);
        beraReservePreSaleBond.purchaseBRR(initialUsdcAmount, aliceMerkleProof);
        vm.stopPrank();

        // Get updated available BRR
        uint256 remainingBRR = beraReservePreSaleBond.bRRTokensAvailable();

        // Ensure that ALICE's purchase didn't deplete BRR supply
        assertGt(remainingBRR, 0, "Remaining BRR should be > 0 after Alice's purchase");

        // BOB tries to purchase more than available BRR
        vm.startPrank(BOB);
        usdc.approve(address(beraReservePreSaleBond), finalUsdcAmount);

        //uint256 bobBalanceBefore = usdc.balanceOf(BOB);
        beraReservePreSaleBond.purchaseBRR(finalUsdcAmount, bobMerkleProof);
        //uint256 bobBalanceAfter = usdc.balanceOf(BOB);

        vm.stopPrank();
    }
}
