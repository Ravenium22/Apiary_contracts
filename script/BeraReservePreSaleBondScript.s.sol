// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { BeraReservePreSaleBond } from "../src/BeraReservePreSaleBond.sol";
import { USDC } from "../src/mocks/USDC.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BeraReservePreSaleBondScript is Script {
    address public constant BERA_RESERVE_DEPLOYER = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    address public constant ADMIN_WALLET = 0xB3acA3a3c4D10eEd121489d37702865Be750B743;
    bytes32 public constant MERKLE_ROOT = 0xb88ff5c2325cbacbb1a30b8f5f2a996edb0035e51f841629412a1f335e0c65b6;
    address public constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    BeraReservePreSaleBond public preSale;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        preSale = new BeraReservePreSaleBond(HONEY, ADMIN_WALLET, BERA_RESERVE_DEPLOYER, MERKLE_ROOT);
        preSale.transferOwnership(ADMIN_WALLET);

        vm.stopBroadcast();

        //log Deployment
        console2.log("PreSaleBond deployed to:", address(preSale));

        validateConfig();
    }

    function validateConfig() public view {
        assert(address(preSale.honey()) == HONEY);
        assert(preSale.protocolMultisig() == ADMIN_WALLET);
        assert(preSale.merkleRoot() == MERKLE_ROOT);
    }

    /**
     * PreSaleBond deployed to: 0xb90200C9b292e5a1C348baeb050c1dAF2D3f739a
     * forge script
     *  script/BeraReservePreSaleBondScript.s.sol
     *  --broadcast
     *  --rpc-url 127.0.0.1:8545
     *  --verify -vvv
     */
}
