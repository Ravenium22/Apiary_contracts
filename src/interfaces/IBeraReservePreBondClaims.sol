// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { InvestorBondInfo } from "../types/BeraReserveTypes.sol";

interface IBeraReservePreBondClaims {
    function mintBRR() external;

    function setTgeStartTime() external;

    function pause() external;

    function unpause() external;

    function unlockBRR() external;

    function unlockedAmount(address user) external view returns (uint256 unlocked);

    function vestedAmount(address user) external view returns (uint256);

    function clawBack(address token, uint256 amount) external;

    function investorAllocations(address user) external view returns (InvestorBondInfo memory allocation);
}
