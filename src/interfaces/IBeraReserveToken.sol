// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBeraReserveToken is IERC20 {
    function decimals() external view returns (uint8);

    function allocationLimits(address minter) external view returns (uint256);

    function mint(address account_, uint256 amount_) external;

    function burn(uint256 amount_) external;

    function burnFrom(address account_, uint256 amount_) external;
}
