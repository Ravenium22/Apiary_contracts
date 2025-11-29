// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { BeraReserveToken } from "../src/BeraReserveToken.sol";
// import { VaultOwned } from "../src/VaultOwned.sol";
// import { sBeraReserve } from "../src/sBeraReserveERC20.sol";
// import { BeraReserveStaking } from "../src/Staking.sol";
import { BeraReserveTreasury } from "../src/Treasury.sol";
import { BeraReserveBondDepository } from "../src/BondDepository.sol";
// import { StakingWarmup } from "../src/StakingWarmup.sol";
// import { BeraReserveBondingCalculator } from "../src/StandardBondingCalculator.sol";
// import { Distributor } from "../src/StakingDistributor.sol";
// import { StakingHelper } from "../src/StakingHelper.sol";
// import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
// import { BeraReserveLockUp } from "../src/BeraReserveLockUp.sol";
// import { BeraReservePreSaleBond } from "../src/BeraReservePreSaleBond.sol";
// import { BeraReserveFeeDistributor } from "../src/BeraReserveFeeDistributor.sol";
// import { IUniswapV2Factory, IUniswapV2Router02 } from "src/BeraReserveToken.sol";

contract BeraReserveBRRHoneyScriptV1 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    BeraReserveBondDepository public brrHoneyBondDepository;
    address public brrHoneyPair = 0x5C22d7AC7D2CDdD5d6563F4685207CF418b46748; //!change with real address
    address public bondingCalculator = 0x0fb8b986e4F9246FE77ee45b26ED02acc3703Ec7; //!change with real address
    address public staking = 0x4703Ce2C637C50A1dF7122f5678A7eD18A509f84; //!change with real address
    BeraReserveToken public beraReserveToken = BeraReserveToken(payable(0x21AA3A1277833aEB47fcae1EdB3782b750A756D7)); //!change with real address
    BeraReserveTreasury public treasury = BeraReserveTreasury(0x692f78bbdA0387F323eEfCEEB4153CFd3C81C6E5); //!change with real address

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        brrHoneyBondDepository = new BeraReserveBondDepository(
            address(beraReserveToken), brrHoneyPair, address(treasury), BERA_RESERVE_ADMIN, address(bondingCalculator)
        );

        beraReserveToken.excludeAccountFromFeesAndDecay(address(brrHoneyBondDepository), true);

        brrHoneyBondDepository.setStaking(address(staking), false);

        brrHoneyBondDepository.initializeBondTerms(
            2, //controlVariable
            216_000, //vestingTerm (~ 5 days)
            101, //minimumPrice //$1.01
            500, //maxPayout(0.5%)
            100, //fee (1%)
            40_000e9,
            0
        );

        beraReserveToken.excludeAccountFromFeesAndDecay(address(brrHoneyPair), true);
        //!needed?
        //beraReserveToken.excludeAccountFromFeesAndDecay(address(uniswapRouter), true);

        BeraReserveTreasury.MANAGING _brrHoneyManaging = BeraReserveTreasury.MANAGING.LIQUIDITYDEPOSITOR;

        BeraReserveTreasury.MANAGING LP_TOKEN = BeraReserveTreasury.MANAGING.LIQUIDITYTOKEN;

        treasury.queue(_brrHoneyManaging, address(brrHoneyBondDepository));

        treasury.queue(LP_TOKEN, brrHoneyPair);

        vm.stopBroadcast();
    }
}
