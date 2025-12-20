// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { SafeMath } from "./libs/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ApiaryStaking
 * @notice Staking contract for Apiary protocol
 * @dev Allows users to stake APIARY tokens and receive sAPIARY (staked APIARY) in return.
 *      Features a warmup period before stakers can claim their sAPIARY.
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

interface IWarmup {
    function retrieve(address staker_, uint256 amount_) external;
}

interface IDistributor {
    function distribute() external returns (bool);
}

interface IApiaryToken is IERC20 {
    function updateLastStakedTime(address staker) external;
}

interface IOwnable {
    function manager() external view returns (address);
    function renounceManagement() external;
    function pushManagement(address newOwner_) external;
    function pullManagement() external;
}

contract Ownable is IOwnable {
    address internal _owner;
    address internal _newOwner;

    event OwnershipPushed(address indexed previousOwner, address indexed newOwner);
    event OwnershipPulled(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipPushed(address(0), _owner);
    }

    function manager() public view override returns (address) {
        return _owner;
    }

    modifier onlyManager() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function renounceManagement() public virtual override onlyManager {
        emit OwnershipPushed(_owner, address(0));
        _owner = address(0);
    }

    function pushManagement(address newOwner_) public virtual override onlyManager {
        require(newOwner_ != address(0), "Ownable: new owner is the zero address");
        emit OwnershipPushed(_owner, newOwner_);
        _newOwner = newOwner_;
    }

    function pullManagement() public virtual override {
        require(msg.sender == _newOwner, "Ownable: must be new owner to pull");
        emit OwnershipPulled(_owner, _newOwner);
        _owner = _newOwner;
    }
}

contract ApiaryStaking is Ownable, Pausable, ReentrancyGuard {
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
    address public warmupContract; // Warmup contract that holds sAPIARY during warmup

    uint256 public warmupPeriod;   // Number of epochs for warmup
    uint256 public totalBonus;     // Total bonus provided to locker

    /*//////////////////////////////////////////////////////////////
                        WARMUP TRACKING
    //////////////////////////////////////////////////////////////*/

    struct Claim {
        uint256 deposit;   // Amount of APIARY deposited
        uint256 gons;      // Amount of gons (internal sAPIARY accounting)
        uint256 expiry;    // Epoch when warmup expires
        bool lock;         // Prevents malicious delays (user can lock their own deposits)
    }

    mapping(address => Claim) public warmupInfo;

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount, address indexed recipient);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event Forfeited(address indexed user, uint256 amount);
    event Rebased(uint256 indexed epoch, uint256 distribute);
    event WarmupSet(uint256 warmupPeriod);
    event DistributorSet(address indexed distributor);
    event WarmupContractSet(address indexed warmupContract);
    event LockerSet(address indexed locker);

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__INVALID_ADDRESS();
    error APIARY__DEPOSITS_LOCKED();
    error APIARY__ONLY_LOCKER();
    error APIARY__WARMUP_ALREADY_SET();
    error APIARY__LOCKER_ALREADY_SET();
    error APIARY__TRANSFER_FAILED();

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
     */
    constructor(
        address _APIARY,
        address _sAPIARY,
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochBlock
    ) {
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
     * @notice Stake APIARY tokens to enter warmup period
     * @dev User sends APIARY, contract sends sAPIARY to warmup contract
     *      After warmup period, user can claim sAPIARY from warmup contract
     * @param _amount Amount of APIARY to stake
     * @param _recipient Address that will receive the sAPIARY after warmup
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
        IApiaryToken(APIARY).updateLastStakedTime(_recipient);

        // Transfer APIARY from user to this contract
        IERC20(APIARY).safeTransferFrom(msg.sender, address(this), _amount);

        Claim memory info = warmupInfo[_recipient];
        if (info.lock) revert APIARY__DEPOSITS_LOCKED();

        // Update warmup info: accumulate deposit, gons, and set expiry
        warmupInfo[_recipient] = Claim({
            deposit: info.deposit.add(_amount),
            gons: info.gons.add(IsAPIARY(sAPIARY).gonsForBalance(_amount)),
            expiry: epoch.number.add(warmupPeriod),
            lock: false
        });

        totalStaked = totalStaked.add(_amount);

        // Transfer sAPIARY to warmup contract (1:1 with APIARY initially)
        IERC20(sAPIARY).safeTransfer(warmupContract, _amount);

        emit Staked(msg.sender, _amount, _recipient);
        return true;
    }

    /**
     * @notice Claim sAPIARY from warmup after warmup period expires
     * @param _recipient Address to claim for
     */
    function claim(address _recipient) public whenNotPaused nonReentrant {
        Claim memory info = warmupInfo[_recipient];
        
        if (epoch.number >= info.expiry && info.expiry != 0) {
            delete warmupInfo[_recipient];
            
            uint256 claimAmount = IsAPIARY(sAPIARY).balanceForGons(info.gons);
            IWarmup(warmupContract).retrieve(_recipient, claimAmount);
            
            emit Claimed(_recipient, claimAmount);
        }
    }

    /**
     * @notice Forfeit sAPIARY in warmup and retrieve original APIARY deposit
     * @dev Returns the original APIARY deposit amount, even if sAPIARY value changed during warmup
     */
    function forfeit() external whenNotPaused nonReentrant {
        Claim memory info = warmupInfo[msg.sender];
        delete warmupInfo[msg.sender];

        // Retrieve sAPIARY from warmup contract back to staking contract
        IWarmup(warmupContract).retrieve(address(this), IsAPIARY(sAPIARY).balanceForGons(info.gons));
        
        // Return original APIARY deposit to user
        IERC20(APIARY).safeTransfer(msg.sender, info.deposit);

        emit Forfeited(msg.sender, info.deposit);
    }

    /**
     * @notice Toggle deposit lock to prevent new deposits (protection from malicious activity)
     * @dev Users can lock their own deposits to prevent someone else from adding to their warmup
     */
    function toggleDepositLock() external whenNotPaused {
        warmupInfo[msg.sender].lock = !warmupInfo[msg.sender].lock;
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

        totalStaked = totalStaked.sub(_amount);

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

        totalStaked = totalStaked.sub(_amount);

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
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyManager {
        _unpause();
    }

    enum CONTRACTS {
        DISTRIBUTOR,
        WARMUP,
        LOCKER
    }

    /**
     * @notice Set contract addresses for staking system components
     * @param _contract Type of contract to set
     * @param _address Address of the contract
     */
    function setContract(CONTRACTS _contract, address _address) external onlyManager {
        if (_address == address(0)) revert APIARY__INVALID_ADDRESS();

        if (_contract == CONTRACTS.DISTRIBUTOR) {
            distributor = _address;
            emit DistributorSet(_address);
        } else if (_contract == CONTRACTS.WARMUP) {
            if (warmupContract != address(0)) revert APIARY__WARMUP_ALREADY_SET();
            warmupContract = _address;
            emit WarmupContractSet(_address);
        } else if (_contract == CONTRACTS.LOCKER) {
            if (locker != address(0)) revert APIARY__LOCKER_ALREADY_SET();
            locker = _address;
            emit LockerSet(_address);
        }
    }

    /**
     * @notice Set warmup period for new stakers
     * @param _warmupPeriod Number of epochs for warmup
     */
    function setWarmup(uint256 _warmupPeriod) external onlyManager {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }

    /**
     * @notice Emergency function to retrieve tokens from contract
     * @param token Address of token to retrieve
     * @param amount Amount to retrieve
     */
    function retrieve(address token, uint256 amount) external onlyManager {
        // Retrieve any ETH balance
        uint256 balance = address(this).balance;
        if (balance != 0) {
            (bool success,) = payable(msg.sender).call{ value: balance }("");
            if (!success) revert APIARY__TRANSFER_FAILED();
        }

        // Retrieve specified token
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
