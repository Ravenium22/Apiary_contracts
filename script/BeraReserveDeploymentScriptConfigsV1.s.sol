// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { BeraReserveToken } from "../src/BeraReserveToken.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { sBeraReserve } from "../src/sBeraReserveERC20.sol";
import { BeraReserveStaking } from "../src/Staking.sol";
import { BeraReserveTreasury } from "../src/Treasury.sol";
import { BeraReserveBondDepository } from "../src/BondDepository.sol";
import { Distributor } from "../src/StakingDistributor.sol";

interface IWBERA is IERC20 {
    function deposit(uint256 bera) external payable;
}

contract BeraReserveConfigScriptV1 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    BeraReserveToken public beraReserveToken = BeraReserveToken(payable(0x54968986A1f231bAA6f4f8f92bb03d02f5383E2C));
    sBeraReserve public sBeraReserveToken = sBeraReserve(0x453e0Ce636ACd3A2dE115eB3deBe6dfc914A7c58);
    BeraReserveStaking public staking = BeraReserveStaking(0xF00Ac731FA3232B1238cB44A84B5875c0A514027);
    Distributor public distributor = Distributor(0x4D04812cE63CfC12B03e28eb2e37e8ab0e65DB34);
    BeraReserveStaking.CONTRACTS public contracts;
    BeraReserveBondDepository.PARAMETER public parameter;
    BeraReserveBondDepository usdcBondDepository = BeraReserveBondDepository(0xACEFDe613D8573405A56169Dc2c7f0504F539854);
    BeraReserveTreasury public treasury = BeraReserveTreasury(0xa62f03A696E61dDCf333e9A1Ed505c764F14b9D2);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BeraReserveTreasury.MANAGING _managing = BeraReserveTreasury.MANAGING.RESERVEDEPOSITOR;

        BeraReserveTreasury.MANAGING distributorManager = BeraReserveTreasury.MANAGING.REWARDMANAGER;

        BeraReserveTreasury.MANAGING sBRR_MANAGING = BeraReserveTreasury.MANAGING.SBRR;

        treasury.toggle(_managing, address(usdcBondDepository), address(0));

        treasury.toggle(distributorManager, address(distributor), address(0));

        treasury.toggle(sBRR_MANAGING, address(sBeraReserveToken), address(0));

        vm.stopBroadcast();
    }

    function _postDeploymentChecks() internal view {
        require(address(treasury.sBRR()) == address(sBeraReserveToken), "Treasury: sBRR contract != sBRR");
        require(treasury.isReserveToken(address(beraReserveToken)), "BRR contract not reserve token");
        require(
            treasury.isReserveDepositor(address(usdcBondDepository)),
            "usdcBondDepository contract not reserve depositor"
        );
        require(treasury.isRewardManager(address(distributor)), "distributor contract not reward manager");
    }
}
