// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { BeraReserveToken } from "../../src/BeraReserveToken.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BeraReserveStaking } from "../../src/Staking.sol";
import { DistributorV2 } from "../../src/StakingDistributorV2.sol";
import { BeraReservePreBondClaims } from "../../src/BeraReservePreBondClaims.sol";

interface IWBERA is IERC20 {
    function deposit(uint256 bera) external payable;
}

contract BeraReserveConfigScriptV2 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    BeraReserveToken public beraReserveToken = BeraReserveToken(payable(0x885a71E726Fe7828d84B876e42C48F97990a5c9d));
    address public uniswapV2Pair = 0xa8f9d7Ea6Baa104454bbcAD647A4c8b17778969C;
    DistributorV2 public distributor = DistributorV2(0x5a7fa3a2e1C7c794413F1daC409f1cE60666fCAB);
    BeraReserveStaking.CONTRACTS public contracts;
    BeraReserveStaking public staking = BeraReserveStaking(0x6DC3FbEe136385D5B32A103f4BB6d9Fd5E2f8762);
    BeraReservePreBondClaims public preBondClaims = BeraReservePreBondClaims(0x8B1104c8adf85b67aB22F0A39985A75E2dDc4650);
    address public newPair = 0xa8f9d7Ea6Baa104454bbcAD647A4c8b17778969C;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        beraReserveToken.updateUniswapV2Pair(newPair);

        preBondClaims.unpause();

        preBondClaims.setTgeStartTime();

        vm.stopBroadcast();
    }
}
