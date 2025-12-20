// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IApiaryToken } from "./interfaces/IApiaryToken.sol";
import { IApiaryTreasury } from "./interfaces/IApiaryTreasury.sol";

/**
 * @title ApiaryTreasury
 * @notice Manages protocol reserves with iBGT as the primary reserve token
 * @dev Holds reserves, mints APIARY tokens for deposits, and coordinates with yield manager
 *      for iBGT staking on Infrared protocol
 * 
 * Flow:
 * 1. Bond depositors deposit iBGT → Treasury holds it
 * 2. Yield manager pulls iBGT → Stakes on Infrared
 * 3. Yield manager returns iBGT + rewards → Treasury receives it
 * 
 * Phase 1: Treasury holds iBGT without staking (yield manager not set)
 * Phase 2: Yield manager actively manages iBGT staking
 */
contract ApiaryTreasury is IApiaryTreasury, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    
    IApiaryToken public immutable APIARY_TOKEN;
    address public immutable APIARY_HONEY_LP;  // Kodiak APIARY/HONEY LP token
    address public immutable IBGT;              // iBGT token address
    address public immutable HONEY;             // HONEY token address

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    // Authorization mappings
    mapping(address => bool) public isReserveToken;
    mapping(address => bool) public isLiquidityToken;
    mapping(address => bool) public isReserveDepositor;
    mapping(address => bool) public isLiquidityDepositor;
    
    // Accounting mappings
    mapping(address => uint256) public totalReserves;
    mapping(address => uint256) public totalBorrowed;
    
    // Special role addresses
    address public reservesManager;
    address public yieldManager;
    
    // iBGT-specific accounting
    IBGTAccounting private _ibgtAccounting;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_TOKEN();
    error APIARY__UNAUTHORIZED_RESERVE_MANAGER();
    error APIARY__UNAUTHORIZED_YIELD_MANAGER();
    error APIARY__INVALID_LIQUIDITY_DEPOSITOR();
    error APIARY__INVALID_RESERVE_DEPOSITOR();
    error APIARY__INSUFFICIENT_IBGT_AVAILABLE();
    error APIARY__INSUFFICIENT_IBGT_STAKED();
    error APIARY__INVALID_PRINCIPAL_AMOUNT();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyReserveManager() {
        if (msg.sender != reservesManager) revert APIARY__UNAUTHORIZED_RESERVE_MANAGER();
        _;
    }

    modifier onlyYieldManager() {
        if (msg.sender != yieldManager) revert APIARY__UNAUTHORIZED_YIELD_MANAGER();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize the treasury contract
     * @param admin Address of the admin (multisig recommended)
     * @param _apiary Address of APIARY token contract
     * @param _ibgt Address of iBGT token
     * @param _honey Address of HONEY token
     * @param _apiaryHoneyLP Address of APIARY/HONEY LP token from Kodiak
     */
    constructor(
        address admin,
        address _apiary,
        address _ibgt,
        address _honey,
        address _apiaryHoneyLP
    ) Ownable(admin) {
        if (
            _apiary == address(0) ||
            _ibgt == address(0) ||
            _honey == address(0) ||
            _apiaryHoneyLP == address(0)
        ) {
            revert APIARY__ZERO_ADDRESS();
        }

        APIARY_TOKEN = IApiaryToken(_apiary);
        IBGT = _ibgt;
        HONEY = _honey;
        APIARY_HONEY_LP = _apiaryHoneyLP;

        // Set iBGT as approved reserve token
        isReserveToken[_ibgt] = true;
        
        // Set APIARY/HONEY LP as approved liquidity token
        isLiquidityToken[_apiaryHoneyLP] = true;
        
        // Initialize iBGT accounting
        _ibgtAccounting = IBGTAccounting({
            totalDeposited: 0,
            totalStaked: 0,
            totalReturned: 0,
            availableBalance: 0
        });
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit reserve or liquidity tokens in exchange for APIARY
     * @dev Only authorized depositors can call this
     *      For iBGT deposits, updates special accounting
     * @param _amount Amount of tokens to deposit
     * @param _token Address of token being deposited
     * @param value Amount of APIARY to mint to depositor
     * @return Amount of APIARY minted
     */
    function deposit(
        uint256 _amount,
        address _token,
        uint256 value
    ) external override nonReentrant returns (uint256) {
        // Validate token is approved
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) {
            revert APIARY__INVALID_TOKEN();
        }

        // Check authorization
        if (isReserveToken[_token]) {
            if (!isReserveDepositor[msg.sender]) {
                revert APIARY__INVALID_RESERVE_DEPOSITOR();
            }
        } else if (isLiquidityToken[_token]) {
            if (!isLiquidityDepositor[msg.sender]) {
                revert APIARY__INVALID_LIQUIDITY_DEPOSITOR();
            }
        }

        // Transfer tokens from depositor to treasury
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Update reserves accounting
        totalReserves[_token] += _amount;

        // Special accounting for iBGT
        if (_token == IBGT) {
            _ibgtAccounting.totalDeposited += _amount;
            _ibgtAccounting.availableBalance += _amount;
        }

        // Mint APIARY to depositor
        // Note: Treasury must have mint allocation in APIARY token contract
        APIARY_TOKEN.mint(msg.sender, value);

        emit Deposit(_token, _amount, value);

        return value;
    }

    /*//////////////////////////////////////////////////////////////
                    RESERVE MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Borrow reserves from treasury (only reserves manager)
     * @dev Allows reserves manager to temporarily borrow reserves
     * @param _amount Amount to borrow
     * @param _token Token to borrow
     */
    function borrowReserves(
        uint256 _amount,
        address _token
    ) external override onlyReserveManager nonReentrant {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) {
            revert APIARY__INVALID_TOKEN();
        }

        totalReserves[_token] -= _amount;
        totalBorrowed[_token] += _amount;

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, _amount);
    }

    /**
     * @notice Repay borrowed reserves
     * @param _amount Amount to repay
     * @param _token Token to repay
     */
    function repayReserves(
        uint256 _amount,
        address _token
    ) external override onlyReserveManager nonReentrant {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) {
            revert APIARY__INVALID_TOKEN();
        }

        totalBorrowed[_token] -= _amount;
        totalReserves[_token] += _amount;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit ReservesRepaid(_token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                    YIELD MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Pull iBGT from treasury for staking on Infrared
     * @dev Only yield manager can call this
     *      Updates accounting to track staked vs available iBGT
     * @param _amount Amount of iBGT to pull for staking
     */
    function pullIBGTForStaking(uint256 _amount) 
        external 
        override 
        onlyYieldManager 
        nonReentrant 
    {
        // Verify sufficient iBGT available
        if (_amount > _ibgtAccounting.availableBalance) {
            revert APIARY__INSUFFICIENT_IBGT_AVAILABLE();
        }

        // Update accounting
        _ibgtAccounting.availableBalance -= _amount;
        _ibgtAccounting.totalStaked += _amount;

        // Transfer iBGT to yield manager
        IERC20(IBGT).safeTransfer(msg.sender, _amount);

        emit IBGTPulledForStaking(_amount, msg.sender);
    }

    /**
     * @notice Return iBGT and rewards from staking to treasury
     * @dev Only yield manager can call this
     *      Tracks principal repayment and rewards separately
     * @param _amount Total amount being returned (principal + rewards)
     * @param _principal Amount of original iBGT that was staked
     */
    function returnIBGTFromStaking(
        uint256 _amount,
        uint256 _principal
    ) external override onlyYieldManager nonReentrant {
        // Validate principal amount doesn't exceed staked
        if (_principal > _ibgtAccounting.totalStaked) {
            revert APIARY__INSUFFICIENT_IBGT_STAKED();
        }

        // Validate amount is at least principal (can't return less than staked)
        if (_amount < _principal) {
            revert APIARY__INVALID_PRINCIPAL_AMOUNT();
        }

        // Calculate rewards (amount - principal)
        uint256 rewards = _amount - _principal;

        // Update accounting
        _ibgtAccounting.totalStaked -= _principal;
        _ibgtAccounting.availableBalance += _amount;
        _ibgtAccounting.totalReturned += _amount;

        // If there are rewards, increase total reserves
        if (rewards > 0) {
            totalReserves[IBGT] += rewards;
        }

        // Transfer iBGT + rewards back to treasury
        IERC20(IBGT).safeTransferFrom(msg.sender, address(this), _amount);

        emit IBGTReturnedFromStaking(_amount, rewards);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set the reserves manager address
     * @param _manager Address of reserves manager
     */
    function setReservesManager(address _manager) external override onlyOwner {
        if (_manager == address(0)) revert APIARY__ZERO_ADDRESS();
        reservesManager = _manager;
        emit ReservesManagerSet(_manager);
    }

    /**
     * @notice Set the yield manager address
     * @dev Yield manager handles iBGT staking on Infrared
     * @param _yieldManager Address of yield manager
     */
    function setYieldManager(address _yieldManager) external override onlyOwner {
        if (_yieldManager == address(0)) revert APIARY__ZERO_ADDRESS();
        yieldManager = _yieldManager;
        emit YieldManagerSet(_yieldManager);
    }

    /**
     * @notice Set reserve depositor authorization
     * @param _depositor Address of depositor (e.g., bond depository)
     * @param _status Authorization status
     */
    function setReserveDepositor(
        address _depositor,
        bool _status
    ) external override onlyOwner {
        if (_depositor == address(0)) revert APIARY__ZERO_ADDRESS();
        isReserveDepositor[_depositor] = _status;
        emit ReserveDepositorSet(_depositor, _status);
    }

    /**
     * @notice Set liquidity depositor authorization
     * @param _depositor Address of depositor
     * @param _status Authorization status
     */
    function setLiquidityDepositor(
        address _depositor,
        bool _status
    ) external override onlyOwner {
        if (_depositor == address(0)) revert APIARY__ZERO_ADDRESS();
        isLiquidityDepositor[_depositor] = _status;
        emit LiquidityDepositorSet(_depositor, _status);
    }

    /**
     * @notice Set reserve token approval status
     * @param _token Token address
     * @param _status Approval status
     */
    function setReserveToken(
        address _token,
        bool _status
    ) external override onlyOwner {
        isReserveToken[_token] = _status;
        emit ReserveTokenSet(_token, _status);
    }

    /**
     * @notice Set liquidity token approval status
     * @param _token Token address
     * @param _status Approval status
     */
    function setLiquidityToken(
        address _token,
        bool _status
    ) external override onlyOwner {
        isLiquidityToken[_token] = _status;
        emit LiquidityTokenSet(_token, _status);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get iBGT accounting details
     * @return IBGTAccounting struct with all iBGT tracking data
     */
    function getIBGTAccounting() external view override returns (IBGTAccounting memory) {
        return _ibgtAccounting;
    }

    /**
     * @notice Get actual iBGT balance in treasury
     * @return Current iBGT balance held by contract
     */
    function getIBGTBalance() external view returns (uint256) {
        return IERC20(IBGT).balanceOf(address(this));
    }

    /**
     * @notice Get HONEY balance in treasury
     * @return Current HONEY balance held by contract
     */
    function getHONEYBalance() external view returns (uint256) {
        return IERC20(HONEY).balanceOf(address(this));
    }

    /**
     * @notice Get APIARY/HONEY LP balance in treasury
     * @return Current LP token balance held by contract
     */
    function getLPBalance() external view returns (uint256) {
        return IERC20(APIARY_HONEY_LP).balanceOf(address(this));
    }
}
