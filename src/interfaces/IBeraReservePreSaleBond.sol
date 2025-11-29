// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { InvestorBondInfo } from "src/types/BeraReserveTypes.sol";

interface IBeraReservePreSaleBond {
    function investorAllocations(address user) external view returns (InvestorBondInfo memory);
    function purchaseBRR(uint256 usdcAmount, bytes32[] calldata merkleProof) external;

    function setTgeStartTime() external;

    function setBondPurchaseLimit(uint128 _bondPurchaseLimit) external;

    function setBRRToken(address _brrToken) external;

    function setWhitelistEnabled(bool _whitelistEnabled) external;

    function setMerkleRoot(bytes32 _merkleRoot) external;

    function mintBRR() external;

    function startPreSaleBond() external;

    function endPreSaleBond() external;

    function setProtocolMultisig(address _protocolMultisig) external;

    function unlockedAmount(address user) external view returns (uint256 unlocked);

    function pause() external;

    function unpause() external;

    function setTokenPrice(uint128 _price) external;

    function unlockBRR() external;

    function bRRTokensAvailable() external view returns (uint256);

    function vestedAmount(address user) external view returns (uint256);
}
