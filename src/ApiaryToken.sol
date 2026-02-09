// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ERC20Permit } from "./libs/ERC20Permit.sol";
import { ERC20 } from "./libs/ERC20.sol";
import { VaultOwned } from "./VaultOwned.sol";

contract ApiaryToken is ERC20Permit, VaultOwned, AccessControl {
    /**
     * Apiary Tokenomics Overview:
     *
     * - **Token Symbol**: APIARY
     * - **Decimals**: 9
     * - **Supply Model**: Uncapped, controlled by per-minter allocation limits
     *
     * **Initial Allocations:**
     * - **Pre-Bonds** (55%) - 110,000 APIARY
     * - **Team** (15%) - 30,000 APIARY
     * - **Bullas Booga** (15%) - 30,000 APIARY
     * - **Liquidity** (10%) - 20,000 APIARY
     * - **Kodiak** (5%) - 10,000 APIARY
     *
     * **Supply Control:**
     * - No global cap - token is inflationary via bonds, deflationary via burns
     * - Each minter contract has allocation limit set by admin
     * - Admin can increase allocations as needed for ongoing bond sales
     * - Burned tokens are permanently removed from circulation
     */

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Initial allocation constants (for reference - actual limits set via setAllocationLimit)
    uint256 internal constant PRE_BONDS_ALLOCATION = 110_000e9; // 55%
    uint256 internal constant TEAM_ALLOCATION = 30_000e9; // 15%
    uint256 internal constant BULLAS_BOOGA_ALLOCATION = 30_000e9; // 15%
    uint256 internal constant LIQUIDITY_ALLOCATION = 20_000e9; // 10%
    uint256 internal constant KODIAK_ALLOCATION = 10_000e9; // 5%
    uint256 internal constant INITIAL_SUPPLY = 200_000e9; // 200,000 APIARY with 9 decimals

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Total APIARY tokens ever minted (does not decrease on burn). Used for analytics.
    uint256 public totalMintedSupply;
    
    /// @notice Tracks last stake time per user. Updated by staking contract, used for protocol analytics.
    mapping(address user => uint48 timestamp) public lastTimeStaked;
    
    /// @notice Remaining mint allocation for each minter address
    mapping(address user => uint256 amount) public allocationLimits;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event MinterAllocationSet(address indexed minter, uint256 indexed maxNumberOfTokens);
    event MinterAllocationIncreased(address indexed minter, uint256 indexed additionalTokens);
    event InitialSupplyMinted(address indexed recipient, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error APIARY__INVALID_ADDRESS();
    error APIARY__TRANSFER_AMOUNT_EXCEEDS_BALANCE();
    error APIARY__ALLOCATION_LIMIT_ALREADY_SET();
    error APIARY__MAX_MINT_ALLOC_EXCEEDED();
    error APIARY__BURN_AMOUNT_EXCEEDS_ALLOWANCE();
    error APIARY__NOT_A_MINTER();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address protocolAdmin) ERC20("Apiary", "APIARY", 9) VaultOwned(protocolAdmin) {
        if (protocolAdmin == address(0)) {
            revert APIARY__INVALID_ADDRESS();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, protocolAdmin);

        // Mint initial 200k supply to deployer (msg.sender)
        _mint(msg.sender, INITIAL_SUPPLY);
        totalMintedSupply = INITIAL_SUPPLY;

        emit InitialSupplyMinted(msg.sender, INITIAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the initial allocation limit for a new minter address.
     * @param minter The address that will be granted the MINTER_ROLE.
     * @param maxNumberOfTokens The maximum number of tokens this minter can mint.
     * @dev Can only be called once per minter address. Automatically grants MINTER_ROLE.
     *      Use increaseAllocationLimit() to add more tokens to an existing minter.
     */
    function setAllocationLimit(address minter, uint256 maxNumberOfTokens) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (allocationLimits[minter] != 0) {
            revert APIARY__ALLOCATION_LIMIT_ALREADY_SET();
        }
        
        // Grant the minter role to the address if it doesn't have it
        if (!hasRole(MINTER_ROLE, minter)) {
            _grantRole(MINTER_ROLE, minter);
        }

        allocationLimits[minter] = maxNumberOfTokens;

        emit MinterAllocationSet(minter, maxNumberOfTokens);
    }

    /**
     * @notice Increases the allocation limit for an existing minter.
     * @param minter The address of the minter to increase allocation for.
     * @param additionalTokens The number of additional tokens to add to the minter's allocation.
     * @dev The minter must already have MINTER_ROLE. Use setAllocationLimit() for new minters.
     */
    function increaseAllocationLimit(address minter, uint256 additionalTokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!hasRole(MINTER_ROLE, minter)) {
            revert APIARY__NOT_A_MINTER();
        }
        
        allocationLimits[minter] += additionalTokens;
        
        emit MinterAllocationIncreased(minter, additionalTokens);
    }

    /*//////////////////////////////////////////////////////////////
                          MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens to a specified account.
     * @param account_ The address of the account to receive the newly minted tokens.
     * @param amount_ The amount of tokens to be minted.
     * @dev This function checks if the caller has the `MINTER_ROLE` and if the caller's
     *      mint allocation limit will be exceeded. There is no global supply cap.
     */
    function mint(address account_, uint256 amount_) external onlyRole(MINTER_ROLE) {
        if (amount_ > allocationLimits[_msgSender()]) {
            revert APIARY__MAX_MINT_ALLOC_EXCEEDED();
        }

        allocationLimits[_msgSender()] -= amount_;
        totalMintedSupply += amount_;

        _mint(account_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                          BURNING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Burns tokens from the caller's account.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burns tokens from another account (requires allowance).
     * @param account_ The address of the account to burn tokens from.
     * @param amount_ The amount of tokens to burn.
     */
    function burnFrom(address account_, uint256 amount_) external {
        _burnFrom(account_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                          STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the last staked timestamp for a user.
     * @param _staker The address of the staker.
     * @dev Can only be called by the staking contract.
     */
    function updateLastStakedTime(address _staker) external onlyStaking {
        lastTimeStaked[_staker] = uint48(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles the internal token transfer mechanism.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     * @dev This is a clean transfer function with no fees or decay mechanisms.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (sender == address(0) || recipient == address(0)) {
            revert APIARY__INVALID_ADDRESS();
        }

        uint256 senderBalance = _balances[sender];

        if (senderBalance < amount) {
            revert APIARY__TRANSFER_AMOUNT_EXCEEDS_BALANCE();
        }

        // AUDIT-HIGH-02 Fix: Only use unchecked for the subtraction (provably safe
        // from the senderBalance >= amount check above). Recipient addition uses
        // checked arithmetic to prevent silent overflow with uncapped supply.
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /**
     * @notice Internal function to burn tokens from an account using allowance.
     * @param account_ The address to burn tokens from.
     * @param amount_ The amount of tokens to burn.
     */
    function _burnFrom(address account_, uint256 amount_) internal {
        if (allowance(account_, msg.sender) < amount_) {
            revert APIARY__BURN_AMOUNT_EXCEEDS_ALLOWANCE();
        }

        uint256 decreasedAllowance_ = allowance(account_, msg.sender) - amount_;

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }
}
