// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import {BeraReserveBondDepositoryV2} from "../../src/BeraReserveBondDepositoryV2.sol";
import {BeraReserveUniswapV2TwapOracle} from "../../src/utils/BeraReserveUniswapV2TwapOracle.sol";
import {BeraReserveTreasuryV2} from "../../src/BeraReserveTreasuryV2.sol";
import {BeraReserveToken} from "../../src/BeraReserveToken.sol";
import { BeraReserveBondingCalculator } from "src/BeraReserveBondingCalculator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract BeraReserveDeploymentScriptV3 is Script {
    address public constant BERA_RESERVE_ADMIN = 0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF;
    address public constant BERA_RESERVE_MAIN_ADMIN = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;

    address public constant BRR_HONEY_PAIR = 0xa8f9d7Ea6Baa104454bbcAD647A4c8b17778969C;
    BeraReserveToken public beraReserveToken = BeraReserveToken(payable(0x885a71E726Fe7828d84B876e42C48F97990a5c9d));
    address public constant USDC_TOKEN = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address public constant FEE_DISTRIBUTOR = 0xC6cB8A7425855F2931709Ac9c19E4622b555e646;
    address public USDC_WHALE = 0xAB961d7C42BBcd454A54b342Bd191a8f090219E6;


    BeraReserveBondDepositoryV2 public usdcDepository;
    BeraReserveBondDepositoryV2 public lpDepository;
    BeraReserveBondingCalculator public bondingCalculator;
    BeraReserveUniswapV2TwapOracle public brrHoneyTwapOracle;
    BeraReserveTreasuryV2 public treasury;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bondingCalculator = new BeraReserveBondingCalculator(address(beraReserveToken));
      
        brrHoneyTwapOracle = new BeraReserveUniswapV2TwapOracle(
            BRR_HONEY_PAIR
        );

        treasury = new BeraReserveTreasuryV2(
            BERA_RESERVE_ADMIN,
            address(beraReserveToken),
            USDC_TOKEN,
            BRR_HONEY_PAIR
        );
        
        usdcDepository = new BeraReserveBondDepositoryV2(
            address(beraReserveToken),
            USDC_TOKEN,
            address(treasury),
            FEE_DISTRIBUTOR,
            BERA_RESERVE_ADMIN,
            address(0),
            address(brrHoneyTwapOracle)
        ); 

        /**
         * @dev Initialize the USDC Depository with the following terms:
         * - Vesting Term: 216,000 seconds 5 days
         * - Max Payout: 0.5% of 40,000 BRR (200 BRR)
         * - Fee: 100 basis points (1%)
         * - Discount Rate: 50 basis points (0.5%)
         * - Max Debt: 40,000 BRR
         */
        usdcDepository.initializeBondTerms(216_000, 50, 100, 50, 40_000e9);

        lpDepository = new BeraReserveBondDepositoryV2(
            address(beraReserveToken),
            BRR_HONEY_PAIR,
            address(treasury),
            FEE_DISTRIBUTOR,
            BERA_RESERVE_ADMIN,
            address(bondingCalculator),
            address(brrHoneyTwapOracle)
        );

        lpDepository.initializeBondTerms(216_000, 50, 100, 50, 40_000e9);

        treasury.setReserveDepositor(address(usdcDepository), true);

        treasury.setLiquidityDepositor(address(lpDepository), true);

        treasury.setLiquidityToken(BRR_HONEY_PAIR, true);

        //!set allocations
        //beraReserveToken.setAllocationLimit(address(treasury), 40_000e9);

        vm.stopBroadcast();

        vm.prank(BERA_RESERVE_MAIN_ADMIN);
        beraReserveToken.setAllocationLimit(address(treasury), 40_000e9);
        vm.stopPrank();

        _logDeployedContracts();

        _postDeploymentChecks();

        //buyBonds();
    }


    function _logDeployedContracts() internal view {
        console2.log("BeraReserveTWAP Oracle :", address(brrHoneyTwapOracle));
        console2.log("Treasury :", address(treasury));
        console2.log("USDC Depository :", address(usdcDepository)); 
        console2.log("LP Depository :", address(lpDepository));
        
    }

    function _postDeploymentChecks() internal view {
        require(address(treasury.BRR_TOKEN()) == address(beraReserveToken), "Treasury BRR_TOKEN mismatch");
        require(treasury.pair() == BRR_HONEY_PAIR, "Treasury pair mismatch");
        require(treasury.isReserveToken(USDC_TOKEN), "Treasury USDC_TOKEN mismatch");
        require(treasury.isLiquidityToken(BRR_HONEY_PAIR), "Treasury BRR_HONEY_PAIR mismatch");

        
        require(usdcDepository.principle() == USDC_TOKEN, "USDC Depository principle mismatch");
        require(address(usdcDepository.twap()) == address(brrHoneyTwapOracle), "USDC Depository TWAP mismatch");
        require(address(usdcDepository.treasury()) == address(treasury), "USDC Depository treasury mismatch");
        require(address(usdcDepository.dao()) == FEE_DISTRIBUTOR, "USDC Depository DAO mismatch");

        (uint256 vestingTerm, uint256 maxPayout, uint256 fee, uint256 discountRate, uint256 maxDebt) = usdcDepository.terms();
        require(vestingTerm == 216_000, "Vesting term mismatch");
        require(maxPayout == 50, "Max payout mismatch");
        require(fee == 100, "Fee mismatch");
        require(discountRate == 50, "Discount rate mismatch");
        require(maxDebt == 40_000e9, "Max debt mismatch");

       

        require(address(lpDepository.treasury()) == address(treasury), "LP Depository treasury mismatch");
        require(address(lpDepository.dao()) == FEE_DISTRIBUTOR, "LP Depository DAO mismatch");
        require(address(lpDepository.twap()) == address(brrHoneyTwapOracle), "LP Depository TWAP mismatch");
        require(lpDepository.principle() == BRR_HONEY_PAIR, "LP Depository principle mismatch");

         (vestingTerm, maxPayout, fee, discountRate, maxDebt) = lpDepository.terms();
        require(vestingTerm == 216_000, "LP Vesting term mismatch");
        require(maxPayout == 50, "LP Max payout mismatch");
        require(fee == 100, "LP Fee mismatch");
        require(discountRate == 50, "LP Discount rate mismatch");
        require(maxDebt == 40_000e9, "LP Max debt mismatch");     
    }

    function buyBonds() public {
        vm.startBroadcast(USDC_WHALE);

        IERC20(USDC_TOKEN).approve(address(usdcDepository), 100e6);
         usdcDepository.deposit(50e6, 1.2e18);
        vm.stopBroadcast();
    }
}
