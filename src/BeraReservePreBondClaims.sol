// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { SafeCast } from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IBeraReserveToken } from "./interfaces/IBeraReserveToken.sol";
import { IBeraReservePreSaleBond } from "./interfaces/IBeraReservePreSaleBond.sol";
import { InvestorBondInfo } from "./types/BeraReserveTypes.sol";
import { IBeraReservePreBondClaims } from "./interfaces/IBeraReservePreBondClaims.sol";

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
contract BeraReservePreBondClaims is IBeraReservePreBondClaims, Ownable2Step, Pausable {
    using Math for uint256;
    using Math for uint128;
    using SafeERC20 for IBeraReserveToken;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant PRE_BOND_SALE_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint48 public constant PRE_BOND_SALE_VESTING_DURATION = 5 days;
    uint256 public constant PRECISION_BRR = 1e9;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IBeraReserveToken public brrToken;
    IBeraReservePreSaleBond public preBondSaleContract;

    uint48 public tgeStartTime;
    bool public tgeStarted;

    mapping(address user => bool claimed) public purchaseAccounted;

    mapping(address userAddress => InvestorBondInfo userInfo) private _investorAllocations;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TotalBRRMinted(uint256 indexed amount);
    event BRRUnlocked(address indexed user, uint256 indexed amount);
    event TgeStarted(bool indexed _tgeStarted);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error BERA_RESERVE__INVALID_ADDRESS();
    error BERA_RESERVE__INVALID_AMOUNT();
    error BERA_RESERVE__NO_VESTING_SCHEDULE_FOUND();
    error BERA_RESERVE__NO_BRR_TO_UNLOCK();
    error BERA_RESERVE__INVALID_BALANCE();
    error BRR_TRANSFER_FAILED();
    error BERA_RESERVE__TGE_ALREADY_STARTED();
    error BERA_RESERVE__NATIVE_TRANSFER_FAILED();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _brr, address _admin, address _preBondPurchase) Ownable(_admin) {
        if (_brr == address(0) || _admin == address(0) || _preBondPurchase == address(0)) {
            revert BERA_RESERVE__INVALID_ADDRESS();
        }

        brrToken = IBeraReserveToken(_brr);
        preBondSaleContract = IBeraReservePreSaleBond(_preBondPurchase);
    }

    function mintBRR() external override onlyOwner {
        brrToken.mint(address(this), PRE_BOND_SALE_TOTAL_BRR_AMOUNT);

        emit TotalBRRMinted(PRE_BOND_SALE_TOTAL_BRR_AMOUNT);
    }

    function setTgeStartTime() external override onlyOwner {
        if (tgeStarted) revert BERA_RESERVE__TGE_ALREADY_STARTED();

        tgeStartTime = uint48(block.timestamp);
        tgeStarted = true;

        emit TgeStarted(tgeStarted);
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
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
        if (!purchaseAccounted[msg.sender]) {
            InvestorBondInfo memory investorBonds = preBondSaleContract.investorAllocations(msg.sender);
            if (investorBonds.totalAmount != 0) {
                purchaseAccounted[msg.sender] = true;
                _investorAllocations[msg.sender].totalAmount =
                    uint128(uint256(investorBonds.totalAmount).mulDiv(1, 5, Math.Rounding.Floor));
                _investorAllocations[msg.sender].unlockedAmount = investorBonds.unlockedAmount;
                _investorAllocations[msg.sender].duration = investorBonds.duration;
            }
        }

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

    /**
     * @notice Calculates the amount of BRR tokens that can be unlocked for an investor based on their vesting schedule.
     * @dev The function determines the amount of BRR tokens that can be unlocked based on the elapsed time.
     * @param user The address of the investor.
     * @return unlocked The amount of BRR tokens that can be unlocked for the investor at the current time.
     */
    function unlockedAmount(address user) public view override returns (uint256 unlocked) {
        InvestorBondInfo memory investorBonds = _investorAllocations[user];
        if (investorBonds.totalAmount == 0) {
            investorBonds = preBondSaleContract.investorAllocations(user);
            investorBonds.totalAmount = uint128(uint256(investorBonds.totalAmount).mulDiv(1, 5, Math.Rounding.Floor));
        }

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
        if (investorBonds.totalAmount == 0) {
            investorBonds = preBondSaleContract.investorAllocations(user);
            investorBonds.totalAmount = uint128(uint256(investorBonds.totalAmount).mulDiv(1, 5, Math.Rounding.Floor));
        }

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
            (bool success,) = payable(address(msg.sender)).call{ value: address(this).balance }("");
            if (!success) {
                revert BERA_RESERVE__NATIVE_TRANSFER_FAILED();
            }
        }

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function investorAllocations(address user) external view override returns (InvestorBondInfo memory allocation) {
        allocation = _investorAllocations[user];

        if (allocation.totalAmount == 0) {
            allocation = preBondSaleContract.investorAllocations(user);
            allocation.totalAmount = uint128(uint256(allocation.totalAmount).mulDiv(1, 5, Math.Rounding.Floor));
        }
    }
}
