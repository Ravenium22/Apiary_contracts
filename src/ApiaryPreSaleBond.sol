// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IApiaryToken } from "./interfaces/IApiaryToken.sol";
import { IApiaryPreSaleBond } from "./interfaces/IApiaryPreSaleBond.sol";
import { PreSaleBondState, InvestorBondInfo } from "./types/BeraReserveTypes.sol";

/**
 * @title ApiaryPreSaleBond
 * @notice Whitelisted pre-sale bond contract for Apiary protocol
 * @dev Enables early supporters to purchase APIARY at initial market cap with linear vesting
 * 
 * **Pre-Sale Details:**
 * - Total Allocation: 55% of supply = 110,000 APIARY
 * - Token Price: $0.50 per APIARY ($100k market cap / 200k total supply)
 * - Payment Token: HONEY (Berachain native stablecoin)
 * - Per-Wallet Limit: Configurable by admin (default: 500 APIARY = $125)
 * - Whitelist: Merkle proof based for partners (Plug, ApDao, YeetDat, BoogaBullas)
 * - Vesting: 5 days linear from TGE
 * 
 * **Vesting Schedule:**
 * - Day 0 (TGE): Linear release begins
 * - Day 5: Fully vested
 * 
 * **Security Features:**
 * - Merkle proof verification (cannot be bypassed)
 * - Per-wallet purchase limits
 * - Total sold cannot exceed 110,000 APIARY
 * - One-way state transitions (NotStarted → Live → Ended)
 * - Payment tokens immediately sent to treasury
 * - Pausable emergency stop
 * - Ownable2Step for admin transfer
 * 
 * **States:**
 * - NotStarted: Initial state, no purchases allowed
 * - Live: Pre-sale active, whitelisted users can purchase
 * - Ended: Pre-sale concluded, no further purchases
 * 
 * @author Apiary Protocol Team
 */
contract ApiaryPreSaleBond is IApiaryPreSaleBond, Ownable2Step, Pausable, ReentrancyGuard {
    using Math for uint256;
    using Math for uint128;
    using SafeERC20 for IApiaryToken;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Total APIARY allocated to pre-sale (55% of 200k supply)
    uint256 public constant PRE_SALE_TOTAL_APIARY_AMOUNT = 110_000e9; // 110,000 APIARY (9 decimals)

    /// @notice Vesting duration from TGE
    uint48 public constant PRE_SALE_VESTING_DURATION = 5 days;

    /// @notice APIARY token precision (9 decimals)
    uint256 public constant PRECISION_APIARY = 1e9;

    /// @notice HONEY token precision (18 decimals)
    uint256 public constant PRECISION_HONEY = 1e18;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice APIARY token contract
    IApiaryToken public apiaryToken;

    /// @notice HONEY payment token (Berachain stablecoin)
    IERC20 public honey;

    /// @notice Treasury address (receives HONEY payments)
    address public treasury;

    /// @notice Current pre-sale state
    PreSaleBondState public currentPreSaleBondState;

    /// @notice Merkle root for whitelist verification
    bytes32 public merkleRoot;

    /// @notice Total APIARY bonds sold
    uint128 public totalBondsSold;

    /// @notice Token price in HONEY (18 decimals)
    /// @dev Default: $0.50 = 0.50e18 HONEY per APIARY
    uint128 public tokenPrice;

    /// @notice Total HONEY raised from pre-sale
    uint128 public totalHoneyRaised;

    /// @notice Maximum APIARY per wallet
    /// @dev Default: 500 APIARY = $250 at $0.50/token
    uint128 public bondPurchaseLimit;

    /// @notice TGE (Token Generation Event) start timestamp
    uint48 public tgeStartTime;

    /// @notice Whether TGE has started
    bool public tgeStarted;

    /// @notice Whether whitelist is enabled
    /// @dev Can be disabled by admin if needed
    bool public isWhitelistEnabled;

    /// @notice HIGH-03 Fix: Total APIARY claimed/unlocked by all users
    /// @dev Used in clawBack() to accurately calculate unredeemed obligations
    uint128 public totalClaimedByUsers;

    /// @notice User bond information
    mapping(address userAddress => InvestorBondInfo userInfo) private _investorAllocations;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__PRE_SALE_NOT_LIVE();
    error APIARY__INVALID_ADDRESS();
    error APIARY__INVALID_MERKLE_ROOT();
    error APIARY__INVALID_AMOUNT();
    error APIARY__NO_VESTING_SCHEDULE();
    error APIARY__APIARY_SOLD_OUT();
    error APIARY__INVALID_PROOF();
    error APIARY__MAX_BOND_REACHED();
    error APIARY__TGE_ALREADY_STARTED();
    error APIARY__INVALID_STATE_TRANSITION();
    error APIARY__TGE_NOT_STARTED();
    error APIARY__SLIPPAGE_EXCEEDED();
    error APIARY__TOKEN_NOT_SET();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ApiaryPurchased(address indexed user, uint128 indexed apiaryAmount, uint128 indexed honeyAmount);
    event PreSaleBondStarted(PreSaleBondState indexed state);
    event PreSaleBondEnded(PreSaleBondState indexed state);
    event TotalApiaryMinted(uint256 indexed amount);
    event TokenPriceSet(uint128 indexed price);
    event ApiaryUnlocked(address indexed user, uint256 indexed amount);
    event TreasurySet(address indexed treasury);
    event MerkleRootSet(bytes32 indexed merkleRoot);
    event TgeStarted(uint48 indexed tgeStartTime);
    event BondPurchaseLimitSet(uint128 indexed bondPurchaseLimit);
    event WhitelistEnabled(bool indexed isEnabled);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize pre-sale bond contract
     * @param _honey HONEY token address (payment token)
     * @param _treasury Treasury address (receives payments)
     * @param _admin Admin address (owner)
     * @param _merkleRoot Initial merkle root for whitelist
     */
    constructor(
        address _honey,
        address _treasury,
        address _admin,
        bytes32 _merkleRoot
    ) Ownable(_admin) {
        if (_honey == address(0) || _treasury == address(0)) {
            revert APIARY__INVALID_ADDRESS();
        }
        if (_merkleRoot == bytes32(0)) {
            revert APIARY__INVALID_MERKLE_ROOT();
        }

        honey = IERC20(_honey);
        treasury = _treasury;
        merkleRoot = _merkleRoot;

        // Default values
        // $0.50 per APIARY = 0.50e18 HONEY (assuming 1 HONEY = $1)
        tokenPrice = 50e16; // 0.50 HONEY

        // Default limit: 500 APIARY = $250 at $0.50/token
        bondPurchaseLimit = 500e9;

        // Whitelist enabled by default
        isWhitelistEnabled = true;

        // Start in NotStarted state
        currentPreSaleBondState = PreSaleBondState.NotStarted;
    }

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase APIARY tokens with HONEY during pre-sale
     * @dev Transfers HONEY from user to treasury and allocates APIARY for vesting
     * 
     * Flow:
     * 1. Verify pre-sale is live
     * 2. Check whitelist merkle proof (if enabled)
     * 3. Verify user hasn't exceeded purchase limit
     * 4. Calculate APIARY amount from HONEY payment
     * 5. Handle refunds if purchase exceeds available or limit
     * 6. Transfer HONEY to treasury
     * 7. Allocate APIARY for vesting
     * 
     * @param honeyAmount Amount of HONEY to spend (18 decimals)
     * @param merkleProof Merkle proof for whitelist verification
     * @param minApiaryAmount Minimum APIARY to receive (slippage protection)
     */
    function purchaseApiary(
        uint256 honeyAmount,
        bytes32[] calldata merkleProof,
        uint256 minApiaryAmount
    ) external whenNotPaused nonReentrant {
        // Check pre-sale is live
        if (currentPreSaleBondState != PreSaleBondState.Live) {
            revert APIARY__PRE_SALE_NOT_LIVE();
        }

        // Check user hasn't maxed out allocation
        if (_investorAllocations[msg.sender].totalAmount == bondPurchaseLimit) {
            revert APIARY__MAX_BOND_REACHED();
        }

        // Verify whitelist (if enabled)
        if (isWhitelistEnabled) {
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
            if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
                revert APIARY__INVALID_PROOF();
            }
        }

        // Check APIARY availability
        uint256 apiaryAvailable = apiaryTokensAvailable();
        if (apiaryAvailable == 0) {
            revert APIARY__APIARY_SOLD_OUT();
        }

        // Transfer HONEY from user
        honey.safeTransferFrom(msg.sender, address(this), honeyAmount);

        // Calculate APIARY purchase amount
        // honeyAmount (18 decimals) * PRECISION_APIARY (9 decimals) / tokenPrice (18 decimals)
        uint256 apiaryPurchaseAmount = honeyAmount.mulDiv(PRECISION_APIARY, tokenPrice);

        // Slippage protection: revert if amount below minimum
        if (apiaryPurchaseAmount < minApiaryAmount) {
            revert APIARY__SLIPPAGE_EXCEEDED();
        }

        // If user already has allocation, unlock vested tokens first
        // C-01 Fix: Call internal version to avoid nested nonReentrant
        if (_investorAllocations[msg.sender].totalAmount != 0) {
            _unlockApiaryInternal();
        }

        // LOW-04 Fix: Apply caps sequentially, calculate refund once at the end
        // Cap purchase at available APIARY
        if (apiaryPurchaseAmount > apiaryAvailable) {
            apiaryPurchaseAmount = apiaryAvailable;
        }

        // Cap purchase at user's remaining allocation
        uint256 remainingAllocation = bondPurchaseLimit - _investorAllocations[msg.sender].totalAmount;
        if (apiaryPurchaseAmount > remainingAllocation) {
            apiaryPurchaseAmount = remainingAllocation;
        }

        // Single refund calculation based on final capped amount
        uint256 actualHoneyCost = apiaryPurchaseAmount.mulDiv(tokenPrice, PRECISION_APIARY, Math.Rounding.Ceil);
        uint256 honeyToRefund = honeyAmount > actualHoneyCost ? honeyAmount - actualHoneyCost : 0;

        // Update HONEY amount after refund calculation
        honeyAmount -= honeyToRefund;

        // Refund excess HONEY if any
        if (honeyToRefund != 0) {
            honey.safeTransfer(msg.sender, honeyToRefund);
        }

        // Initialize vesting schedule if first purchase
        if (_investorAllocations[msg.sender].totalAmount == 0) {
            _investorAllocations[msg.sender].duration = PRE_SALE_VESTING_DURATION;
        }

        // Update user allocation
        _investorAllocations[msg.sender].totalAmount += SafeCast.toUint128(apiaryPurchaseAmount);

        // Update global counters
        // M-06 Fix: Use SafeCast consistently to prevent silent truncation
        totalBondsSold += SafeCast.toUint128(apiaryPurchaseAmount);
        totalHoneyRaised += SafeCast.toUint128(honeyAmount);

        // Transfer HONEY to treasury immediately
        honey.safeTransfer(treasury, honeyAmount);

        emit ApiaryPurchased(msg.sender, SafeCast.toUint128(apiaryPurchaseAmount), SafeCast.toUint128(honeyAmount));
    }

    /**
     * @notice Unlock and claim vested APIARY tokens
     * @dev Calculates vested amount and transfers to user
     * 
     * Vesting Formula:
     * - If TGE not started: 0 vested
     * - If fully vested (≥5 days): totalAmount vested
     * - Otherwise: (totalAmount × timeSinceTGE) / vestingDuration
     */
    function unlockApiary() public whenNotPaused nonReentrant {
        _unlockApiaryInternal();
    }

    /**
     * @notice Internal unlock logic (no nonReentrant modifier)
     * @dev C-01 Fix: Extracted to avoid nested nonReentrant when called from purchaseApiary()
     */
    function _unlockApiaryInternal() internal {
        // C-03 Fix: Ensure apiaryToken is set before attempting transfer
        if (address(apiaryToken) == address(0)) {
            revert APIARY__TOKEN_NOT_SET();
        }

        InvestorBondInfo storage investorInfo = _investorAllocations[msg.sender];

        if (investorInfo.totalAmount == 0) {
            revert APIARY__NO_VESTING_SCHEDULE();
        }

        uint256 releasableApiary = unlockedAmount(msg.sender);
        if (releasableApiary == 0) {
            return;
        }

        investorInfo.unlockedAmount += SafeCast.toUint128(releasableApiary);

        // HIGH-03 Fix: Track total claimed across all users for accurate clawBack protection
        totalClaimedByUsers += SafeCast.toUint128(releasableApiary);

        apiaryToken.safeTransfer(msg.sender, releasableApiary);

        emit ApiaryUnlocked(msg.sender, releasableApiary);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint total sold APIARY to contract for vesting distribution
     * @dev Called after pre-sale ends, before TGE starts
     * @dev Only mints exactly what was sold, no excess
     */
    function mintApiary() external onlyOwner {
        apiaryToken.mint(address(this), totalBondsSold);

        emit TotalApiaryMinted(totalBondsSold);
    }

    /**
     * @notice Start the pre-sale (transition to Live state)
     * @dev Can only be called from NotStarted state
     */
    function startPreSaleBond() external onlyOwner {
        if (currentPreSaleBondState != PreSaleBondState.NotStarted) {
            revert APIARY__INVALID_STATE_TRANSITION();
        }

        currentPreSaleBondState = PreSaleBondState.Live;
        emit PreSaleBondStarted(currentPreSaleBondState);
    }

    /**
     * @notice End the pre-sale (transition to Ended state)
     * @dev Can only be called from Live state
     * @dev One-way transition, cannot go back to Live
     */
    function endPreSaleBond() external onlyOwner {
        if (currentPreSaleBondState != PreSaleBondState.Live) {
            revert APIARY__INVALID_STATE_TRANSITION();
        }

        currentPreSaleBondState = PreSaleBondState.Ended;
        emit PreSaleBondEnded(currentPreSaleBondState);
    }

    /**
     * @notice Set TGE start time (enables vesting)
     * @dev Can only be called once
     */
    function setTgeStartTime() external onlyOwner {
        if (tgeStarted) {
            revert APIARY__TGE_ALREADY_STARTED();
        }

        tgeStartTime = uint48(block.timestamp);
        tgeStarted = true;

        emit TgeStarted(tgeStartTime);
    }

    /**
     * @notice Set APIARY token contract address
     * @param _apiaryToken APIARY token address
     */
    function setApiaryToken(address _apiaryToken) external onlyOwner {
        if (_apiaryToken == address(0)) {
            revert APIARY__INVALID_ADDRESS();
        }

        apiaryToken = IApiaryToken(_apiaryToken);
    }

    /**
     * @notice Update per-wallet purchase limit
     * @param _bondPurchaseLimit New limit in APIARY (9 decimals)
     */
    function setBondPurchaseLimit(uint128 _bondPurchaseLimit) external onlyOwner {
        if (_bondPurchaseLimit == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        bondPurchaseLimit = _bondPurchaseLimit;
        emit BondPurchaseLimitSet(_bondPurchaseLimit);
    }

    /**
     * @notice Update token price
     * @param _price New price in HONEY (18 decimals)
     * @dev Example: $0.50 = 50e16 (0.50 * 1e18)
     */
    function setTokenPrice(uint128 _price) external onlyOwner {
        if (_price == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        tokenPrice = _price;
        emit TokenPriceSet(_price);
    }

    /**
     * @notice Update merkle root for whitelist
     * @param _merkleRoot New merkle root
     * @dev Can update before/during pre-sale to add addresses
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (_merkleRoot == bytes32(0)) {
            revert APIARY__INVALID_MERKLE_ROOT();
        }

        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /**
     * @notice Enable/disable whitelist requirement
     * @param _whitelistEnabled True to require whitelist, false to allow public
     */
    function setWhitelistEnabled(bool _whitelistEnabled) external onlyOwner {
        isWhitelistEnabled = _whitelistEnabled;
        emit WhitelistEnabled(_whitelistEnabled);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) {
            revert APIARY__INVALID_ADDRESS();
        }

        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /**
     * @notice Pause the contract (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency token recovery
     * @dev L-04 Fix: Removed dead ETH handling code (contract has no receive/fallback)
     * @param token Token address
     * @param amount Amount to recover
     */
    function clawBack(address token, uint256 amount) external onlyOwner {
        if (token != address(0)) {
            // C-05 Fix + HIGH-03 Fix: Protect only unredeemed APIARY from being withdrawn
            // Uses actual unredeemed amount (totalBondsSold - totalClaimedByUsers)
            // instead of totalBondsSold which overstates obligations after claims
            if (token == address(apiaryToken) && address(apiaryToken) != address(0)) {
                uint256 userAllocated = totalBondsSold - totalClaimedByUsers;
                uint256 contractBalance = IERC20(token).balanceOf(address(this));
                uint256 excess = contractBalance > userAllocated ? contractBalance - userAllocated : 0;
                if (amount > excess) {
                    revert APIARY__INVALID_AMOUNT();
                }
            }
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get investor allocation information
     * @param user User address
     * @return Investor bond information struct
     */
    function investorAllocations(address user) external view returns (InvestorBondInfo memory) {
        return _investorAllocations[user];
    }

    /**
     * @notice Calculate APIARY tokens still available for purchase
     * @return Available APIARY amount
     */
    function apiaryTokensAvailable() public view returns (uint256) {
        return PRE_SALE_TOTAL_APIARY_AMOUNT - totalBondsSold;
    }

    /**
     * @notice Calculate unlocked APIARY for a user (ready to claim)
     * @param user User address
     * @return Amount of APIARY ready to unlock
     */
    function unlockedAmount(address user) public view returns (uint256) {
        InvestorBondInfo memory investorBonds = _investorAllocations[user];

        if (investorBonds.totalAmount == 0) {
            return 0;
        }

        uint256 vested = vestedAmount(user);
        return vested - investorBonds.unlockedAmount;
    }

    /**
     * @notice Calculate total vested APIARY for a user
     * @param user User address
     * @return Total vested APIARY (including already unlocked)
     * 
     * Vesting Logic:
     * - Before TGE: 0
     * - After 5 days: Full amount
     * - Between: Linear (amount × timePassed / totalDuration)
     */
    function vestedAmount(address user) public view returns (uint256) {
        InvestorBondInfo memory investorBonds = _investorAllocations[user];

        if (tgeStartTime == 0) {
            return 0;
        } else if (block.timestamp >= tgeStartTime + PRE_SALE_VESTING_DURATION) {
            return investorBonds.totalAmount;
        } else {
            uint256 durationPassed = block.timestamp - tgeStartTime;

            uint256 totalVested = uint256(investorBonds.totalAmount).mulDiv(
                durationPassed,
                PRE_SALE_VESTING_DURATION,
                Math.Rounding.Floor
            );

            return totalVested;
        }
    }

    /**
     * @notice Verify if an address is whitelisted
     * @param user Address to verify
     * @param merkleProof Merkle proof for verification
     * @return True if whitelisted or whitelist disabled
     */
    function isWhitelisted(
        address user,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        if (!isWhitelistEnabled) {
            return true;
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user))));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }
}
