// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { VestingSchedule, MemberType } from "../types/BeraReserveTypes.sol";

interface IBeraReserveLockUp {
    function mintAndStakeBRR() external;

    function addMultipleTeamMembers(address[] calldata members, uint128[] calldata totalAmounts) external;

    function addMultipleMarketingMembers(address[] calldata members, uint128[] calldata totalAmounts) external;

    function addMultipleSeedRoundMembers(address[] calldata members, uint128[] calldata totalAmounts) external;

    function addTeamMember(address _member, uint128 totalAmount) external;

    function addMarketingMember(address _member, uint128 totalAmount) external;

    function addSeedRoundMember(address _member, uint128 totalAmount) external;

    function initiateTGEUnlock() external;

    function unlockSbrr(MemberType memberType) external;

    function getSeedRoundSchedules(address user) external view returns (VestingSchedule memory schedule);

    function getTeamSchedules(address user) external view returns (VestingSchedule memory schedule);

    function getMarketSchedules(address user) external view returns (VestingSchedule memory schedule);

    function unlockedAmount(address member, MemberType memberType) external view returns (uint256 unlocked);

    function vestedAmount(address member, MemberType memberType) external view returns (uint256);
}
