// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IBeraReserveStaking {
    function stake(uint256 _amount, address _recipient) external returns (bool);

    function unstake(uint256 _amount, bool _trigger) external;

    function unstakeFor(address _recipient, uint256 _amount) external;

    function claim(address _recipient) external;
}
