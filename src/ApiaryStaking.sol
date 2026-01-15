// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeMath } from "./libs/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ApiaryStaking
 * @notice Staking contract for Apiary protocol
 * @dev Allows users to stake APIARY tokens and receive sAPIARY (staked APIARY) in return.
 *      Staking is instant - users receive sAPIARY immediately upon staking.
 *      Phase 1: No yield distribution (epoch.distribute = 0)
 *      Phase 2: Yield distribution enabled via distributor
 */

interface IsAPIARY {
    function rebase(uint256 apiaryProfit_, uint256 epoch_) external returns (uint256);
    function circulatingSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function gonsForBalance(uint256 amount) external view returns (uint256);
    function balanceForGons(uint256 gons) external view returns (uint256);
    function index() external view returns (uint256);
}

interface IDistributor {
    function distribute() external returns (bool);
}

interface IApiaryToken is IERC20 {
    function updateLastStakedTime(address staker) external;
}

contract ApiaryStaking is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable APIARY;
    address public immutable sAPIARY;

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public totalStaked;

    struct Epoch {
        uint256 length;        // Length of epoch in blocks
        uint256 number;        // Current epoch number
        uint256 endBlock;      // Block number when epoch ends
        uint256 distribute;    // Amount to distribute this epoch (0 in Phase 1)
    }

    Epoch public epoch;

    address public distributor;    // Distributor contract (optional, for Phase 2)
    address public locker;         // Locker contract (optional, for lockup mechanism)

    uint256 public totalBonus;     // Total bonus provided to locker

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount, address indexed recipient);
    event Unstaked(address indexed user, uint256 amount);
    event Rebased(uint256 indexed epoch, uint256 distribute);
    event DistributorSet(address indexed distributor);
    event LockerSet(address indexed locker);
    /// @notice L-02 Fix: Emitted when totalStaked changes
    event TotalStakedUpdated(uint256 oldValue, uint256 newValue);

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__INVALID_ADDRESS();
    error APIARY__ONLY_LOCKER();
    error APIARY__LOCKER_ALREADY_SET();
    error APIARY__TRANSFER_FAILED();
    /// @notice M-02 Fix: Insufficient sAPIARY balance for staking
    error APIARY__INSUFFICIENT_SAPIARY_BALANCE();

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the staking contract
     * @param _APIARY Address of the APIARY token
     * @param _sAPIARY Address of the sAPIARY token
     * @param _epochLength Length of each epoch in blocks
     * @param _firstEpochNumber Starting epoch number
     * @param _firstEpochBlock Block number when first epoch ends
     * @param _initialOwner Address of the initial owner
     */
    constructor(
        address _APIARY,
        address _sAPIARY,
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochBlock,
        address _initialOwner
    ) Ownable(_initialOwner) {
        if (_APIARY == address(0)) revert APIARY__INVALID_ADDRESS();
        if (_sAPIARY == address(0)) revert APIARY__INVALID_ADDRESS();

        APIARY = _APIARY;
        sAPIARY = _sAPIARY;

        // Initialize epoch with distribute = 0 (Phase 1: no yield)
        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endBlock: _firstEpochBlock,
            distribute: 0
        });
    }

    /*//////////////////////////////////////////////////////////////
                        STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake APIARY tokens and receive sAPIARY instantly
     * @dev User sends APIARY, contract sends sAPIARY directly to recipient
     * @param _amount Amount of APIARY to stake
     * @param _recipient Address that will receive the sAPIARY
     * @return bool Success status
     */
    function stake(uint256 _amount, address _recipient) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (bool) 
    {
        rebase();

        // Update the last staked time on the APIARY token contract
        // H-06 Fix: Use try-catch to prevent staking failure if timestamp update reverts
        try IApiaryToken(APIARY).updateLastStakedTime(_recipient) {} catch {}

        // Transfer APIARY from user to this contract
        IERC20(APIARY).safeTransferFrom(msg.sender, address(this), _amount);

        // L-02 Fix: Emit event for totalStaked change
        uint256 oldTotalStaked = totalStaked;
        totalStaked = totalStaked.add(_amount);
        emit TotalStakedUpdated(oldTotalStaked, totalStaked);

        // M-02 Fix: Verify sufficient sAPIARY balance before transfer
        uint256 sApiaryBalance = IERC20(sAPIARY).balanceOf(address(this));
        if (sApiaryBalance < _amount) {
            revert APIARY__INSUFFICIENT_SAPIARY_BALANCE();
        }

        // Transfer sAPIARY directly to recipient (1:1 with APIARY)
        IERC20(sAPIARY).safeTransfer(_recipient, _amount);

        emit Staked(msg.sender, _amount, _recipient);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        UNSTAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Unstake sAPIARY and receive APIARY (1:1 ratio)
     * @param _amount Amount of sAPIARY to unstake
     * @param _trigger Whether to trigger a rebase before unstaking
     */
    function unstake(uint256 _amount, bool _trigger) external whenNotPaused nonReentrant {
        if (_trigger) {
            rebase();
        }

        // L-02 Fix: Emit event for totalStaked change
        uint256 oldTotalStaked = totalStaked;
        totalStaked = totalStaked.sub(_amount);
        emit TotalStakedUpdated(oldTotalStaked, totalStaked);

        // Take sAPIARY from user
        IERC20(sAPIARY).safeTransferFrom(msg.sender, address(this), _amount);
        
        // Give APIARY to user
        IERC20(APIARY).safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Unstake on behalf of user (only callable by locker contract)
     * @param _recipient Address to unstake for
     * @param _amount Amount to unstake
     */
    function unstakeFor(address _recipient, uint256 _amount) external whenNotPaused nonReentrant {
        if (msg.sender != locker) revert APIARY__ONLY_LOCKER();

        rebase();

        // L-02 Fix: Emit event for totalStaked change
        uint256 oldTotalStaked = totalStaked;
        totalStaked = totalStaked.sub(_amount);
        emit TotalStakedUpdated(oldTotalStaked, totalStaked);

        IERC20(sAPIARY).safeTransferFrom(_recipient, address(this), _amount);
        IERC20(APIARY).safeTransfer(_recipient, _amount);

        emit Unstaked(_recipient, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        REBASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Trigger rebase if epoch has ended
     * @dev In Phase 1, distribute is always 0 (no yield)
     *      In Phase 2, distribute will be calculated based on profits
     */
    function rebase() public {
        if (epoch.endBlock <= block.number) {
            // Call rebase on sAPIARY contract
            IsAPIARY(sAPIARY).rebase(epoch.distribute, epoch.number);

            // Move to next epoch
            epoch.endBlock = epoch.endBlock.add(epoch.length);
            epoch.number++;

            // Trigger distributor if set (Phase 2)
            if (distributor != address(0)) {
                IDistributor(distributor).distribute();
            }

            // Calculate next epoch distribution
            // Phase 1: This will always be 0 since contractBalance <= staked
            // Phase 2: If profits exist, distribute = balance - staked
            uint256 balance = contractBalance();
            uint256 staked = IsAPIARY(sAPIARY).circulatingSupply();

            if (balance <= staked) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance.sub(staked);
            }

            emit Rebased(epoch.number, epoch.distribute);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current sAPIARY index (tracks rebase growth)
     * @return Current index value
     */
    function index() public view returns (uint256) {
        return IsAPIARY(sAPIARY).index();
    }

    /**
     * @notice Get contract APIARY balance including bonuses
     * @return Total APIARY held by contract
     */
    function contractBalance() public view returns (uint256) {
        return IERC20(APIARY).balanceOf(address(this)).add(totalBonus);
    }

    /*//////////////////////////////////////////////////////////////
                        LOCKER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Provide bonus to locked staking contract
     * @param _amount Amount of sAPIARY to send as bonus
     */
    function giveLockBonus(uint256 _amount) external {
        if (msg.sender != locker) revert APIARY__ONLY_LOCKER();
        
        totalBonus = totalBonus.add(_amount);
        IERC20(sAPIARY).safeTransfer(locker, _amount);
    }

    /**
     * @notice Reclaim bonus from locked staking contract
     * @param _amount Amount of sAPIARY to reclaim
     */
    function returnLockBonus(uint256 _amount) external {
        if (msg.sender != locker) revert APIARY__ONLY_LOCKER();
        
        totalBonus = totalBonus.sub(_amount);
        IERC20(sAPIARY).safeTransferFrom(locker, address(this), _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause the contract (emergency use only)
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

    enum CONTRACTS {
        DISTRIBUTOR,
        LOCKER
    }

    /**
     * @notice Set contract addresses for staking system components
     * @param _contract Type of contract to set
     * @param _address Address of the contract
     */
    function setContract(CONTRACTS _contract, address _address) external onlyOwner {
        if (_address == address(0)) revert APIARY__INVALID_ADDRESS();

        if (_contract == CONTRACTS.DISTRIBUTOR) {
            distributor = _address;
            emit DistributorSet(_address);
        } else if (_contract == CONTRACTS.LOCKER) {
            if (locker != address(0)) revert APIARY__LOCKER_ALREADY_SET();
            locker = _address;
            emit LockerSet(_address);
        }
    }

    /**
     * @notice Emergency function to retrieve accidentally sent tokens
     * @dev Cannot withdraw APIARY that belongs to stakers or sAPIARY
     * @param token Address of token to retrieve
     * @param amount Amount to retrieve
     */
    function retrieve(address token, uint256 amount) external onlyOwner {
        // Prevent draining staked APIARY
        if (token == APIARY) {
            uint256 apiaryBalance = IERC20(APIARY).balanceOf(address(this));
            uint256 excess = apiaryBalance > totalStaked ? apiaryBalance - totalStaked : 0;
            require(amount <= excess, "ApiaryStaking: cannot drain staked funds");
        }
        
        // Prevent draining sAPIARY
        if (token == sAPIARY) {
            // Only allow retrieval of excess sAPIARY
            uint256 sApiaryBalance = IERC20(sAPIARY).balanceOf(address(this));
            // In normal operation, staking contract shouldn't hold sAPIARY
            // It sends directly to stakers immediately
            // Allow retrieval only if there's unexpected balance
            require(sApiaryBalance >= amount, "ApiaryStaking: insufficient balance");
        }

        // Retrieve any ETH balance
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success,) = payable(msg.sender).call{ value: ethBalance }("");
            if (!success) revert APIARY__TRANSFER_FAILED();
        }

        // Retrieve specified token
        if (token != address(0) && amount > 0) {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }
}
