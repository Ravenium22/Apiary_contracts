// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IApiaryToken } from "./interfaces/IApiaryToken.sol";
import { IApiaryTreasury } from "./interfaces/IApiaryTreasury.sol";
import { IApiaryUniswapV2TwapOracle } from "./interfaces/IApiaryUniswapV2TwapOracle.sol";
import { IApiaryBondingCalculator } from "./interfaces/IApiaryBondingCalculator.sol";

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

    // TWAP oracle for APIARY pricing
    IApiaryUniswapV2TwapOracle public twapOracle;

    // LP bonding calculator for LP token valuation
    IApiaryBondingCalculator public lpCalculator;

    /// @notice H-02 Fix: Maximum APIARY mintable per deposit call (0 = unlimited)
    uint256 public maxMintPerDeposit;

    /// @notice HIGH-01 Fix: Maximum mint-to-deposit ratio in basis points (e.g., 12000 = 120%)
    /// @dev Prevents a compromised depositor from passing inflated value. 0 = disabled.
    uint256 public maxMintRatioBps;

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
    error APIARY__TWAP_NOT_SET();
    error APIARY__LP_CALCULATOR_NOT_SET();
    /// @notice H-02 Fix: Mint value exceeds maximum allowed per deposit
    error APIARY__EXCESSIVE_MINT_VALUE();
    /// @notice HIGH-01 Fix: Mint value exceeds allowed ratio relative to deposit amount
    error APIARY__EXCESSIVE_MINT_RATIO();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TwapOracleSet(address indexed twapOracle);
    event LPCalculatorSet(address indexed lpCalculator);
    /// @notice H-02 Fix: Emitted when max mint per deposit is updated
    event MaxMintPerDepositSet(uint256 maxMint);

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

        // H-02 Fix: Validate mint value is within bounds
        if (maxMintPerDeposit > 0 && value > maxMintPerDeposit) {
            revert APIARY__EXCESSIVE_MINT_VALUE();
        }

        // HIGH-01 Fix: Validate mint value is reasonable relative to deposit amount
        if (maxMintRatioBps > 0) {
            uint256 maxReasonableValue;
            if (isLiquidityToken[_token] && address(lpCalculator) != address(0)) {
                // For LP tokens, use bonding calculator for valuation
                uint256 calculatedValue = lpCalculator.valuation(_token, _amount);
                maxReasonableValue = (calculatedValue * maxMintRatioBps) / 10000;
            } else {
                // For reserve tokens (iBGT), value ~ amount adjusted for decimals
                // iBGT is 18 decimals, APIARY is 9 decimals, so 1e18 iBGT -> 1e9 APIARY
                maxReasonableValue = (_amount * maxMintRatioBps) / 10000;
            }
            if (value > maxReasonableValue) {
                revert APIARY__EXCESSIVE_MINT_RATIO();
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

    /**
     * @notice H-02 Fix: Set maximum APIARY mint value per deposit call
     * @dev Prevents a compromised depositor from minting disproportionate APIARY
     *      Set to 0 to disable the limit
     * @param _maxMint Maximum APIARY mintable per deposit (9 decimals)
     */
    function setMaxMintPerDeposit(uint256 _maxMint) external onlyOwner {
        maxMintPerDeposit = _maxMint;
        emit MaxMintPerDepositSet(_maxMint);
    }

    /**
     * @notice HIGH-01 Fix: Set maximum mint-to-deposit ratio
     * @dev Prevents depositors from minting disproportionate APIARY relative to deposit
     *      Set to 0 to disable ratio check. Recommended: 12000 (120%) for 20% tolerance.
     * @param _maxRatioBps Maximum ratio in basis points (e.g., 12000 = 120%)
     */
    function setMaxMintRatio(uint256 _maxRatioBps) external onlyOwner {
        maxMintRatioBps = _maxRatioBps;
    }

    /**
     * @notice Set the TWAP oracle for APIARY pricing
     * @param _twapOracle Address of the TWAP oracle
     */
    function setTwapOracle(address _twapOracle) external onlyOwner {
        if (_twapOracle == address(0)) revert APIARY__ZERO_ADDRESS();
        twapOracle = IApiaryUniswapV2TwapOracle(_twapOracle);
        emit TwapOracleSet(_twapOracle);
    }

    /**
     * @notice Set the LP bonding calculator for LP token valuation
     * @param _lpCalculator Address of the LP calculator
     */
    function setLPCalculator(address _lpCalculator) external onlyOwner {
        if (_lpCalculator == address(0)) revert APIARY__ZERO_ADDRESS();
        lpCalculator = IApiaryBondingCalculator(_lpCalculator);
        emit LPCalculatorSet(_lpCalculator);
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

    /**
     * @notice Calculate market cap and treasury value for protocol mode determination
     * @dev Market cap = APIARY total supply × current TWAP price
     *      Treasury value = iBGT balance (in HONEY terms) + LP token value
     * @return marketCap Market capitalization in HONEY (18 decimals)
     * @return treasuryValue Total treasury value in HONEY (18 decimals)
     */
    function getMarketCapAndTreasuryValue() external returns (uint256 marketCap, uint256 treasuryValue) {
        // Get APIARY price from TWAP oracle (1 APIARY in HONEY, 18 decimals)
        // Note: consult() is not view because it may update the oracle
        if (address(twapOracle) == address(0)) {
            // Return zeros if oracle not set - caller should handle this case
            return (0, 0);
        }

        uint256 apiaryPrice = twapOracle.consult(1e9); // Price for 1 APIARY (9 decimals)

        // Calculate market cap: totalSupply * price
        // APIARY has 9 decimals, price is in 18 decimals for 1e9 APIARY
        // So: marketCap = totalSupply * price / 1e9
        uint256 totalSupply = APIARY_TOKEN.totalSupply();
        marketCap = (totalSupply * apiaryPrice) / 1e9;

        // Calculate treasury value
        // 1. iBGT value: Get iBGT balance and convert to HONEY value
        //    For now, assume iBGT ~ HONEY for simplicity (1:1 peg assumption)
        //    In production, this should use an iBGT/HONEY oracle
        uint256 ibgtBalance = _ibgtAccounting.availableBalance + _ibgtAccounting.totalStaked;
        uint256 ibgtValue = ibgtBalance; // 1:1 assumption with HONEY

        // 2. LP token value: Use bonding calculator if set
        uint256 lpBalance = IERC20(APIARY_HONEY_LP).balanceOf(address(this));
        uint256 lpValue = 0;
        if (lpBalance > 0 && address(lpCalculator) != address(0)) {
            // Bonding calculator returns value in APIARY terms (9 decimals)
            // Convert to HONEY using current price
            uint256 lpValueInApiary = lpCalculator.valuation(APIARY_HONEY_LP, lpBalance);
            lpValue = (lpValueInApiary * apiaryPrice) / 1e9;
        }

        treasuryValue = ibgtValue + lpValue;
    }

    /*//////////////////////////////////////////////////////////////
                        SYNC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice M-03 Fix: Emitted when iBGT accounting is synced with actual balance
    event IBGTAccountingSynced(uint256 oldAvailable, uint256 newAvailable);

    /**
     * @notice M-03 Fix: Sync iBGT accounting with actual balance
     * @dev Use if accounting drifts due to direct transfers to treasury
     *      This sets availableBalance to match actual token balance
     */
    function syncIBGTAccounting() external onlyOwner {
        uint256 actualBalance = IERC20(IBGT).balanceOf(address(this));
        uint256 oldAvailable = _ibgtAccounting.availableBalance;

        // M-07 Fix: Also update totalReserves when syncing to prevent accounting mismatch
        if (actualBalance > oldAvailable) {
            uint256 surplus = actualBalance - oldAvailable;
            totalReserves[IBGT] += surplus;
        }

        // Sync available balance with actual token balance
        // Staked amounts are tracked separately by YieldManager
        _ibgtAccounting.availableBalance = actualBalance;

        emit IBGTAccountingSynced(oldAvailable, actualBalance);
    }
}
