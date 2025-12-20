// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IApiaryTreasury
 * @notice Interface for the Apiary Treasury contract
 * @dev Manages protocol reserves with iBGT as primary reserve token
 */
interface IApiaryTreasury {
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Tracks iBGT allocation and staking status
     */
    struct IBGTAccounting {
        uint256 totalDeposited;     // Total iBGT deposited via bonds
        uint256 totalStaked;        // Total iBGT currently staked on Infrared
        uint256 totalReturned;      // Total iBGT + rewards returned from staking
        uint256 availableBalance;   // iBGT available in treasury (not staked)
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount);
    event ReservesRepaid(address indexed token, uint256 amount);
    event IBGTPulledForStaking(uint256 amount, address indexed yieldManager);
    event IBGTReturnedFromStaking(uint256 amount, uint256 rewards);
    event ReservesManagerSet(address indexed manager);
    event YieldManagerSet(address indexed yieldManager);
    event ReserveDepositorSet(address indexed depositor, bool status);
    event LiquidityDepositorSet(address indexed depositor, bool status);
    event ReserveTokenSet(address indexed token, bool status);
    event LiquidityTokenSet(address indexed token, bool status);

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit reserve or liquidity tokens in exchange for APIARY
     * @param _amount Amount of tokens to deposit
     * @param _token Address of token being deposited
     * @param value Amount of APIARY to mint
     * @return Amount of APIARY minted
     */
    function deposit(uint256 _amount, address _token, uint256 value) external returns (uint256);

    /*//////////////////////////////////////////////////////////////
                    RESERVE MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Borrow reserves (only reserves manager)
     * @param _amount Amount to borrow
     * @param _token Token to borrow
     */
    function borrowReserves(uint256 _amount, address _token) external;

    /**
     * @notice Repay borrowed reserves
     * @param _amount Amount to repay
     * @param _token Token to repay
     */
    function repayReserves(uint256 _amount, address _token) external;

    /*//////////////////////////////////////////////////////////////
                    YIELD MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Pull iBGT from treasury for staking on Infrared
     * @param _amount Amount of iBGT to pull
     */
    function pullIBGTForStaking(uint256 _amount) external;

    /**
     * @notice Return iBGT and rewards from staking to treasury
     * @param _amount Total amount being returned (principal + rewards)
     * @param _principal Amount of original iBGT staked
     */
    function returnIBGTFromStaking(uint256 _amount, uint256 _principal) external;

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setReservesManager(address _manager) external;
    function setYieldManager(address _yieldManager) external;
    function setReserveDepositor(address _depositor, bool _status) external;
    function setLiquidityDepositor(address _depositor, bool _status) external;
    function setReserveToken(address _token, bool _status) external;
    function setLiquidityToken(address _token, bool _status) external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function isReserveToken(address token) external view returns (bool);
    function isLiquidityToken(address token) external view returns (bool);
    function getIBGTAccounting() external view returns (IBGTAccounting memory);
    function totalReserves(address token) external view returns (uint256);
    function totalBorrowed(address token) external view returns (uint256);
}
