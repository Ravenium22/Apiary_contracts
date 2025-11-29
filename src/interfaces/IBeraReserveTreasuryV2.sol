// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IBeraReserveTreasuryV2 {
    function deposit(uint256 _amount, address _token, uint256 value) external returns (uint256);

    function borrowReserves(uint256 _amount, address _token) external;

    function repayReserves(uint256 _amount, address _token) external;

    function isReserveToken(address token) external view returns (bool);

    function isLiquidityToken(address token) external view returns (bool);

    function setReservesManager(address _manager) external;

    function setReserveDepositor(address _depositor, bool _status) external;

    function setLiquidityDepositor(address _depositor, bool _status) external;

    function setReserveToken(address _token, bool _status) external;

    function setLiquidityToken(address _token, bool _status) external;
}
