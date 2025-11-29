// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { Script, console2 } from "forge-std/Script.sol";
import { BeraReserveToken } from "../../src/BeraReserveToken.sol";
import { sBeraReserve } from "../../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../../src/Staking.sol";
import { DistributorV2 } from "../../src/StakingDistributorV2.sol";
import { BeraReserveLockUp } from "../../src/BeraReserveLockUp.sol";
import { BeraReserveFeeDistributor } from "../../src/BeraReserveFeeDistributor.sol";
import { BeraReservePreBondClaims } from "../../src/BeraReservePreBondClaims.sol";

contract BeraReserveDeploymentTransferOwnership is Script {
    address public constant BERA_RESERVE_ADMIN_DEPLOYER = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    address public constant BERA_RESERVE_ADMIN = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    BeraReserveToken public constant beraReserveToken = BeraReserveToken(0x885a71E726Fe7828d84B876e42C48F97990a5c9d);
    sBeraReserve public constant sBeraReserveToken = sBeraReserve(0xDb062B6769cC17ddd055e1A4001F7709Bed0c2c0);
    BeraReserveStaking public constant staking = BeraReserveStaking(0x6DC3FbEe136385D5B32A103f4BB6d9Fd5E2f8762);
    DistributorV2 public constant distributorV2 = DistributorV2(0x5a7fa3a2e1C7c794413F1daC409f1cE60666fCAB);
    BeraReserveLockUp public constant lockUp = BeraReserveLockUp(0xAB36e285D57679eBBe95b58afA0961951F21C08B);
    BeraReserveFeeDistributor public constant feeDistributor =
        BeraReserveFeeDistributor(0xC6cB8A7425855F2931709Ac9c19E4622b555e646);
    BeraReservePreBondClaims public constant preBondClaims =
        BeraReservePreBondClaims(0x8B1104c8adf85b67aB22F0A39985A75E2dDc4650);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Transfer ownership of BeraReserveToken
        beraReserveToken.grantRole(DEFAULT_ADMIN_ROLE, BERA_RESERVE_ADMIN);

        beraReserveToken.revokeRole(DEFAULT_ADMIN_ROLE, BERA_RESERVE_ADMIN_DEPLOYER);

        // Transfer ownership of sBeraReserve
        sBeraReserveToken.pushManagement(BERA_RESERVE_ADMIN);

        // Transfer ownership of Staking
        staking.pushManagement(BERA_RESERVE_ADMIN);

        // Transfer ownership of DistributorV2
        distributorV2.pushPolicy(BERA_RESERVE_ADMIN);

        // Transfer ownership of BeraReserveLockUp
        lockUp.transferOwnership(BERA_RESERVE_ADMIN);

        // Transfer ownership of BeraReserveFeeDistributor
        feeDistributor.transferOwnership(BERA_RESERVE_ADMIN);

        // Transfer ownership of BeraReservePreBondClaims
        preBondClaims.transferOwnership(BERA_RESERVE_ADMIN);

        vm.stopBroadcast();

        _postDeploymentChecks();
    }

    function _postDeploymentChecks() internal view {
        require(beraReserveToken.hasRole(DEFAULT_ADMIN_ROLE, BERA_RESERVE_ADMIN), "Ownership not transferred");
        require(lockUp.pendingOwner() == BERA_RESERVE_ADMIN, "Ownership not transferred");
        require(feeDistributor.pendingOwner() == BERA_RESERVE_ADMIN, "Ownership not transferred");
        require(preBondClaims.pendingOwner() == BERA_RESERVE_ADMIN, "Ownership not transferred");

        //!comment out before mainnet deployment
        // //simulate new owner
        // vm.startPrank(BERA_RESERVE_ADMIN);

        // beraReserveToken.setBuyFee(2_000);

        // sBeraReserveToken.pullManagement();

        // console2.log("sBeraReserveToken management pulled", sBeraReserveToken.manager());

        // staking.pullManagement();

        // console2.log("Staking management pulled", staking.manager());

        // distributorV2.pullPolicy();
        // distributorV2.addRecipient(address(lockUp), 23);

        // console2.log("DistributorV2 policy pulled", distributorV2.policy());

        // lockUp.acceptOwnership();

        // console2.log("LockUp ownership accepted", lockUp.owner());

        // feeDistributor.acceptOwnership();

        // console2.log("FeeDistributor ownership accepted", feeDistributor.owner());

        // preBondClaims.acceptOwnership();

        // console2.log("PreBondClaims ownership accepted", preBondClaims.owner());

        // vm.stopPrank();
    }
}
