// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeMath } from "./libs/SafeMath.sol";
import { ERC20 } from "./libs/ERC20.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { Counters } from "./libs/ERC20Permit.sol";

/**
 * @title sApiary - Staked Apiary Token
 * @notice This is a rebasing ERC20 token that represents staked APIARY tokens.
 * @dev Uses a gons-based accounting system to handle rebases efficiently.
 *      Balances are stored as "gons" (internal shares) and converted to token amounts using _gonsPerFragment.
 *      When rebase() is called, only _gonsPerFragment is updated - no balance transfers occur.
 */

interface IERC2612Permit {
    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    function nonces(address owner) external view returns (uint256);
}

abstract contract ERC20Permit is ERC20, IERC2612Permit {
    using Counters for Counters.Counter;

    mapping(address => Counters.Counter) private _nonces;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    bytes32 public DOMAIN_SEPARATOR;

    constructor() {
        uint256 chainID;
        assembly {
            chainID := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")), // Version
                chainID,
                address(this)
            )
        );
    }

    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
        override
    {
        require(block.timestamp <= deadline, "Permit: expired deadline");

        bytes32 hashStruct =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, _nonces[owner].current(), deadline));

        bytes32 _hash = keccak256(abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, hashStruct));

        address signer = ecrecover(_hash, v, r, s);
        require(signer != address(0) && signer == owner, "Permit: Invalid signature");

        _nonces[owner].increment();
        _approve(owner, spender, amount);
    }

    function nonces(address owner_) public view override returns (uint256) {
        return _nonces[owner_].current();
    }
}

contract sApiary is ERC20Permit, Ownable2Step {
    using SafeMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "sApiary: caller is not staking contract");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public stakingContract;
    address public initializer;

    /*//////////////////////////////////////////////////////////////
                        REBASING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Maximum value for uint256
    uint256 private constant MAX_UINT256 = ~uint256(0);
    
    // Initial supply: 5 million tokens with 9 decimals
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10 ** 9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    // This ensures _gonsPerFragment never goes below 1
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1

    /*//////////////////////////////////////////////////////////////
                        REBASING STATE
    //////////////////////////////////////////////////////////////*/

    // INDEX is stored in gons to avoid precision loss
    uint256 public INDEX;

    // Conversion rate from gons to fragments (tokens)
    // This is updated on each rebase
    uint256 private _gonsPerFragment;

    // User balances in gons (internal accounting unit)
    mapping(address => uint256) private _gonBalances;

    // Allowances are stored in token amounts, not gons
    mapping(address => mapping(address => uint256)) private _allowedValue;

    /*//////////////////////////////////////////////////////////////
                            REBASE TRACKING
    //////////////////////////////////////////////////////////////*/

    struct Rebase {
        uint256 epoch;
        uint256 rebase; // 18 decimals - percentage of rebase
        uint256 totalStakedBefore;
        uint256 totalStakedAfter;
        uint256 amountRebased;
        uint256 index;
        uint256 blockNumberOccured;
    }

    Rebase[] public rebases;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LogSupply(uint256 indexed epoch, uint256 timestamp, uint256 totalSupply);
    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
    event LogStakingContractUpdated(address stakingContract);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _initialOwner) ERC20("Staked Apiary", "sAPIARY", 9) ERC20Permit() Ownable(_initialOwner) {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the contract by setting the staking contract address.
     * @dev Can only be called once by the initializer.
     *      All initial supply is minted to the staking contract.
     * @param stakingContract_ The address of the staking contract.
     */
    function initialize(address stakingContract_) external returns (bool) {
        require(msg.sender == initializer, "sApiary: caller is not initializer");
        require(stakingContract_ != address(0), "sApiary: invalid staking contract");
        
        stakingContract = stakingContract_;
        _gonBalances[stakingContract] = TOTAL_GONS;

        emit Transfer(address(0x0), stakingContract, _totalSupply);
        emit LogStakingContractUpdated(stakingContract_);

        initializer = address(0);
        return true;
    }

    /**
     * @notice Set the initial index for the staking system.
     * @dev Can only be called once by the owner, and only before INDEX is set.
     * @param _INDEX The initial index value (in token amounts, will be converted to gons).
     */
    function setIndex(uint256 _INDEX) external onlyOwner returns (bool) {
        require(INDEX == 0, "sApiary: index already set");
        INDEX = gonsForBalance(_INDEX);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        REBASING MECHANISM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increases sAPIARY supply to increase staking balances relative to profit.
     * @dev This is the core rebasing function - it updates _gonsPerFragment to reflect the new total supply.
     *      Only callable by the staking contract.
     *      The rebase increases everyone's balance proportionally without any transfers.
     * @param profit_ The amount of profit to distribute (in token amounts).
     * @param epoch_ The current epoch number.
     * @return The new total supply after rebase.
     */
    function rebase(uint256 profit_, uint256 epoch_) public onlyStakingContract returns (uint256) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();

        if (profit_ == 0) {
            emit LogSupply(epoch_, block.timestamp, _totalSupply);
            emit LogRebase(epoch_, 0, index());
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            // Calculate proportional rebase: profit_ * totalSupply / circulatingSupply
            rebaseAmount = profit_.mul(_totalSupply).div(circulatingSupply_);
        } else {
            rebaseAmount = profit_;
        }

        // Increase total supply
        _totalSupply = _totalSupply.add(rebaseAmount);

        // Cap at MAX_SUPPLY to prevent overflow
        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        // Prevent division by zero
        require(_totalSupply > 0, "sApiary: zero supply");

        // Update the conversion rate (this is what makes balances increase)
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _storeRebase(circulatingSupply_, profit_, epoch_);

        return _totalSupply;
    }

    /**
     * @notice Store rebase data and emit events.
     * @param previousCirculating_ The circulating supply before the rebase.
     * @param profit_ The profit amount that was rebased.
     * @param epoch_ The epoch number.
     */
    function _storeRebase(uint256 previousCirculating_, uint256 profit_, uint256 epoch_) internal returns (bool) {
        // H-02 Fix: Prevent division by zero if no circulating supply
        if (previousCirculating_ == 0) {
            emit LogSupply(epoch_, block.timestamp, _totalSupply);
            emit LogRebase(epoch_, 0, index());
            return true;
        }
        
        uint256 rebasePercent = profit_.mul(1e18).div(previousCirculating_);

        rebases.push(
            Rebase({
                epoch: epoch_,
                rebase: rebasePercent, // 18 decimals
                totalStakedBefore: previousCirculating_,
                totalStakedAfter: circulatingSupply(),
                amountRebased: profit_,
                index: index(),
                blockNumberOccured: block.number
            })
        );

        emit LogSupply(epoch_, block.timestamp, _totalSupply);
        emit LogRebase(epoch_, rebasePercent, index());

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        BALANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the token balance of an account.
     * @dev Converts gons to token amount using current _gonsPerFragment.
     * @param who The address to query.
     * @return The token balance.
     */
    function balanceOf(address who) public view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    /**
     * @notice Convert a token amount to gons.
     * @param amount The token amount.
     * @return The equivalent amount in gons.
     */
    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    /**
     * @notice Convert gons to a token amount.
     * @param gons The gons amount.
     * @return The equivalent token amount.
     */
    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    /**
     * @notice Get the circulating supply (total supply minus staking contract balance).
     * @dev The staking contract holds excess sAPIARY.
     * @return The circulating supply.
     */
    function circulatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(stakingContract));
    }

    /**
     * @notice Get the current index value.
     * @dev Converts INDEX from gons to token amount.
     * @return The current index.
     */
    function index() public view returns (uint256) {
        return balanceForGons(INDEX);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer tokens to another address.
     * @dev Transfers are done in gons to maintain precision.
     * @param to The recipient address.
     * @param value The amount of tokens to transfer.
     */
    function transfer(address to, uint256 value) public override returns (bool) {
        // H-03 Fix: Calculate gons first to avoid rounding mismatch between check and transfer
        uint256 gonValue = gonsForBalance(value);
        require(_gonBalances[msg.sender] >= gonValue, "sApiary: insufficient balance");

        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another using allowance.
     * @param from The sender address.
     * @param to The recipient address.
     * @param value The amount of tokens to transfer.
     */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        // H-03 Fix: Calculate gons first to avoid rounding mismatch between check and transfer
        uint256 gonValue = gonsForBalance(value);
        require(_gonBalances[from] >= gonValue, "sApiary: insufficient balance");

        _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        
        emit Transfer(from, to, value);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the allowance of a spender for an owner.
     * @param owner_ The owner address.
     * @param spender The spender address.
     */
    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowedValue[owner_][spender];
    }

    /**
     * @notice Approve a spender to spend tokens on behalf of the caller.
     * @param spender The spender address.
     * @param value The allowance amount.
     */
    function approve(address spender, uint256 value) public override returns (bool) {
        _allowedValue[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Internal approve function (used by permit).
     * @param owner The owner address.
     * @param spender The spender address.
     * @param value The allowance amount.
     */
    function _approve(address owner, address spender, uint256 value) internal virtual override {
        _allowedValue[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Increase the allowance of a spender.
     * @param spender The spender address.
     * @param addedValue The amount to increase.
     */
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _allowedValue[msg.sender][spender] = _allowedValue[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedValue[msg.sender][spender]);
        return true;
    }

    /**
     * @notice Decrease the allowance of a spender.
     * @param spender The spender address.
     * @param subtractedValue The amount to decrease.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedValue[msg.sender][spender] = 0;
        } else {
            _allowedValue[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedValue[msg.sender][spender]);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the total number of rebases that have occurred.
     */
    function getRebasesLength() public view returns (uint256) {
        return rebases.length;
    }
}
