// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IBeraReserveFeeDistributor {
    function updateAllocations() external;

    function allocateTeam() external returns (uint256);

    function allocatePOL() external returns (uint256);

    function allocateTreasury() external returns (uint256);

    function allocateToAll() external;

    function updateAddresses(address _treasury, address _pol, address _team) external;

    function updateShares(uint16 _teamShare, uint16 _polShare, uint16 _treasuryShare) external;

    function getShareDebt(address _contract) external view returns (int256);

    function getContractShares() external view returns (uint16, uint16, uint16);

    function getContractAddresses() external view returns (address, address, address);

    function getLastBalance() external view returns (uint256);

    function getAccumulatedBeraReserveTokenPerContract() external view returns (uint256);

    function getLastUpdatedTimestamp() external view returns (uint48);
}
