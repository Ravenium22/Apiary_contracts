// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { MerkleProof } from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import { SafeCast } from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IBeraReserveToken } from "./interfaces/IBeraReserveToken.sol";
import { IBeraReservePreSaleBond } from "./interfaces/IBeraReservePreSaleBond.sol";
import { PreSaleBondState, InvestorBondInfo } from "./types/BeraReserveTypes.sol";
/**
 * @author 0xm00k
 *
 * **PreSaleBond Vesting Schedule**
 * ----------------------------------
 * - **Day 0**: Linear release begins
 * - **Day 5**: Fully vested
 *
 * **Pre-Bond Details:**
 * - 5% of the initial BRR supply will be allocated to pre-bonds for whitelisted wallets.
 * - Maximum allocation per wallet: $500.(2500 BRR per token price $0.20)
 * - No discount on tokens received; buyers purchase at the starting market cap.
 * - Tokens will linearly vest over 5 days, similar to a standard bond.
 * - Any unsold pre-bond tokens will be burned once the protocol is live.
 *
 * Debasing Protection:
 * - Not required for pre-bonds since they function like normal bonds.
 * - Will only apply to team tokens, marketing tokens, and seed round tokens.
 *
 */

contract BeraReservePreSaleBond is IBeraReservePreSaleBond, Ownable2Step, Pausable {
    using Math for uint256;
    using Math for uint128;
    using SafeERC20 for IBeraReserveToken;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant PRE_BOND_SALE_TOTAL_BRR_AMOUNT = 50_000e9; // 50,000 BRR (5% of total supply)
    uint48 public constant PRE_BOND_SALE_VESTING_DURATION = 5 days;
    uint256 public constant PRECISION_BRR = 1e9;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IBeraReserveToken public brrToken;
    IERC20 public honey;

    address public protocolMultisig;
    PreSaleBondState public currentPreSaleBondState;
    bytes32 public merkleRoot;
    uint128 public totalBondsSold;
    uint128 public tokenPrice;
    uint128 public totalHoneyRaised;
    uint128 public bondPurchaseLimit;
    uint48 public tgeStartTime;
    bool public tgeStarted;
    bool public isWhitelistEnabled;

    mapping(address userAddress => InvestorBondInfo userInfo) private _investorAllocations;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BRRTokensPurchased(address indexed user, uint128 indexed amount, uint128 indexed honeyAmount);
    event PreSaleBondStarted(PreSaleBondState indexed state);
    event PreSaleBondEnded(PreSaleBondState indexed state);
    event TotalBRRMinted(uint256 indexed amount);
    event TokenPriceSet(uint128 indexed price);
    event BRRUnlocked(address indexed user, uint256 indexed amount);
    event ProtocolMultisigSet(address indexed multisig);
    event MerkleRootSet(bytes32 indexed _merkleRoot);
    event TgeStarted(bool indexed _tgeStarted);
    event BondPurchaseLimitSet(uint128 indexed _bondPurchaseLimit);
    event WhitelistEnabled(bool indexed _whitelistEnabled);
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error BERA_RESERVE__PRE_BOND_SALE_NOT_LIVE();
    error BERA_RESERVE__INVALID_ADDRESS();
    error BERA_RESERVE__MERKLE_ALREADY_SET();
    error BERA_RESERVE__INVALID_MERKLE_ROOT();
    error BERA_RESERVE__INVALID_AMOUNT();
    error BERA_RESERVE__NO_VESTING_SCHEDULE_FOUND();
    error BERA_RESERVE__NO_BRR_TO_UNLOCK();
    error BERA_RESERVE__BRR_SOLD_OUT();
    error BERA_RESERVE__INVALID_BALANCE();
    error BERA_RESERVE__INVALID_PROOF();
    error BRR_TRANSFER_FAILED();
    error BERA_RESERVE__PRE_BOND_SALE__MAX_BOND();
    error BERA_RESERVE__TGE_ALREADY_STARTED();
    error BERA_RESERVE__INVALID_BOND_PURCHASE_LIMIT();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _honey, address _protocolMultisig, address _admin, bytes32 _merkleRoot) Ownable(_admin) {
        if (_honey == address(0) || _protocolMultisig == address(0)) {
            revert BERA_RESERVE__INVALID_ADDRESS();
        }

        if (_merkleRoot == bytes32(0)) revert BERA_RESERVE__INVALID_MERKLE_ROOT();

        honey = IERC20(_honey);

        merkleRoot = _merkleRoot;

        protocolMultisig = _protocolMultisig;

        /**
         * @dev
         * bondPurchaseLimit = 2_500e9;
         * if maxPerWalletValue is $500
         * and token price is $0.20
         */
        bondPurchaseLimit = 2_500e9;

        tokenPrice = 2e17; //$0.20

        isWhitelistEnabled = true;
    }

    /**
     * @notice Allows a user to purchase BRR tokens using honey.
     * @dev The function checks that the PreSaleBond is live and validates the amount of honey sent.
     * @param honeyAmount The amount of honey the user wants to spend on purchasing BRR tokens.
     *
     * Requirements:
     * - The PreSaleBond state must be `Live`.
     * - There must be available BRR tokens for sale.
     * - The user's total allocation must not exceed the maximum allowed per wallet.
     *
     * Example:
     * - If the user has 100 honey and the token price is 1 honey per 1 BRR token, they will receive 100 BRR tokens.
     * - If the user tries to purchase more BRR tokens than available, they will receive the maximum available BRR
     *   tokens and a refund for the remaining honey.
     */
    function purchaseBRR(uint256 honeyAmount, bytes32[] calldata merkleProof) external override whenNotPaused {
        if (currentPreSaleBondState != PreSaleBondState.Live) revert BERA_RESERVE__PRE_BOND_SALE_NOT_LIVE();

        if (_investorAllocations[msg.sender].totalAmount == bondPurchaseLimit) {
            revert BERA_RESERVE__PRE_BOND_SALE__MAX_BOND();
        }

        if (isWhitelistEnabled) {
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
            if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
                revert BERA_RESERVE__INVALID_PROOF();
            }
        }

        uint256 brrAvailable = bRRTokensAvailable();

        uint256 honeyToRefund;

        if (brrAvailable == 0) revert BERA_RESERVE__BRR_SOLD_OUT();

        honey.safeTransferFrom(msg.sender, address(this), honeyAmount);

        //calculate amount of brr tokens bought.
        uint256 brrPurchaseAmount = honeyAmount.mulDiv(PRECISION_BRR, tokenPrice);

        if (_investorAllocations[msg.sender].totalAmount != 0) {
            unlockBRR();
        }

        if (brrPurchaseAmount >= brrAvailable) {
            brrPurchaseAmount = brrAvailable;

            uint256 valueOfBrrTokensAvailable = brrPurchaseAmount.mulDiv(tokenPrice, PRECISION_BRR, Math.Rounding.Ceil);

            honeyToRefund = honeyAmount - valueOfBrrTokensAvailable;
        }

        if (_investorAllocations[msg.sender].totalAmount + brrPurchaseAmount > bondPurchaseLimit) {
            brrPurchaseAmount = bondPurchaseLimit - _investorAllocations[msg.sender].totalAmount;

            honeyToRefund = honeyAmount - (brrPurchaseAmount.mulDiv(tokenPrice, PRECISION_BRR, Math.Rounding.Floor));
        }

        honeyAmount -= honeyToRefund;

        if (honeyToRefund != 0) honey.safeTransfer(msg.sender, honeyToRefund);

        if (_investorAllocations[msg.sender].totalAmount == 0) {
            _investorAllocations[msg.sender].duration = PRE_BOND_SALE_VESTING_DURATION;
        }

        _investorAllocations[msg.sender].totalAmount += SafeCast.toUint128(brrPurchaseAmount);

        totalBondsSold += uint128(brrPurchaseAmount);
        totalHoneyRaised += uint128(honeyAmount);

        honey.safeTransfer(protocolMultisig, honeyAmount);

        emit BRRTokensPurchased(msg.sender, uint128(brrPurchaseAmount), uint128(honeyAmount));
    }

    function mintBRR() external override onlyOwner {
        brrToken.mint(address(this), totalBondsSold);

        emit TotalBRRMinted(totalBondsSold);
    }

    /**
     * @dev Start the pre-sale
     * @notice This function can only be called by the owner
     */
    function startPreSaleBond() external override onlyOwner {
        currentPreSaleBondState = PreSaleBondState.Live;
        emit PreSaleBondStarted(currentPreSaleBondState);
    }

    function setTgeStartTime() external override onlyOwner {
        if (tgeStarted) revert BERA_RESERVE__TGE_ALREADY_STARTED();

        tgeStartTime = uint48(block.timestamp);
        tgeStarted = true;

        emit TgeStarted(tgeStarted);
    }

    function setWhitelistEnabled(bool _whitelistEnabled) external override onlyOwner {
        isWhitelistEnabled = _whitelistEnabled;

        emit WhitelistEnabled(_whitelistEnabled);
    }

    function setBRRToken(address _brrToken) external override onlyOwner {
        if (_brrToken == address(0)) revert BERA_RESERVE__INVALID_ADDRESS();

        brrToken = IBeraReserveToken(_brrToken);
    }

    function setBondPurchaseLimit(uint128 _bondPurchaseLimit) external override onlyOwner {
        if (_bondPurchaseLimit == 0) revert BERA_RESERVE__INVALID_AMOUNT();

        bondPurchaseLimit = _bondPurchaseLimit;

        emit BondPurchaseLimitSet(_bondPurchaseLimit);
    }

    /**
     * @notice Ends the PreSaleBond and burns any remaining BRR tokens.
     * @dev This function can only be called by the owner. It updates the state of the PreSaleBond to `Ended`,
     * burns the remaining BRR tokens in the contract, and emits an event indicating the end of the PreSaleBond.
     *
     * Example:
     * - The owner calls this function to conclude the PreSaleBond, ensuring that no further purchases can be made and
     * that any unsold BRR tokens are burned.
     */
    function endPreSaleBond() external override onlyOwner {
        currentPreSaleBondState = PreSaleBondState.Ended;

        emit PreSaleBondEnded(currentPreSaleBondState);
    }

    function setProtocolMultisig(address _protocolMultisig) external override onlyOwner {
        if (_protocolMultisig == address(0)) {
            revert BERA_RESERVE__INVALID_ADDRESS();
        }

        protocolMultisig = _protocolMultisig;

        emit ProtocolMultisigSet(_protocolMultisig);
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    function setTokenPrice(uint128 _price) external override onlyOwner {
        if (_price == 0) revert BERA_RESERVE__INVALID_AMOUNT();

        tokenPrice = _price;

        emit TokenPriceSet(_price);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external override onlyOwner {
        if (_merkleRoot == bytes32(0)) revert BERA_RESERVE__INVALID_MERKLE_ROOT();

        merkleRoot = _merkleRoot;

        emit MerkleRootSet(_merkleRoot);
    }

    /**
     * @notice Unlocks and transfers vested BRR tokens to the user.
     * @dev The function checks if the user has any vested BRR tokens and calculates the amount of BRR tokens
     * that can be unlocked based on the vesting schedule. Unlocks fully after 5 days.
     *
     * Requirements:
     * - The user must have an existing vesting schedule.
     * - There must be BRR tokens available for the user to unlock.
     *
     * Example:
     * - If a user has vested BRR tokens available according to their vesting schedule,
     * this function will transfer the unlockable BRR tokens to the user.
     */
    function unlockBRR() public override whenNotPaused {
        InvestorBondInfo storage investorInfo = _investorAllocations[msg.sender];

        if (investorInfo.totalAmount == 0) {
            revert BERA_RESERVE__NO_VESTING_SCHEDULE_FOUND();
        }

        uint256 releasableBRR = unlockedAmount(msg.sender);
        if (releasableBRR == 0) {
            return;
        }

        investorInfo.unlockedAmount += SafeCast.toUint128(releasableBRR);

        brrToken.safeTransfer(msg.sender, releasableBRR);

        emit BRRUnlocked(msg.sender, releasableBRR);
    }

    function bRRTokensAvailable() public view override returns (uint256) {
        return PRE_BOND_SALE_TOTAL_BRR_AMOUNT - totalBondsSold;
    }

    /**
     * @notice Calculates the amount of BRR tokens that can be unlocked for an investor based on their vesting schedule.
     * @dev The function determines the amount of BRR tokens that can be unlocked based on the elapsed time.
     * @param user The address of the investor.
     * @return unlocked The amount of BRR tokens that can be unlocked for the investor at the current time.
     */
    function unlockedAmount(address user) public view override returns (uint256 unlocked) {
        InvestorBondInfo memory investorBonds = _investorAllocations[user];

        if (investorBonds.totalAmount == 0) {
            return 0;
        }

        uint256 vested = vestedAmount(user);
        unlocked = vested - investorBonds.unlockedAmount;
    }

    /**
     * @notice Calculates the total amount of BRR tokens vested for an investor based on their vesting schedule.
     * @dev The function determines the vested amount of BRR tokens based on the elapsed time.
     * @param user The address of the investor.
     * @return vested The total amount of BRR tokens vested for the investor at the current time.
     * Example: start time is TGE start time and end time is TGE start time + 5 days.
     * If the investor has 100 BRR tokens and the vesting duration is 5 days, the investor will receive 100 BRR tokens.
     */
    function vestedAmount(address user) public view override returns (uint256) {
        InvestorBondInfo memory investorBonds = _investorAllocations[user];

        if (tgeStartTime == 0) {
            return 0;
        } else if (block.timestamp >= tgeStartTime + PRE_BOND_SALE_VESTING_DURATION) {
            return investorBonds.totalAmount;
        } else {
            uint256 durationPassed = block.timestamp - tgeStartTime;

            uint256 totalVested = uint256(investorBonds.totalAmount).mulDiv(
                durationPassed, PRE_BOND_SALE_VESTING_DURATION, Math.Rounding.Floor
            );

            return totalVested;
        }
    }

    function clawBack(address token, uint256 amount) external onlyOwner {
        if (address(this).balance != 0) {
            //! use low level call
            payable(address(msg.sender)).transfer(address(this).balance);
        }

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function investorAllocations(address user) external view override returns (InvestorBondInfo memory) {
        return _investorAllocations[user];
    }
}
