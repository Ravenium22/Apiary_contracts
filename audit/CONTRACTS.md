# Apiary Protocol Contract Reference

Complete reference for all Apiary protocol contracts, including purpose, functions, state variables, and events.

---

## Table of Contents

1. [ApiaryToken](#1-apiarytoken)
2. [sApiary](#2-sapiary)
3. [ApiaryTreasury](#3-apiarytreasury)
4. [ApiaryStaking](#4-apiarystaking)
5. [ApiaryStakingWarmup](#5-apiarystakingwarmup)
6. [ApiaryBondDepository](#6-apiarybonddepository)
7. [ApiaryPreSaleBond](#7-apiarypresalebond)
8. [ApiaryUniswapV2TwapOracle](#8-apiaryuniswapv2twaporacle)
9. [ApiaryYieldManager](#9-apiaryyieldmanager)
10. [ApiaryInfraredAdapter](#10-apiaryinfraredadapter)
11. [ApiaryKodiakAdapter](#11-apiarykodiakadapter)

---

## 1. ApiaryToken

**Location**: `src/ApiaryToken.sol`
**Inherits**: `ERC20Permit`, `VaultOwned`, `AccessControl`

### Purpose
Main protocol token with controlled minting via allocation limits.

### Constants
- `MINTER_ROLE`: Role required to mint tokens
- `BURNER_ROLE`: Role required to burn tokens
- `INITIAL_SUPPLY`: 200,000 APIARY (200_000e9)

### State Variables
```solidity
uint256 public totalMintedSupply;                    // Total minted so far
mapping(address => uint256) public allocationLimits;  // Mint limits per address
mapping(address => uint48) public lastTimeStaked;     // Last stake timestamp
```

### Key Functions

#### `setAllocationLimit(address minter, uint256 maxTokens)` 
**Access**: `DEFAULT_ADMIN_ROLE`
**Purpose**: Set one-time minting limit for an address
**Invariants**:
- Can only be called once per address
- Automatically grants `MINTER_ROLE`
- Cannot exceed `INITIAL_SUPPLY`

#### `mint(address account, uint256 amount)`
**Access**: `MINTER_ROLE`
**Purpose**: Mint new APIARY tokens
**Checks**:
- ✅ Caller has `MINTER_ROLE`
- ✅ `totalMintedSupply + amount <= INITIAL_SUPPLY`
- ✅ `amount <= allocationLimits[caller]`
**Effects**:
- Mints tokens to `account`
- Decrements `allocationLimits[caller]`
- Increments `totalMintedSupply`

#### `burn(uint256 amount)`
**Access**: Anyone (their own tokens)
**Purpose**: Burn APIARY tokens
**Effects**:
- Burns caller's tokens
- Decrements `totalSupply`
- Does NOT decrement `totalMintedSupply`

#### `burnFrom(address account, uint256 amount)`
**Access**: Anyone (with allowance)
**Purpose**: Burn tokens from another account
**Checks**:
- ✅ Caller has allowance
**Effects**:
- Burns tokens from `account`
- Decrements allowance

### Events
```solidity
event MinterAllocationSet(address indexed minter, uint256 indexed maxTokens);
```

### Errors
```solidity
error APIARY__INVALID_ADDRESS();
error APIARY__TOTAL_SUPPLY_EXCEEDED();
error APIARY__ALLOCATION_LIMIT_ALREADY_SET();
error APIARY__MAX_MINT_ALLOC_EXCEEDED();
error APIARY__BURN_AMOUNT_EXCEEDS_ALLOWANCE();
```

---

## 2. sApiary

**Location**: `src/sApiary.sol`
**Inherits**: `ERC20Permit`, `Ownable`

### Purpose
Rebasing staked APIARY token with dynamic index.

### Constants
```solidity
uint256 private constant MAX_UINT256 = type(uint256).max;
uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000e9;
uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
```

### State Variables
```solidity
address public stakingContract;        // Only staking can mint/burn
address public initializer;            // One-time initializer
uint256 private _gonsPerFragment;      // Conversion rate
mapping(address => uint256) private _gonBalances;  // Internal balances
Rebase[] public rebases;               // Rebase history
```

### Key Functions

#### `initialize(address stakingContract_)`
**Access**: `initializer` (one-time)
**Purpose**: Set staking contract and mint initial supply
**Effects**:
- Sets `stakingContract`
- Mints total supply to staking contract
- Can only be called once

#### `rebase(uint256 profit, uint256 epoch)`
**Access**: `stakingContract` only
**Purpose**: Increase index (rebase)
**Parameters**:
- `profit`: Amount of APIARY to distribute
- `epoch`: Current epoch number
**Effects**:
- Increases `_gonsPerFragment` (decreases value per gon)
- All balances effectively increase
- Records rebase in history

#### `balanceOf(address who)`
**Returns**: Balance in APIARY (fragments)
**Formula**: `_gonBalances[who] / _gonsPerFragment`

#### `circulatingSupply()`
**Returns**: Total supply minus staking contract balance
**Purpose**: Get actual circulating sAPIARY

### Events
```solidity
event LogSupply(uint256 indexed epoch, uint256 timestamp, uint256 totalSupply);
event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
event LogStakingContractUpdated(address stakingContract);
```

---

## 3. ApiaryTreasury

**Location**: `src/ApiaryTreasury.sol`
**Inherits**: `IApiaryTreasury`, `Ownable2Step`, `ReentrancyGuard`

### Purpose
Manages protocol reserves, mints APIARY for deposits, lends iBGT to yield manager.

### Immutables
```solidity
IApiaryToken public immutable APIARY_TOKEN;
address public immutable APIARY_HONEY_LP;
address public immutable IBGT;
address public immutable HONEY;
```

### State Variables
```solidity
mapping(address => bool) public isReserveToken;       // iBGT
mapping(address => bool) public isLiquidityToken;     // LP tokens
mapping(address => bool) public isReserveDepositor;   // Can deposit reserves
mapping(address => bool) public isLiquidityDepositor; // Can deposit LP
mapping(address => uint256) public totalReserves;     // Total per token
mapping(address => uint256) public totalBorrowed;     // Borrowed by YM

address public reservesManager;   // Deprecated
address public yieldManager;      // Can borrow iBGT

IBGTAccounting private _ibgtAccounting;  // iBGT tracking
```

### Key Functions

#### `deposit(uint256 amount, address token, uint256 value)`
**Access**: `isReserveDepositor` or `isLiquidityDepositor`
**Purpose**: Deposit tokens, receive APIARY
**Parameters**:
- `amount`: Token amount to deposit
- `token`: Token address (iBGT or LP)
- `value`: APIARY amount to mint
**Checks**:
- ✅ `token` is approved reserve or liquidity token
- ✅ Caller is authorized depositor
**Effects**:
- Transfers `token` from caller to treasury
- Increments `totalReserves[token]`
- Mints `value` APIARY to caller
- Emits `Deposit` event

#### `borrowIBGT(uint256 amount)`
**Access**: `yieldManager` only
**Purpose**: Yield manager borrows iBGT for staking
**Checks**:
- ✅ Sufficient iBGT available
**Effects**:
- Decrements `_ibgtAccounting.availableBalance`
- Increments `totalBorrowed[IBGT]`
- Increments `_ibgtAccounting.totalStaked`
- Transfers iBGT to yield manager

#### `repayIBGT(uint256 principal, uint256 yield)`
**Access**: `yieldManager` only
**Purpose**: Yield manager returns iBGT + yield
**Parameters**:
- `principal`: Original borrowed amount
- `yield`: Rewards earned
**Effects**:
- Decrements `totalBorrowed[IBGT]`
- Decrements `_ibgtAccounting.totalStaked`
- Increments `_ibgtAccounting.availableBalance`
- Increments `_ibgtAccounting.totalReturned`
- Transfers iBGT from yield manager

#### `setYieldManager(address _yieldManager)`
**Access**: `owner` only
**Purpose**: Set yield manager address
**Effects**: Updates `yieldManager`

### Events
```solidity
event Deposit(address indexed token, uint256 amount, uint256 value);
event IBGTBorrowed(uint256 amount);
event IBGTRepaid(uint256 principal, uint256 yield);
event YieldManagerSet(address indexed yieldManager);
```

### Errors
```solidity
error APIARY__ZERO_ADDRESS();
error APIARY__INVALID_TOKEN();
error APIARY__UNAUTHORIZED_YIELD_MANAGER();
error APIARY__INVALID_LIQUIDITY_DEPOSITOR();
error APIARY__INVALID_RESERVE_DEPOSITOR();
error APIARY__INSUFFICIENT_IBGT_AVAILABLE();
error APIARY__INSUFFICIENT_IBGT_STAKED();
```

---

## 4. ApiaryStaking

**Location**: `src/ApiaryStaking.sol`
**Inherits**: `Ownable`, `Pausable`, `ReentrancyGuard`

### Purpose
Stake APIARY to receive sAPIARY with warmup period.

### State Variables
```solidity
address public APIARY;         // APIARY token
address public sAPIARY;        // sAPIARY token
address public warmup;         // Warmup contract
address public locker;         // Optional locker
address public distributor;    // Yield distributor (Phase 2+)

Epoch public epoch;            // Current epoch info

mapping(address => Claim) public warmupInfo;  // User warmup data
```

### Epoch Struct
```solidity
struct Epoch {
    uint256 length;      // Blocks per epoch
    uint256 number;      // Current epoch
    uint256 endBlock;    // Block when epoch ends
    uint256 distribute;  // Amount to distribute (Phase 2+)
}
```

### Key Functions

#### `stake(uint256 amount, address recipient)`
**Access**: Public (when not paused)
**Purpose**: Stake APIARY, enter warmup
**Parameters**:
- `amount`: APIARY to stake
- `recipient`: Who receives sAPIARY
**Checks**:
- ✅ Not paused
- ✅ Warmup contract set
**Effects**:
- Transfers APIARY from caller
- Calculates sAPIARY amount (by index)
- Mints sAPIARY to warmup contract
- Creates warmup claim for `recipient`
- Updates `lastTimeStaked`

#### `unstake(uint256 amount, bool trigger)`
**Access**: Public (when not paused)
**Purpose**: Retrieve from warmup or unstake sAPIARY
**Parameters**:
- `amount`: Amount to unstake
- `trigger`: If false, retrieve from warmup; if true, burn sAPIARY
**For warmup (`trigger = false`)**:
- Retrieves sAPIARY from warmup after warmup period
- Transfers sAPIARY to user
**For unstake (`trigger = true`)**:
- Burns sAPIARY
- Calculates APIARY amount (by index)
- Transfers APIARY to user

#### `rebase()`
**Access**: Anyone (if epoch ended)
**Purpose**: Trigger epoch rebase
**Checks**:
- ✅ Current block >= `epoch.endBlock`
**Effects**:
- Increments `epoch.number`
- Updates `epoch.endBlock`
- If `distribute > 0`: calls `sAPIARY.rebase()`
- Emits `LogRebase`

#### `setWarmupContract(address _warmup)`
**Access**: `owner` only
**Purpose**: Set warmup contract (one-time)
**Effects**: Sets `warmup` address

### Events
```solidity
event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
event LogStake(address indexed recipient, uint256 amount);
event LogUnstake(address indexed recipient, uint256 amount);
event LogWarmupSet(address indexed warmup);
```

---

## 5. ApiaryStakingWarmup

**Location**: `src/ApiaryStakingWarmup.sol`

### Purpose
Hold sAPIARY during warmup period before users can claim.

### State Variables
```solidity
address public immutable staking;  // Staking contract
IsAPIARY public immutable sAPIARY;  // sAPIARY token
```

### Key Functions

#### `retrieve(address staker, uint256 amount)`
**Access**: `staking` contract only
**Purpose**: Transfer sAPIARY to user after warmup
**Effects**:
- Transfers `amount` sAPIARY to `staker`

---

## 6. ApiaryBondDepository

**Location**: `src/ApiaryBondDepository.sol`
**Inherits**: `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Purpose
Bond iBGT or LP tokens for vested APIARY.

### Immutables
```solidity
address public immutable APIARY;      // APIARY token
address public immutable principle;    // iBGT or LP
address public immutable treasury;     // Treasury
address public immutable dao;          // Fee recipient
IApiaryUniswapV2TwapOracle public immutable twap;  // Price oracle
address public immutable bondCalculator;  // LP valuation (optional)
bool public immutable isLiquidityBond;    // True if LP bond
```

### State Variables
```solidity
mapping(address => Bond) public bondInfo;  // User bonds
mapping(uint8 => Terms) public terms;      // Bond terms

uint256 public totalDebt;              // Total outstanding bonds
uint256 public lastDecay;              // Last debt decay timestamp
```

### Bond Struct
```solidity
struct Bond {
    uint256 payout;         // Total APIARY to receive
    uint256 vesting;        // Blocks to fully vest
    uint256 lastBlock;      // Last interaction block
    uint256 pricePaid;      // Price paid (for records)
}
```

### Terms Struct
```solidity
struct Terms {
    uint256 vestingTerm;    // Vesting period (blocks)
    uint256 discountRate;   // Discount in BPS
    uint256 maxDebt;        // Max total debt
}
```

### Key Functions

#### `deposit(uint256 amount, uint256 maxPrice, address depositor)`
**Access**: Public (when not paused)
**Purpose**: Create a bond by depositing principle
**Parameters**:
- `amount`: Principle amount to deposit
- `maxPrice`: Maximum acceptable price (slippage)
- `depositor`: Who receives the bond
**Checks**:
- ✅ Not paused
- ✅ `bondPrice() <= maxPrice`
- ✅ `totalDebt + payout <= terms.maxDebt`
**Effects**:
- Transfers principle from caller
- Deposits to treasury → receives APIARY
- Creates/updates bond with vesting schedule
- Increments `totalDebt`
- Emits `BondCreated`

#### `redeem(address depositor, bool all)`
**Access**: Public
**Purpose**: Redeem vested APIARY
**Parameters**:
- `depositor`: Whose bond to redeem
- `all`: If true, redeem all vested; if false, claim all
**Effects**:
- Calculates vested amount
- Transfers APIARY to depositor
- Updates bond info
- Decrements `totalDebt` if fully redeemed
- Emits `BondRedeemed`

#### `bondPrice()`
**Returns**: Current bond price in principle per APIARY
**Formula**: Uses TWAP oracle price with discount

#### `setBondTerms(uint8 parameter, uint256 input)`
**Access**: `owner` only
**Purpose**: Update bond terms
**Parameters**:
- `parameter`: 0=vestingTerm, 1=discountRate, 2=maxDebt
- `input`: New value

### Events
```solidity
event BondCreated(address indexed depositor, uint256 deposit, uint256 payout, uint256 expires, uint256 pricePaid);
event BondRedeemed(address indexed recipient, uint256 payout, uint256 remaining);
event BondTermsSet(uint8 parameter, uint256 input);
```

---

## 7. ApiaryPreSaleBond

**Location**: `src/ApiaryPreSaleBond.sol`
**Inherits**: `IApiaryPreSaleBond`, `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Purpose
Pre-sale with 110% bonus, merkle whitelist, linear vesting.

### State Variables
```solidity
IERC20 public honey;               // Payment token
IApiaryToken public apiary;        // APIARY token
address public treasury;           // Receives payments

bytes32 public merkleRoot;         // Whitelist root
uint128 public tokenPrice;         // HONEY per APIARY
uint128 public bondPurchaseLimit;  // Max per user
uint48 public tgeStartTime;        // TGE timestamp
bool public isWhitelistEnabled;    // Whitelist on/off

PreSaleBondState public currentPreSaleBondState;  // State machine

mapping(address => UserPurchaseInfo) public userPurchaseInfo;  // User data
uint256 public totalApiaryToMint;  // Total sold
```

### PreSaleBondState Enum
```solidity
enum PreSaleBondState {
    NotStarted,   // Pre-sale not started
    Active,       // Pre-sale active
    Ended,        // Pre-sale ended, before TGE
    TGEStarted    // TGE started, vesting active
}
```

### UserPurchaseInfo Struct
```solidity
struct UserPurchaseInfo {
    uint128 honeyPaid;          // HONEY paid
    uint128 apiaryPurchased;    // APIARY purchased (with 110% bonus)
    uint128 apiaryUnlocked;     // APIARY claimed so far
    uint48 lastUnlockTime;      // Last claim timestamp
}
```

### Key Functions

#### `purchaseApiary(uint256 honeyAmount, bytes32[] calldata merkleProof)`
**Access**: Public (whitelisted if enabled)
**Purpose**: Buy APIARY with HONEY
**Parameters**:
- `honeyAmount`: HONEY to spend
- `merkleProof`: Merkle proof for whitelist
**Checks**:
- ✅ State is `Active`
- ✅ Whitelist verification (if enabled)
- ✅ User limit not exceeded
**Effects**:
- Transfers HONEY from user to treasury
- Calculates APIARY amount with 110% bonus
- Records purchase info
- Increments `totalApiaryToMint`

#### `unlockApiary()`
**Access**: Public
**Purpose**: Claim vested APIARY
**Checks**:
- ✅ State is `TGEStarted`
- ✅ User has purchased
**Effects**:
- Calculates vested amount (linear over 30 days)
- Transfers APIARY to user
- Updates `apiaryUnlocked` and `lastUnlockTime`

#### `startPreSaleBond()`
**Access**: `owner` only
**Purpose**: Start pre-sale
**Effects**: Sets state to `Active`

#### `endPreSaleBond()`
**Access**: `owner` only
**Purpose**: End pre-sale
**Effects**: Sets state to `Ended`

#### `startTge()`
**Access**: `owner` only
**Purpose**: Start TGE and vesting
**Checks**:
- ✅ State is `Ended`
- ✅ APIARY has been minted to contract
**Effects**:
- Sets state to `TGEStarted`
- Records `tgeStartTime`

#### `mintTotalSoldApiary()`
**Access**: `owner` only
**Purpose**: Mint all sold APIARY to contract
**Checks**:
- ✅ State is `Ended`
**Effects**:
- Mints `totalApiaryToMint` to contract
- Ready for TGE start

### Events
```solidity
event ApiaryPurchased(address indexed user, uint256 honeyPaid, uint256 apiaryPurchased);
event ApiaryUnlocked(address indexed user, uint256 amount);
event PreSaleBondStarted(PreSaleBondState state);
event PreSaleBondEnded(PreSaleBondState state);
event TgeStarted(uint48 tgeStartTime);
```

---

## 8. ApiaryUniswapV2TwapOracle

**Location**: `src/ApiaryUniswapV2TwapOracle.sol`

### Purpose
Time-weighted average price oracle for APIARY/HONEY pair.

### State Variables
```solidity
address public immutable pair;      // Uniswap V2 pair
address public immutable token0;    // APIARY
address public immutable token1;    // HONEY

uint256 public price0CumulativeLast;
uint256 public price1CumulativeLast;
uint32 public blockTimestampLast;
uint256 public price0Average;
uint256 public price1Average;

uint256 public minimumUpdateInterval;  // Min seconds between updates
```

### Key Functions

#### `update()`
**Access**: Public
**Purpose**: Update TWAP prices
**Checks**:
- ✅ Enough time passed since last update
**Effects**:
- Reads current cumulative prices from pair
- Calculates time-weighted average
- Updates `price0Average` and `price1Average`

#### `consult(address token, uint256 amountIn)`
**Returns**: Equivalent amount of other token
**Purpose**: Get price for amount
**Example**: `consult(APIARY, 1e9)` returns HONEY value of 1 APIARY

---

## 9. ApiaryYieldManager

**Location**: `src/ApiaryYieldManager.sol`
**Inherits**: `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Purpose
**MOST CRITICAL CONTRACT** - Orchestrates all yield distribution.

### Immutables
```solidity
IERC20 public immutable apiaryToken;
IERC20 public immutable honeyToken;
IERC20 public immutable ibgtToken;
```

### State Variables
```solidity
address public treasury;
address public infraredAdapter;
address public kodiakAdapter;
address public stakingContract;

Strategy public currentStrategy;        // Current phase
SplitConfig public splitConfig;         // Yield splits
uint256 public slippageTolerance;       // Swap slippage (BPS)
uint256 public minYieldAmount;          // Min to execute
uint256 public maxExecutionAmount;      // Max per execution
uint256 public mcThresholdMultiplier;   // Phase 2 MC/TV ratio
uint256 public totalYieldProcessed;     // Historical total
bool public emergencyMode;              // Bypass adapters
```

### Strategy Enum
```solidity
enum Strategy {
    PHASE1_LP_BURN,      // 25/25/50
    PHASE2_CONDITIONAL,  // MC/TV based
    PHASE3_VBGT          // vBGT staking
}
```

### SplitConfig Struct
```solidity
struct SplitConfig {
    uint256 toHoney;      // % to HONEY
    uint256 toApiaryLP;   // % to LP
    uint256 toBurn;       // % to burn
    uint256 toStakers;    // % to stakers (Phase 2+)
    uint256 toCompound;   // % to compound (Phase 2+)
}
```

### Key Functions

#### `executeYield()`
**Access**: Public (when not paused)
**Purpose**: Execute yield strategy
**Checks**:
- ✅ Not paused
- ✅ Pending yield >= `minYieldAmount`
- ✅ Adapters configured
**Effects (Phase 1)**:
1. Borrow iBGT from treasury (if needed for staking)
2. Claim rewards from Infrared adapter
3. Split yield according to `splitConfig`:
   - 25% → swap to HONEY via Kodiak
   - 25% → swap to APIARY → burn
   - 50% → create APIARY/HONEY LP → stake
4. Repay iBGT to treasury
5. Update `totalYieldProcessed`
**Returns**: `(totalYield, honeySwapped, apiaryBurned, lpCreated, compounded)`

#### `setStrategy(Strategy newStrategy)`
**Access**: `owner` only
**Purpose**: Change yield strategy
**Effects**: Updates `currentStrategy`

#### `setSplitConfig(SplitConfig memory newConfig)`
**Access**: `owner` only
**Purpose**: Update yield splits
**Checks**:
- ✅ Sum of splits = 10000 (100%)
**Effects**: Updates `splitConfig`

#### `setEmergencyMode(bool enabled)`
**Access**: `owner` only
**Purpose**: Enable/disable emergency mode
**Effects**:
- If enabled: Skip adapters, send yield to treasury
- If disabled: Normal operation

#### `emergencyWithdraw(address token)`
**Access**: `owner` only
**Purpose**: Withdraw stuck tokens
**Effects**: Transfers entire balance to treasury

### Events
```solidity
event YieldExecuted(uint256 totalYield, uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated);
event StrategyChanged(Strategy indexed newStrategy);
event SplitConfigUpdated(uint256 toHoney, uint256 toApiaryLP, uint256 toBurn);
event EmergencyModeEnabled(bool enabled);
```

### Errors
```solidity
error APIARY__ZERO_ADDRESS();
error APIARY__INVALID_SPLIT_CONFIG();
error APIARY__INSUFFICIENT_YIELD();
error APIARY__NO_PENDING_YIELD();
error APIARY__SWAP_FAILED(string reason);
error APIARY__LP_CREATION_FAILED();
error APIARY__BURN_FAILED();
error APIARY__EMERGENCY_MODE_ACTIVE();
error APIARY__ADAPTER_NOT_SET();
```

---

## 10. ApiaryInfraredAdapter

**Location**: `src/ApiaryInfraredAdapter.sol`
**Inherits**: `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Purpose
Interface to Infrared protocol for iBGT staking.

### State Variables
```solidity
IInfrared public infrared;         // Infrared staking
IERC20 public ibgt;                 // iBGT token
IERC20 public rewardToken;          // Reward token
address public treasury;            // Treasury
address public yieldManager;        // Only caller

uint256 public minStakeAmount;      // Min stake
uint256 public minUnstakeAmount;    // Min unstake
uint256 public totalStaked;         // Total staked
uint256 public totalClaimed;        // Total claimed
```

### Key Functions

#### `stake(uint256 amount)`
**Access**: `yieldManager` only
**Purpose**: Stake iBGT on Infrared
**Checks**:
- ✅ Not paused
- ✅ `amount >= minStakeAmount`
**Effects**:
- Approves Infrared to spend iBGT
- Stakes on Infrared
- Increments `totalStaked`

#### `unstake(uint256 amount)`
**Access**: `yieldManager` only
**Purpose**: Unstake iBGT from Infrared
**Checks**:
- ✅ Not paused
- ✅ `amount >= minUnstakeAmount`
**Effects**:
- Withdraws from Infrared
- Decrements `totalStaked`
- Returns iBGT to caller

#### `claimRewards()`
**Access**: `yieldManager` only
**Purpose**: Claim staking rewards
**Returns**: Amount claimed
**Effects**:
- Claims rewards from Infrared
- Increments `totalClaimed`
- Transfers rewards to yield manager

#### `getPendingRewards()`
**Returns**: Pending rewards
**Purpose**: View unclaimed rewards

#### `emergencyWithdraw()`
**Access**: `owner` only
**Purpose**: Emergency unstake all
**Effects**:
- Withdraws all staked iBGT
- Transfers to treasury

### Events
```solidity
event Staked(uint256 amount);
event Unstaked(uint256 amount);
event RewardsClaimed(uint256 amount);
event EmergencyWithdraw(uint256 amount);
```

---

## 11. ApiaryKodiakAdapter

**Location**: `src/ApiaryKodiakAdapter.sol`
**Inherits**: `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Purpose
Interface to Kodiak DEX for swaps and LP operations.

### State Variables
```solidity
IKodiakRouter public kodiakRouter;      // Router for swaps
IKodiakFactory public kodiakFactory;    // Factory
IERC20 public honey;                     // HONEY token
IERC20 public apiary;                    // APIARY token
address public treasury;                 // Treasury
address public yieldManager;             // Only caller

uint256 public defaultSlippageBps;       // Default slippage
uint256 public defaultDeadlineOffset;    // Default deadline
uint256 public minSwapAmount;            // Min swap
uint256 public minLiquidityAmount;       // Min LP
```

### Key Functions

#### `swapIBGTForHoney(uint256 ibgtAmount, uint256 minHoneyOut)`
**Access**: `yieldManager` only
**Purpose**: Swap iBGT → HONEY
**Parameters**:
- `ibgtAmount`: iBGT to swap
- `minHoneyOut`: Min HONEY (slippage)
**Returns**: HONEY received
**Effects**:
- Swaps on Kodiak router
- Returns HONEY to yield manager

#### `swapIBGTForApiary(uint256 ibgtAmount, uint256 minApiaryOut)`
**Access**: `yieldManager` only
**Purpose**: Swap iBGT → APIARY
**Returns**: APIARY received

#### `addLiquidityApiaryHoney(uint256 apiaryAmount, uint256 honeyAmount, uint256 minLiquidity)`
**Access**: `yieldManager` only
**Purpose**: Add APIARY/HONEY liquidity
**Returns**: LP tokens created
**Effects**:
- Adds liquidity on Kodiak
- Returns LP tokens to yield manager

#### `stakeLPTokens(uint256 lpAmount)`
**Access**: `yieldManager` only
**Purpose**: Stake LP on Kodiak gauge
**Effects**:
- Deposits LP to gauge
- Earns rewards

#### `unstakeLPTokens(uint256 lpAmount)`
**Access**: `yieldManager` only
**Purpose**: Unstake LP from gauge

#### `claimLPRewards()`
**Access**: `yieldManager` only
**Purpose**: Claim LP staking rewards
**Returns**: Rewards claimed

#### `emergencyWithdraw(address token)`
**Access**: `owner` only
**Purpose**: Withdraw stuck tokens

### Events
```solidity
event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
event LiquidityAdded(uint256 apiaryAmount, uint256 honeyAmount, uint256 liquidity);
event LPStaked(uint256 amount);
event LPUnstaked(uint256 amount);
event LPRewardsClaimed(address[] tokens, uint256[] amounts);
```

---

## Access Control Summary

| Contract | Access Mechanism | Critical Roles |
|----------|------------------|----------------|
| ApiaryToken | AccessControl | DEFAULT_ADMIN_ROLE, MINTER_ROLE, BURNER_ROLE |
| sApiary | Custom (stakingContract) | stakingContract, initializer |
| ApiaryTreasury | Ownable2Step | owner, yieldManager |
| ApiaryStaking | Ownable | owner |
| ApiaryBondDepository | Ownable2Step | owner |
| ApiaryPreSaleBond | Ownable2Step | owner |
| ApiaryYieldManager | Ownable2Step | owner |
| ApiaryInfraredAdapter | Ownable2Step | owner, yieldManager |
| ApiaryKodiakAdapter | Ownable2Step | owner, yieldManager |

---

## Critical Functions Summary

**Most Critical (Can cause loss of funds):**
1. `ApiaryYieldManager.executeYield()` - Handles all yield distribution
2. `ApiaryTreasury.borrowIBGT()` - Lends treasury reserves
3. `ApiaryInfraredAdapter.stake()` - Stakes on external protocol
4. `ApiaryKodiakAdapter.swap*()` - Swaps that could be frontrun

**Admin Functions (Owner only):**
1. Setting adapters in YieldManager
2. Changing yield strategy
3. Setting bond terms
4. Emergency withdrawals
5. Pausing contracts

**Public Functions (User-facing):**
1. `stake()` / `unstake()` - Staking
2. `deposit()` / `redeem()` - Bonding
3. `purchaseApiary()` / `unlockApiary()` - Pre-sale
4. `executeYield()` - Anyone can trigger

---

**For security analysis, see [SECURITY.md](./SECURITY.md)**
**For invariants, see [INVARIANTS.md](./INVARIANTS.md)**
