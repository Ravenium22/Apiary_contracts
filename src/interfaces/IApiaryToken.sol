// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IApiaryToken
 * @author Apiary Protocol
 * @notice Interface for the APIARY governance token
 * @dev Extends IERC20 with minting, burning, and allocation management
 */
interface IApiaryToken is IERC20 {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a minter's allocation is increased
    event AllocationIncreased(address indexed minter, uint256 additionalAmount, uint256 newTotal);

    /*//////////////////////////////////////////////////////////////
                            MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint tokens to recipient
     * @param account_ Address to receive tokens
     * @param amount_ Amount to mint
     * @dev Caller must have minting allocation
     */
    function mint(address account_, uint256 amount_) external;

    /*//////////////////////////////////////////////////////////////
                            BURNING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Burn tokens from another account (requires allowance)
     * @param account_ Address to burn tokens from
     * @param amount_ Amount to burn
     */
    function burnFrom(address account_, uint256 amount_) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get remaining minting allocation for an address
     * @param minter Address to check
     * @return Remaining mintable amount
     */
    function mintingAllocation(address minter) external view returns (uint256);

    /**
     * @notice Get allocation limit for an address
     * @param minter Address to check
     * @return Allocation limit
     */
    function allocationLimits(address minter) external view returns (uint256);

    /**
     * @notice Get total amount ever minted by an address
     * @param minter Address to check
     * @return Total amount minted
     */
    function totalMinted(address minter) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set minting allocation for an address
     * @param minter_ Address to set allocation for
     * @param amount_ Maximum amount that can be minted
     * @dev Can only be called by owner, only works if current allocation is 0
     */
    function setMintingAllocation(address minter_, uint256 amount_) external;

    /**
     * @notice Increase minting allocation for an address
     * @param minter_ Address to increase allocation for
     * @param additionalAmount_ Amount to add to current allocation
     * @dev Can only be called by owner
     */
    function increaseAllocationLimit(address minter_, uint256 additionalAmount_) external;
}
