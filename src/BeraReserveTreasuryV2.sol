// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBeraReserveToken } from "./interfaces/IBeraReserveToken.sol";
import { IBeraReserveTreasuryV2 } from "./interfaces/IBeraReserveTreasuryV2.sol";

/**
 * @title BeraReserveTreasuryV2
 * @author 0xm00k
 * @notice Holds protocol reserves and mints BRR tokens in exchange for approved deposits.
 *  Allows the owner to withdraw reserve assets.
 */
contract BeraReserveTreasuryV2 is IBeraReserveTreasuryV2, Ownable2Step {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    IBeraReserveToken public immutable BRR_TOKEN;
    address public immutable pair;
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => bool) public isReserveToken;
    mapping(address => bool) public isLiquidityToken;
    mapping(address => bool) public isReserveDepositor;
    mapping(address => bool) public isLiquidityDepositor;
    mapping(address => uint256) public totalReserves;
    mapping(address => uint256) public totalBorrowed;
    address public reservesManager;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error InvalidToken();
    error UnAuthorizedReserveManager();
    error InvalidLiquidityDepositor();
    error InvalidReserveDepositor();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount);
    event ReservesRepaid(address indexed token, uint256 amount);

    modifier onlyReserveManager() {
        if (msg.sender != reservesManager) revert UnAuthorizedReserveManager();
        _;
    }

    constructor(address admin, address _brr, address _usdc, address _lp) Ownable(admin) {
        if (_brr == address(0) || _usdc == address(0) || _lp == address(0)) {
            revert ZeroAddress();
        }

        BRR_TOKEN = IBeraReserveToken(_brr);
        pair = _lp;

        isReserveToken[_usdc] = true;
        isLiquidityToken[_lp] = true;
    }

    function deposit(uint256 _amount, address _token, uint256 value) external override returns (uint256) {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();

        if (isReserveToken[_token]) {
            if (!isReserveDepositor[msg.sender]) revert InvalidReserveDepositor();
        } else if (isLiquidityToken[_token]) {
            if (!isLiquidityDepositor[msg.sender]) revert InvalidLiquidityDepositor();
        }

        //@dev approved from depository contract
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        totalReserves[_token] += _amount;

        //@dev treasury has to have been allowed allocation of tokens in the BRR contract
        BRR_TOKEN.mint(msg.sender, value);

        emit Deposit(_token, _amount, value);

        return value;
    }

    /**
     * ADMIN FUNCTIONS
     */
    function borrowReserves(uint256 _amount, address _token) external override onlyReserveManager {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();

        totalReserves[_token] -= _amount;
        totalBorrowed[_token] += _amount;

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, _amount);
    }

    function repayReserves(uint256 _amount, address _token) external override onlyReserveManager {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();

        totalBorrowed[_token] -= _amount;
        totalReserves[_token] += _amount;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit ReservesRepaid(_token, _amount);
    }

    function setReservesManager(address _manager) external override onlyOwner {
        if (_manager == address(0)) revert ZeroAddress();
        reservesManager = _manager;
    }

    function setReserveDepositor(address _depositor, bool _status) external override onlyOwner {
        if (_depositor == address(0)) revert ZeroAddress();
        isReserveDepositor[_depositor] = _status;
    }

    function setLiquidityDepositor(address _depositor, bool _status) external override onlyOwner {
        if (_depositor == address(0)) revert ZeroAddress();
        isLiquidityDepositor[_depositor] = _status;
    }

    function setReserveToken(address _token, bool _status) external override onlyOwner {
        isReserveToken[_token] = _status;
    }

    function setLiquidityToken(address _token, bool _status) external override onlyOwner {
        isLiquidityToken[_token] = _status;
    }
}
