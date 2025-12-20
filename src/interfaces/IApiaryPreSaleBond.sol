// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { InvestorBondInfo } from "src/types/BeraReserveTypes.sol";

/**
 * @title IApiaryPreSaleBond
 * @notice Interface for Apiary pre-sale bond contract
 */
interface IApiaryPreSaleBond {
    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase APIARY tokens with HONEY during pre-sale
     * @param honeyAmount Amount of HONEY to spend
     * @param merkleProof Merkle proof for whitelist verification
     * @param minApiaryAmount Minimum APIARY to receive (slippage protection)
     */
    function purchaseApiary(uint256 honeyAmount, bytes32[] calldata merkleProof, uint256 minApiaryAmount) external;

    /**
     * @notice Unlock and claim vested APIARY tokens
     */
    function unlockApiary() external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint total sold APIARY to contract for distribution
     */
    function mintApiary() external;

    /**
     * @notice Start the pre-sale (NotStarted → Live)
     */
    function startPreSaleBond() external;

    /**
     * @notice End the pre-sale (Live → Ended)
     */
    function endPreSaleBond() external;

    /**
     * @notice Set TGE start time (enables vesting)
     */
    function setTgeStartTime() external;

    /**
     * @notice Set APIARY token contract address
     * @param _apiaryToken APIARY token address
     */
    function setApiaryToken(address _apiaryToken) external;

    /**
     * @notice Update per-wallet purchase limit
     * @param _bondPurchaseLimit New limit in APIARY (9 decimals)
     */
    function setBondPurchaseLimit(uint128 _bondPurchaseLimit) external;

    /**
     * @notice Update token price
     * @param _price New price in HONEY (18 decimals)
     */
    function setTokenPrice(uint128 _price) external;

    /**
     * @notice Update merkle root for whitelist
     * @param _merkleRoot New merkle root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external;

    /**
     * @notice Enable/disable whitelist requirement
     * @param _whitelistEnabled True to require whitelist
     */
    function setWhitelistEnabled(bool _whitelistEnabled) external;

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Pause the contract
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get investor allocation information
     * @param user User address
     * @return Investor bond information
     */
    function investorAllocations(address user) external view returns (InvestorBondInfo memory);

    /**
     * @notice Calculate APIARY tokens still available
     * @return Available APIARY amount
     */
    function apiaryTokensAvailable() external view returns (uint256);

    /**
     * @notice Calculate unlocked APIARY for a user
     * @param user User address
     * @return Unlocked amount
     */
    function unlockedAmount(address user) external view returns (uint256);

    /**
     * @notice Calculate total vested APIARY for a user
     * @param user User address
     * @return Vested amount
     */
    function vestedAmount(address user) external view returns (uint256);

    /**
     * @notice Verify if an address is whitelisted
     * @param user Address to verify
     * @param merkleProof Merkle proof
     * @return True if whitelisted
     */
    function isWhitelisted(address user, bytes32[] calldata merkleProof) external view returns (bool);
}
