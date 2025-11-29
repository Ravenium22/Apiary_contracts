// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { BeraReserveToken } from "../src/BeraReserveToken.sol";
import { BeraReserveTreasury } from "../src/Treasury.sol";
import { BeraReserveBondDepository } from "../src/BondDepository.sol";

contract BeraReserveConfigScriptV1 is Script {
    BeraReserveBondDepository brrHoneyDepository = BeraReserveBondDepository(0x472f65f00d35D677F45e02bB02ad3D7cDA460789); //!change with real address
    BeraReserveTreasury public treasury = BeraReserveTreasury(0x692f78bbdA0387F323eEfCEEB4153CFd3C81C6E5); //!change with real address
    address brrHoneyPair = 0x5C22d7AC7D2CDdD5d6563F4685207CF418b46748; //!change with real address
    address public bondCalculator = 0x0fb8b986e4F9246FE77ee45b26ED02acc3703Ec7; //!change with real address

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BeraReserveTreasury.MANAGING _brrHoneyManaging = BeraReserveTreasury.MANAGING.LIQUIDITYDEPOSITOR;

        BeraReserveTreasury.MANAGING LP_TOKEN = BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN;

        treasury.toggle(_brrHoneyManaging, address(brrHoneyDepository), bondCalculator);

        treasury.toggle(LP_TOKEN, brrHoneyPair, bondCalculator);

        vm.stopBroadcast();
    }
}
