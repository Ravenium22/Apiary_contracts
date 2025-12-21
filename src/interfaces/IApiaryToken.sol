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

    /// @notice Emitted when a minter's initial allocation is set
    event MinterAllocationSet(address indexed minter, uint256 indexed maxNumberOfTokens);
    
    /// @notice Emitted when a minter's allocation is increased
    event MinterAllocationIncreased(address indexed minter, uint256 indexed additionalTokens);

    /*//////////////////////////////////////////////////////////////
                            MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint tokens to recipient
     * @param account_ Address to receive tokens
     * @param amount_ Amount to mint
     * @dev Caller must have MINTER_ROLE and sufficient allocation
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
     * @notice Get remaining allocation limit for an address
     * @param minter Address to check
     * @return Remaining mintable amount
     */
    function allocationLimits(address minter) external view returns (uint256);

    /**
     * @notice Get total amount ever minted across all minters
     * @return Total minted supply (historical, doesn't decrease on burn)
     */
    function totalMintedSupply() external view returns (uint256);

    /**
     * @notice Get last stake timestamp for a user
     * @param user Address to check
     * @return Timestamp of last stake
     */
    function lastTimeStaked(address user) external view returns (uint48);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set initial allocation limit for a new minter
     * @param minter Address to set allocation for
     * @param maxNumberOfTokens Maximum amount that can be minted
     * @dev Can only be called once per minter (when allocation is 0)
     *      Automatically grants MINTER_ROLE
     */
    function setAllocationLimit(address minter, uint256 maxNumberOfTokens) external;

    /**
     * @notice Increase allocation limit for existing minter
     * @param minter Address to increase allocation for
     * @param additionalTokens Amount to add to current allocation
     * @dev Minter must already have MINTER_ROLE
     */
    function increaseAllocationLimit(address minter, uint256 additionalTokens) external;

    /**
     * @notice Update last staked timestamp for a user
     * @param _staker Address of the staker
     * @dev Only callable by staking contract
     */
    function updateLastStakedTime(address _staker) external;
}
