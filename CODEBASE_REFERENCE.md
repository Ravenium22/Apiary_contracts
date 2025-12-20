# BeraReserve Contracts - Comprehensive Codebase Reference

A detailed technical reference guide for the BeraReserve smart contract protocol, a DeFi reserve currency protocol built on Berachain, forked from Olympus DAO (OHM).

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Token Economics](#token-economics)
4. [Data Types & Structures](#data-types--structures)
5. [Core Contracts](#core-contracts)
6. [BRR Token - Deep Dive](#brr-token---deep-dive)
7. [sBRR Token - Rebasing Mechanics](#sbrr-token---rebasing-mechanics)
8. [Bonding System](#bonding-system)
9. [Staking System](#staking-system)
10. [Treasury System](#treasury-system)
11. [Vesting & Lockup](#vesting--lockup)
12. [Pre-Sale Bond System](#pre-sale-bond-system)
13. [Fee Distribution](#fee-distribution)
14. [Oracle System](#oracle-system)
15. [Utility Libraries](#utility-libraries)
16. [Contract Interactions](#contract-interactions)
17. [Access Control & Security](#access-control--security)
18. [Development Setup](#development-setup)
19. [Testing](#testing)
20. [Deployment Scripts](#deployment-scripts)

---

## Project Overview

BeraReserve is a **reserve currency protocol** built on Berachain (Chain ID: 80094). It implements the Olympus DAO (OHM) model with customizations for the Berachain ecosystem.

### Core Protocol Mechanics

1. **Protocol-Owned Liquidity (POL)**: Users bond assets (USDC, LP tokens) to receive discounted BRR tokens
2. **Staking Rewards**: Stakers receive rebasing sBRR tokens that auto-compound
3. **Treasury Backing**: BRR is backed by treasury assets (USDC, LP tokens)
4. **Token Decay**: Unique mechanism that burns unstaked BRR over time to incentivize staking
5. **Dynamic Fees**: Sliding scale fees based on market cap vs treasury value

### Technology Stack
- **Solidity Version**: 0.8.26
- **Framework**: Foundry (forge, cast, anvil)
- **Target Chain**: Berachain Mainnet (Chain ID: 80094)
- **Testnet**: Bepolia (Chain ID: 80069)
- **DEX Integration**: Uniswap V2 (Kodiak on Berachain)
- **Dependencies**: 
  - OpenZeppelin Contracts (AccessControl, Ownable2Step, Pausable, SafeERC20)
  - Uniswap V2 Core

### Key Design Decisions
- **9 Decimals**: BRR uses 9 decimals (like OHM) instead of standard 18
- **Gons-based Accounting**: sBRR uses gons for rebasing math
- **Two-Step Ownership**: All admin contracts use Ownable2Step for safety
- **Pausable**: Critical functions can be paused in emergencies

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                            BeraReserve Protocol Architecture                        │
├───────────────────────────────────────────────────────────────────────────────────┤
│                                                                                    │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                              TOKEN LAYER                                    │   │
│  │  ┌──────────────────┐                    ┌──────────────────┐              │   │
│  │  │   BRR Token      │◄──── stake ───────►│   sBRR Token     │              │   │
│  │  │  (BeraReserve    │                    │  (sBeraReserve)  │              │   │
│  │  │   Token.sol)     │◄──── unstake ──────│   Rebasing ERC20 │              │   │
│  │  │  - 9 decimals    │                    │  - Gons-based    │              │   │
│  │  │  - Decay mech    │                    │  - Auto-compound │              │   │
│  │  │  - Fee on xfer   │                    │                  │              │   │
│  │  └──────────────────┘                    └──────────────────┘              │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                              │                         ▲                           │
│                              ▼                         │                           │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                            STAKING LAYER                                    │   │
│  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │   │
│  │  │  BeraReserve     │    │  StakingWarmup   │    │  Staking         │      │   │
│  │  │  Staking         │───►│  (holds sBRR     │    │  Distributor     │      │   │
│  │  │  - Epochs        │    │   during warmup) │    │  (reward rates)  │      │   │
│  │  │  - Rebase        │    └──────────────────┘    └──────────────────┘      │   │
│  │  │  - Warmup period │                                   │                  │   │
│  │  └──────────────────┘                                   │                  │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                              │                                                     │
│                              ▼                                                     │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                           TREASURY LAYER                                    │   │
│  │  ┌──────────────────┐              ┌──────────────────┐                    │   │
│  │  │  Treasury V1     │              │  Treasury V2     │                    │   │
│  │  │  (Full Olympus   │              │  (Simplified)    │                    │   │
│  │  │   queue system)  │              │  - Reserve/LP    │                    │   │
│  │  │  - 10 MANAGING   │              │  - Depositors    │                    │   │
│  │  │    types         │              │  - Borrow/Repay  │                    │   │
│  │  └──────────────────┘              └──────────────────┘                    │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                              │                                                     │
│                              ▼                                                     │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                           BONDING LAYER                                     │   │
│  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │   │
│  │  │  BondDepository  │    │  BeraReserve     │    │  BeraReserve     │      │   │
│  │  │  V2              │    │  PreSaleBond     │    │  PreBondClaims   │      │   │
│  │  │  - TWAP pricing  │    │  - Whitelist     │    │                  │      │   │
│  │  │  - Discount rate │    │  - Merkle proof  │    │                  │      │   │
│  │  │  - Vesting       │    │  - 5-day vest    │    │                  │      │   │
│  │  └──────────────────┘    └──────────────────┘    └──────────────────┘      │   │
│  │           │                                                                 │   │
│  │           ▼                                                                 │   │
│  │  ┌──────────────────┐    ┌──────────────────┐                              │   │
│  │  │  TWAP Oracle     │    │  Bonding         │                              │   │
│  │  │  (UniV2)         │    │  Calculator      │                              │   │
│  │  │  - 1 hour period │    │  (LP valuation)  │                              │   │
│  │  └──────────────────┘    └──────────────────┘                              │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                         DISTRIBUTION LAYER                                  │   │
│  │  ┌──────────────────┐              ┌──────────────────┐                    │   │
│  │  │  Fee Distributor │              │  LockUp          │                    │   │
│  │  │  - Team 33%      │              │  - Team vesting  │                    │   │
│  │  │  - POL 33%       │              │  - Marketing     │                    │   │
│  │  │  - Treasury 34%  │              │  - Seed round    │                    │   │
│  │  └──────────────────┘              └──────────────────┘                    │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
└───────────────────────────────────────────────────────────────────────────────────┘
```

---

## Token Economics

### BRR Token Distribution

| Allocation          | Percentage | Amount (BRR) | Vesting/Notes                              | Staked? |
|---------------------|------------|--------------|-------------------------------------------|---------|
| **Team**            | 20%        | 40,000       | 1 year linear vesting, 3-month cliff      | ✅ Yes  |
| **Marketing**       | 5%         | 10,000       | 1 year linear vesting                     | ✅ Yes  |
| **Treasury**        | 20%        | 40,000       | Protocol-controlled                       | No      |
| **Liquidity**       | 5%         | 10,000       | Initial DEX liquidity (BRR/HONEY pair)    | No      |
| **Seed Round**      | 20%        | 40,000       | 30% TGE, 70% vested over 6 months         | ✅ Yes  |
| **Pre-Bonds**       | 5%         | 10,000 (later changed to 50,000) | 5-day linear vesting | No      |
| **Airdrop**         | 12%        | 24,000       | Community distribution                    | No      |
| **Rewards**         | 13%        | 26,000       | Staking incentives                        | No      |
| **Total**           | 100%       | 200,000      |                                           |         |

### Key Token Parameters
```solidity
// Token Supply
uint256 public constant INITIAL_BRR_SUPPLY = 160_000e9;  // 160,000 BRR (mintable by treasury/bonds)
uint256 internal constant LIQUIDITY_TOTAL_BRR_AMOUNT = 10_000e9;   // Pre-minted
uint256 internal constant AIRDROP_TOTAL_BRR_AMOUNT = 24_000e9;     // Pre-minted
uint256 internal constant REWARDS_TOTAL_BRR_AMOUNT = 26_000e9;     // Pre-minted

// Pricing
Initial Price: $1.01
Initial Market Cap: $200,000
Token Decimals: 9

// Fees (in Basis Points - BPS)
Default Buy Fee: 300 (3%)
Default Sell Fee: 300 (3%)
Max Fee: 10,000 (100%)

// Decay
Default Decay Ratio: 2,000 (20% per year)
Default Decay Interval: 28,800 seconds (8 hours)
Decay Period: 365 days (1 year for full decay calculation)
```

### Economic Mechanisms

#### 1. Treasury Backing
```
BRR Value Floor = Total Treasury Reserves / BRR Circulating Supply
```

#### 2. Excess Reserves (for Staking Rewards)
```solidity
function excessReserves() public view returns (uint256) {
    return totalReserves.sub(IERC20(BRR).totalSupply().sub(totalDebt));
}
```
Only excess reserves can be distributed as staking rewards.

#### 3. Bond Discount
```solidity
discountedPrice = marketPrice * (10000 - discountRate) / 10000
```

---

## Data Types & Structures

### Core Types (`src/types/BeraReserveTypes.sol`)

```solidity
// Member types for vesting schedules
enum MemberType {
    TEAM,        // 0 - Team allocation
    MARKETING,   // 1 - Marketing allocation
    SEED_ROUND   // 2 - Seed investor allocation
}

// Vesting schedule for team/marketing/seed
struct VestingSchedule {
    MemberType memberType;      // Type of member
    uint128 totalAmount;        // Total tokens allocated
    uint256 amountUnlockedAtTGE; // Tokens available at TGE (seed only)
    uint128 amountClaimed;      // Tokens already claimed
    uint32 start;               // Vesting start timestamp
    uint32 cliff;               // Cliff end timestamp (team only)
    uint32 duration;            // Total vesting duration
}

// Fee calculation data for sliding scale
struct TreasuryValueData {
    uint256 fee;                // Final fee to charge
    uint256 treasuryPercentage; // % of fee to treasury
    uint256 burnPercentage;     // % of fee to burn
    bool isSliding;             // If sliding scale is active
}

// Pre-sale bond states
enum PreSaleBondState {
    NotStarted,  // 0 - Sale not yet started
    Live,        // 1 - Sale is active
    Ended        // 2 - Sale has ended
}

// Pre-sale investor information
struct InvestorBondInfo {
    uint128 totalAmount;    // Total BRR purchased
    uint128 unlockedAmount; // BRR already claimed
    uint48 start;           // Not used (TGE time is global)
    uint48 duration;        // 5 days vesting
}
```

### Bond Structures (BondDepositoryV2)

```solidity
// Bond terms configuration
struct Terms {
    uint256 vestingTerm;   // Vesting period in BLOCKS (not seconds)
    uint256 maxPayout;     // Max % of treasury per bond (in thousandths: 500 = 0.5%)
    uint256 fee;           // DAO fee on bond payout (in hundredths: 500 = 5%)
    uint256 discountRate;  // Discount from market price (BPS: 100 = 1%)
    uint256 maxDebt;       // Maximum total debt allowed
}

// Individual bond information
struct Bond {
    uint256 amountBonded;  // Principal amount deposited
    uint256 payout;        // BRR remaining to be paid
    uint256 vesting;       // Blocks left until fully vested
    uint256 lastBlock;     // Block of last interaction
    uint256 pricePaid;     // Price paid in HONEY (18 decimals)
}

// Parameter enum for bond term updates
enum PARAMETER {
    VESTING,       // 0 - Update vesting term
    PAYOUT,        // 1 - Update max payout
    FEE,           // 2 - Update DAO fee
    DISCOUNT_RATE, // 3 - Update discount rate
    MAX_DEBT       // 4 - Update max debt
}
```

### Staking Structures

```solidity
// Epoch information for staking rebases
struct Epoch {
    uint256 length;     // Blocks per epoch
    uint256 number;     // Current epoch number
    uint256 endBlock;   // Block when epoch ends
    uint256 distribute; // Amount to distribute this epoch
}

// Warmup claim information
struct Claim {
    uint256 deposit; // BRR amount deposited
    uint256 gons;    // Gons equivalent (for rebase tracking)
    uint256 expiry;  // Epoch when warmup ends
    bool lock;       // If locked (prevents malicious delays)
}

// Rebase history record (sBRR)
struct Rebase {
    uint256 epoch;              // Epoch number
    uint256 rebase;             // Rebase percentage (18 decimals)
    uint256 totalStakedBefore;  // Supply before rebase
    uint256 totalStakedAfter;   // Supply after rebase
    uint256 amountRebased;      // BRR distributed
    uint256 index;              // New index value
    uint256 blockNumberOccured; // Block of rebase
}
```

### Treasury V1 Managing Types

```solidity
enum MANAGING {
    RESERVEDEPOSITOR,    // 0 - Can deposit reserve tokens
    RESERVESPENDER,      // 1 - Can withdraw reserves (burn BRR)
    RESERVETOKEN,        // 2 - Approved reserve token
    RESERVEMANAGER,      // 3 - Can manage reserves
    LIQUIDITYDEPOSITOR,  // 4 - Can deposit LP tokens
    LIQUIDITYTOKEN,      // 5 - Approved LP token
    LIQUIDITYMANAGER,    // 6 - Can manage liquidity
    DEBTOR,              // 7 - Can borrow against sBRR
    REWARDMANAGER,       // 8 - Can mint rewards
    SBRR                 // 9 - Set sBRR address
}
```

---

## Core Contracts

### Contract File Overview

| Contract | File | Lines | Purpose |
|----------|------|-------|---------|
| `BeraReserveToken` | `src/BeraReserveToken.sol` | 475 | Main BRR token with fees/decay |
| `sBeraReserve` | `src/sBeraReserveERC20.sol` | 1213 | Staked rebasing token |
| `BeraReserveStaking` | `src/Staking.sol` | 847 | Staking with warmup/epochs |
| `BeraReserveBondDepositoryV2` | `src/BeraReserveBondDepositoryV2.sol` | 389 | V2 Bond purchases |
| `BeraReserveTreasuryV2` | `src/BeraReserveTreasuryV2.sol` | 141 | Simplified treasury |
| `BeraReserveTreasury` | `src/Treasury.sol` | 705 | Full V1 treasury |
| `BeraReserveLockUp` | `src/BeraReserveLockUp.sol` | 445 | Vesting schedules |
| `BeraReservePreSaleBond` | `src/BeraReservePreSaleBond.sol` | 394 | Pre-sale with whitelist |
| `BeraReserveFeeDistributor` | `src/BeraReserveFeeDistributor.sol` | 225 | Fee distribution |
| `BeraReserveUniswapV2TwapOracle` | `src/utils/BeraReserveUniswapV2TwapOracle.sol` | 63 | TWAP price oracle |
| `BeraReserveBondingCalculator` | `src/BeraReserveBondingCalculator.sol` | 223 | LP token valuation |
| `Distributor` | `src/StakingDistributor.sol` | 505 | Staking reward distribution |

---

## BRR Token - Deep Dive

### Contract: `BeraReserveToken` (`src/BeraReserveToken.sol`)

The main protocol token implementing ERC20 with advanced features.

### Inheritance Chain
```
BeraReserveToken
├── ERC20Permit (custom, not OZ)
│   └── ERC20 (custom implementation)
├── VaultOwned (for staking contract reference)
└── AccessControl (OpenZeppelin)
```

### Roles
```solidity
bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // From AccessControl
```

### Key Constants
```solidity
uint256 internal constant BPS = 10_000;                          // Basis points divisor
uint256 internal constant LIQUIDITY_TOTAL_BRR_AMOUNT = 10_000e9; // 5% for liquidity
uint256 internal constant AIRDROP_TOTAL_BRR_AMOUNT = 24_000e9;   // 12% for airdrop
uint256 internal constant REWARDS_TOTAL_BRR_AMOUNT = 26_000e9;   // 13% for rewards
uint256 public constant INITIAL_BRR_SUPPLY = 160_000e9;          // Max mintable
address internal constant LIQUIDITY_WALLET = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
```

### State Variables
```solidity
// Uniswap Integration
IUniswapV2Router02 internal uniswapV2Router;
address public uniswapV2Pair;              // BRR/HONEY pair for fee detection

// Fee Configuration
uint256 public buyFee;                     // Fee on buys (default: 300 = 3%)
uint256 public sellFee;                    // Fee on sells (default: 300 = 3%)
bool public isFeeDisabled;                 // Global fee toggle
address public feeDistributor;             // Receives collected fees

// Sliding Scale Fees (when market cap < treasury value)
uint256 public twentyFivePercentBelowFees; // Fee when MC <= 75% of TV
uint256 public tenPercentBelowFees;        // Fee when MC <= 90% of TV  
uint256 public belowTreasuryValueFees;     // Fee when MC <= TV

// Decay Configuration
uint256 public decayRatio;                 // Annual decay rate (default: 2000 = 20%)
uint256 public decayInterval;              // Seconds between decays (default: 28800 = 8hrs)

// Treasury/Market Data
uint256 public treasuryValue;              // Set by admin for fee calculation
uint256 public marketCap;                  // Set by admin for fee calculation
address public protocolTreasuryAddress;    // Receives treasury portion of sliding fees

// Minting Controls
uint256 public treasuryAllocation;         // Additional treasury allocation
uint256 public totalTreasuryMinted;        // Track treasury mints
uint256 public totalMintedSupply;          // Total minted (capped at INITIAL_BRR_SUPPLY)

// Per-User Tracking
mapping(address => uint48) public lastTimeBurnt;      // Last decay timestamp
mapping(address => uint48) public lastTimeStaked;     // Last stake timestamp
mapping(address => uint48) public lastTimeReceived;   // Last receive timestamp
mapping(address => bool) public isExcludedAccountsFromFees;   // Fee whitelist
mapping(address => bool) public isExcludedAccountsFromDecay;  // Decay whitelist
mapping(address => uint256) public allocationLimits;  // Max mint per minter
```

### Constructor
```solidity
constructor(address protocolAdmin, address rewardWallet, address airdropWallet) 
    ERC20("Bera Reserve", "BRR", 9) 
{
    // Validation
    require(protocolAdmin != address(0) && rewardWallet != address(0) && airdropWallet != address(0));
    
    // Set immutable wallets
    REWARDS_WALLET = rewardWallet;
    AIRDROP_WALLET = airdropWallet;
    
    // Grant admin role
    _grantRole(DEFAULT_ADMIN_ROLE, protocolAdmin);
    
    // Initialize fees and decay
    buyFee = sellFee = 300;        // 3%
    decayRatio = 2_000;            // 20% annual
    decayInterval = 28_800;        // 8 hours
    
    // Exclude wallets from fees/decay
    isExcludedAccountsFromFees[LIQUIDITY_WALLET] = true;
    isExcludedAccountsFromFees[REWARDS_WALLET] = true;
    isExcludedAccountsFromDecay[LIQUIDITY_WALLET] = true;
    isExcludedAccountsFromDecay[REWARDS_WALLET] = true;
    
    // Pre-mint allocations
    _mint(LIQUIDITY_WALLET, LIQUIDITY_TOTAL_BRR_AMOUNT);  // 10,000 BRR
    _mint(REWARDS_WALLET, REWARDS_TOTAL_BRR_AMOUNT);       // 26,000 BRR
    _mint(AIRDROP_WALLET, AIRDROP_TOTAL_BRR_AMOUNT);       // 24,000 BRR
}
```

### Minting System

```solidity
// Set allocation limit for a minter (one-time per address)
function setAllocationLimit(address minter, uint256 maxNumberOfTokens) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (allocationLimits[minter] != 0) revert BERA_RESERVE__ALLOCATION_LIMIT_ALREADY_SET();
    
    // Auto-grant MINTER_ROLE if not already granted
    if (!hasRole(MINTER_ROLE, minter)) {
        _grantRole(MINTER_ROLE, minter);
    }
    
    allocationLimits[minter] = maxNumberOfTokens;
}

// Mint tokens (respects allocation limits)
function mint(address account_, uint256 amount_) external onlyRole(MINTER_ROLE) {
    // Check global supply cap
    if (totalMintedSupply + amount_ > INITIAL_BRR_SUPPLY) 
        revert BERA_RESERVE__TOTAL_SUPPLY_EXCEEDED();
    
    // Check per-minter allocation
    if (amount_ > allocationLimits[_msgSender()]) 
        revert BERA_RESERVE__MAX_MINT_ALLOC_EXCEEDED();
    
    // Decrease allocation and mint
    allocationLimits[_msgSender()] -= amount_;
    _mint(account_, amount_);
    totalMintedSupply += amount_;
    
    // Track receive time for decay calculation
    lastTimeReceived[account_] = uint48(block.timestamp);
}
```

### Decay Mechanism

The decay mechanism burns a portion of unstaked BRR balances over time:

```solidity
// Called before every transfer
function _beforeTokenTransfer(address from_, address, uint256) internal override {
    if (_balances[from_] != 0 && !isExcludedAccountsFromDecay[from_]) {
        // Calculate decay using utility library
        uint256 tokensToBurn = BeraReserveTokenUtils.applyDecay(
            decayRatio,
            _balances[from_],
            lastTimeBurnt[from_],
            lastTimeReceived[from_],
            lastTimeStaked[from_],
            decayInterval
        );
        
        // Apply decay
        uint256 balanceRemaining = balanceOf(from_);
        _totalSupply -= tokensToBurn;
        lastTimeBurnt[from_] = uint48(block.timestamp);
        _balances[from_] = balanceRemaining;
        
        emit Transfer(from_, address(0), tokensToBurn);
    }
}

// balanceOf accounts for pending decay
function balanceOf(address account) public view override returns (uint256) {
    if (_balances[account] != 0 && !isExcludedAccountsFromDecay[account]) {
        uint256 tokensToBurn = BeraReserveTokenUtils.applyDecay(
            decayRatio,
            _balances[account],
            lastTimeBurnt[account],
            lastTimeReceived[account],
            lastTimeStaked[account],
            decayInterval
        );
        
        if (tokensToBurn > _balances[account]) return 0;
        return _balances[account] - tokensToBurn;
    }
    return _balances[account];
}
```

**Decay Formula:**
```
decayRatePerEpoch = (decayRatio × decayInterval × 1e18) / (BPS × DECAY_PERIOD)
elapsedEpochs = elapsedTime / decayInterval
decayAmount = balance × decayRatePerEpoch × elapsedEpochs / 1e18
```

**Example:**
- `decayRatio = 2000` (20% annual)
- `decayInterval = 28800` (8 hours)
- `DECAY_PERIOD = 31536000` (1 year in seconds)
- After 24 hours (3 epochs): ~0.16% decay

### Fee Mechanism

```solidity
function _transfer(address sender, address recipient, uint256 amount) internal override {
    // 1. Apply decay first
    _beforeTokenTransfer(sender, recipient, amount);
    
    uint256 senderBalance = _balances[sender];
    if (senderBalance < amount) revert BERA_RESERVE__TRANSFER_AMOUNT_EXCEEDS_BALANCE();
    _balances[sender] -= amount;
    
    // 2. Apply fees (if not excluded)
    if (!isExcludedAccountsFromFees[sender] || !isExcludedAccountsFromFees[recipient] || !isFeeDisabled) {
        
        if (sender == uniswapV2Pair) {
            // BUY: Apply flat buy fee
            amount = _applyFee(sender, amount, buyFee);
            
        } else if (recipient == uniswapV2Pair) {
            // SELL: Check for sliding scale fee
            TreasuryValueData memory rvfData = BeraReserveTokenUtils.calculateSlidingScaleFee(
                marketCap, treasuryValue, sellFee,
                tenPercentBelowFees, twentyFivePercentBelowFees, belowTreasuryValueFees
            );
            
            if (rvfData.treasuryPercentage == 0) {
                // Normal sell fee
                amount = _applyFee(sender, amount, rvfData.fee);
            } else {
                // Sliding scale: split between treasury and burn
                (uint256 fee, uint256 treasuryFee, uint256 burnFee) = BeraReserveTokenUtils.applySlidingScaleFee(...);
                
                if (treasuryFee != 0) {
                    _balances[protocolTreasuryAddress] += treasuryFee;
                }
                if (burnFee != 0) {
                    _totalSupply -= burnFee;
                }
                amount -= fee;
            }
        }
    }
    
    // 3. Credit recipient
    _balances[recipient] += amount;
    lastTimeReceived[recipient] = uint48(block.timestamp);
    
    emit Transfer(sender, recipient, amount);
}

function _applyFee(address payer, uint256 amount, uint256 fee) internal returns (uint256) {
    uint256 feeAmount = amount.mulDiv(fee, BPS);
    _balances[feeDistributor] += feeAmount;
    emit Transfer(payer, feeDistributor, feeAmount);
    return amount - feeAmount;
}
```

### Sliding Scale Fee Logic

When market cap falls below treasury value:

| Condition | Fee | Distribution |
|-----------|-----|--------------|
| MC > Treasury Value | `sellFee` (3%) | To fee distributor |
| MC ≤ Treasury Value | `belowTreasuryValueFees` | 50% treasury, 50% burn |
| MC ≤ 90% of TV | `tenPercentBelowFees` | 50% treasury, 50% burn |
| MC ≤ 75% of TV | `twentyFivePercentBelowFees` | 50% treasury, 50% burn |

### Admin Functions

```solidity
// Fee Configuration
function setBuyFee(uint256 _buyFee) external onlyRole(DEFAULT_ADMIN_ROLE);
function setSellFee(uint256 _sellFee) external onlyRole(DEFAULT_ADMIN_ROLE);
function setFeeDisabled(bool _isFeeDisabled) external onlyRole(DEFAULT_ADMIN_ROLE);
function setFeeDistributor(address _feeDistributor) external onlyRole(DEFAULT_ADMIN_ROLE);

// Sliding Scale Fees
function setTwentyFivePercentBelowFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE);
function setTenPercentBelowFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE);
function setBelowTreasuryValueFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE);

// Decay Configuration
function setDecayRatio(uint256 _decayRatio) external onlyRole(DEFAULT_ADMIN_ROLE);
function setDecayInterval(uint256 _decayInterval) external onlyRole(DEFAULT_ADMIN_ROLE);

// Market Data (for sliding fee calculation)
function setTreasuryValue(uint256 _treasuryValue) external onlyRole(DEFAULT_ADMIN_ROLE);
function setMarketCap(uint256 _marketCap) external onlyRole(DEFAULT_ADMIN_ROLE);

// Exclusions
function excludeAccountFromFeesAndDecay(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE);
function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external;
function excludeMultipleAccountsFromDecay(address[] calldata accounts, bool excluded) external;

// Staking integration
function updateLastStakedTime(address _staker) external onlyStaking;
function updateUniswapV2Pair(address newPair) external onlyRole(DEFAULT_ADMIN_ROLE);
```

---

## sBRR Token - Rebasing Mechanics

### Contract: `sBeraReserve` (`src/sBeraReserveERC20.sol`)

The staked BRR token that automatically increases in balance through rebasing.

### Key Concept: Gons

Gons are the internal accounting unit. When you stake BRR:
1. Your BRR is converted to a fixed number of gons
2. `_gonsPerFragment` decreases with each rebase
3. Your balance increases: `balance = gons / _gonsPerFragment`

```solidity
// Constants
uint256 private constant MAX_UINT256 = ~uint256(0);
uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10 ** 9;  // 5M sBRR
uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
uint256 private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

// State
uint256 private _gonsPerFragment;
mapping(address => uint256) private _gonBalances;
uint256 public INDEX;  // Tracks cumulative rebase growth
```

### Initialization

```solidity
constructor() ERC20("Staked Bera Reserve", "sBRR", 9) ERC20Permit() {
    initializer = msg.sender;
    _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
    _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
}

function initialize(address stakingContract_) external returns (bool) {
    require(msg.sender == initializer);
    require(stakingContract_ != address(0));
    
    stakingContract = stakingContract_;
    _gonBalances[stakingContract] = TOTAL_GONS;  // All gons start in staking
    
    emit Transfer(address(0x0), stakingContract, _totalSupply);
    initializer = address(0);  // One-time initialization
    return true;
}

function setIndex(uint256 _INDEX) external onlyManager returns (bool) {
    require(INDEX == 0);  // Can only set once
    INDEX = gonsForBalance(_INDEX);
    return true;
}
```

### Rebase Function

Called by staking contract to distribute rewards:

```solidity
function rebase(uint256 profit_, uint256 epoch_) public onlyStakingContract returns (uint256) {
    uint256 rebaseAmount;
    uint256 circulatingSupply_ = circulatingSupply();
    
    if (profit_ == 0) {
        emit LogSupply(epoch_, block.timestamp, _totalSupply);
        emit LogRebase(epoch_, 0, index());
        return _totalSupply;
    }
    
    // Calculate rebase amount proportional to circulating supply
    if (circulatingSupply_ > 0) {
        rebaseAmount = profit_.mul(_totalSupply).div(circulatingSupply_);
    } else {
        rebaseAmount = profit_;
    }
    
    // Increase total supply
    _totalSupply = _totalSupply.add(rebaseAmount);
    if (_totalSupply > MAX_SUPPLY) {
        _totalSupply = MAX_SUPPLY;
    }
    
    // Decrease gonsPerFragment (this increases all balances!)
    _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
    
    // Store rebase history
    _storeRebase(circulatingSupply_, profit_, epoch_);
    
    return _totalSupply;
}
```

**Rebase Math Example:**
```
Before Rebase:
- Total Supply: 1,000,000 sBRR
- User A gons: 1,000,000 gons
- gonsPerFragment: 1,000,000
- User A balance: 1,000,000 / 1,000,000 = 1 sBRR

Profit distributed: 100,000 BRR
New Total Supply: 1,100,000 sBRR
New gonsPerFragment: TOTAL_GONS / 1,100,000

After Rebase:
- User A gons: 1,000,000 gons (unchanged!)
- User A balance: 1,000,000 / new_gonsPerFragment = 1.1 sBRR (10% increase)
```

### Balance Calculations

```solidity
function balanceOf(address who) public view override returns (uint256) {
    return _gonBalances[who].div(_gonsPerFragment);
}

function gonsForBalance(uint256 amount) public view returns (uint256) {
    return amount.mul(_gonsPerFragment);
}

function balanceForGons(uint256 gons) public view returns (uint256) {
    return gons.div(_gonsPerFragment);
}

// Circulating = Total - Staking Contract Holdings
function circulatingSupply() public view returns (uint256) {
    return _totalSupply.sub(balanceOf(stakingContract));
}

// Index tracks cumulative growth
function index() public view returns (uint256) {
    return balanceForGons(INDEX);
}
```

### Transfer Functions

```solidity
function transfer(address to, uint256 value) public override returns (bool) {
    require(_gonBalances[msg.sender].div(_gonsPerFragment) >= value, "!NOT_ENOUGH");
    
    uint256 gonValue = gonsForBalance(value);
    _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
    _gonBalances[to] = _gonBalances[to].add(gonValue);
    
    emit Transfer(msg.sender, to, value);
    return true;
}

function transferFrom(address from, address to, uint256 value) public override returns (bool) {
    require(_gonBalances[from].div(_gonsPerFragment) >= value, "!NOT_ENOUGH");
    
    _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
    emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);
    
    uint256 gonValue = gonsForBalance(value);
    _gonBalances[from] = _gonBalances[from].sub(gonValue);
    _gonBalances[to] = _gonBalances[to].add(gonValue);
    
    emit Transfer(from, to, value);
    return true;
}
```

### Rebase History

```solidity
struct Rebase {
    uint256 epoch;              // Epoch number
    uint256 rebase;             // Rebase percentage (18 decimals)
    uint256 totalStakedBefore;  // Circulating before
    uint256 totalStakedAfter;   // Circulating after
    uint256 amountRebased;      // BRR distributed
    uint256 index;              // New index
    uint256 blockNumberOccured; // Block number
}

Rebase[] public rebases;

function _storeRebase(uint256 previousCirculating_, uint256 profit_, uint256 epoch_) internal {
    uint256 rebasePercent = profit_.mul(1e18).div(previousCirculating_);
    
    rebases.push(Rebase({
        epoch: epoch_,
        rebase: rebasePercent,
        totalStakedBefore: previousCirculating_,
        totalStakedAfter: circulatingSupply(),
        amountRebased: profit_,
        index: index(),
        blockNumberOccured: block.number
    }));
    
    emit LogSupply(epoch_, block.timestamp, _totalSupply);
    emit LogRebase(epoch_, rebasePercent, index());
}

function getRebasesLength() public view returns (uint256) {
    return rebases.length;
}
```

---

## Bonding System

### Contract: `BeraReserveBondDepositoryV2` (`src/BeraReserveBondDepositoryV2.sol`)

Allows users to purchase BRR at a discount by depositing USDC or LP tokens.

### Inheritance
```
BeraReserveBondDepositoryV2
├── Ownable2Step (OpenZeppelin)
│   └── Ownable
└── Pausable (OpenZeppelin)
```

### Constants
```solidity
uint256 private constant BPS = 10_000;              // Basis points
uint256 public constant MINIMUM_PAYOUT = 10_000_000; // 0.01 BRR minimum (10M in 9 decimals)
uint256 private constant PRECISION = 1e18;           // For price calculations
```

### Immutables (Set in Constructor)
```solidity
address public immutable principle;       // USDC or LP token address
bool public immutable isLiquidityBond;    // true if LP bond, false if reserve bond
address public immutable bondCalculator;  // LP valuation calculator (null for reserve bonds)
address public immutable treasury;        // Treasury address
address public immutable BRR;             // BRR token address
```

### State Variables
```solidity
mapping(address => Bond) public bondInfo;  // User bond records
Terms public terms;                        // Current bond terms
address public dao;                        // Receives bond fees
uint256 public totalDebt;                  // Total outstanding bonds
IBeraReserveUniswapV2TwapOracle public twap; // TWAP oracle for pricing
```

### Constructor
```solidity
constructor(
    address _brr,
    address _principle,
    address _treasury,
    address _DAO,
    address admin,
    address _bondCalculator,  // address(0) for reserve bonds
    address _twap
) Ownable(admin) {
    // Validation
    require(_brr != address(0) && _principle != address(0) && _treasury != address(0) && _DAO != address(0) && _twap != address(0));
    
    BRR = _brr;
    principle = _principle;
    treasury = _treasury;
    dao = _DAO;
    twap = IBeraReserveUniswapV2TwapOracle(_twap);
    bondCalculator = _bondCalculator;
    isLiquidityBond = (_bondCalculator != address(0));
}
```

### Initialize Bond Terms

```solidity
function initializeBondTerms(
    uint256 _vestingTerm,    // Blocks for vesting (min 64,800 = ~36 hours)
    uint256 _maxPayout,      // Max payout % (thousandths, max 100 = 0.1%)
    uint256 _fee,            // DAO fee (hundredths, 500 = 5%)
    uint256 _discountRate,   // Discount from market (BPS, 100 = 1%)
    uint256 _maxDebt         // Maximum total debt
) external onlyOwner {
    if (terms.vestingTerm != 0) revert AlreadyInitialized();
    
    terms = Terms({
        vestingTerm: _vestingTerm,
        maxPayout: _maxPayout,
        fee: _fee,
        discountRate: _discountRate,
        maxDebt: _maxDebt
    });
    
    emit BondTermsInitialized(_vestingTerm, _maxPayout, _fee, _discountRate, _maxDebt);
}
```

### Core Deposit Function

```solidity
function deposit(uint256 amount, uint256 maxPriceInHoney) external whenNotPaused returns (uint256 payoutAfterFee) {
    // 1. Validate inputs
    if (amount == 0) revert InvalidAmount();
    if (maxPriceInHoney == 0) revert InvalidMaxPrice();
    
    // 2. Calculate payout and price
    (uint256 payOut, uint256 discountedPriceInHoney) = valueOf(principle, amount);
    
    // 3. Validate constraints
    if (totalDebt + payOut > terms.maxDebt) revert BondSoldOut();
    if (discountedPriceInHoney > maxPriceInHoney) revert SlippageLimitExceeded();
    if (payOut < MINIMUM_PAYOUT) revert BondTooSmall();  // > 0.01 BRR
    if (payOut > maxPayout()) revert BondTooLarge();
    
    // 4. Transfer principle from user
    IERC20(principle).safeTransferFrom(msg.sender, address(this), amount);
    
    // 5. Calculate and deduct fee
    uint256 fee = payOut.mulDiv(terms.fee, BPS);
    payoutAfterFee = payOut - fee;
    
    // 6. Deposit to treasury and mint BRR
    IERC20(principle).approve(address(treasury), amount);
    IBeraReserveTreasuryV2(treasury).deposit(amount, principle, payOut);
    
    // 7. Send fee to DAO
    if (fee != 0) {
        IERC20(BRR).safeTransfer(dao, fee);
    }
    
    // 8. Update debt
    totalDebt += payOut;
    
    // 9. Store bond info (accumulates if user has existing bond)
    bondInfo[msg.sender] = Bond({
        amountBonded: bondInfo[msg.sender].amountBonded + amount,
        payout: bondInfo[msg.sender].payout + payoutAfterFee,
        vesting: terms.vestingTerm,
        lastBlock: block.number,
        pricePaid: discountedPriceInHoney
    });
    
    emit BondCreated(amount, payoutAfterFee, block.number + terms.vestingTerm, discountedPriceInHoney);
    return payoutAfterFee;
}
```

### Price Calculation

```solidity
function valueOf(address _token, uint256 _amount) public returns (uint256 value_, uint256 discountedPriceInHoney) {
    // 1. Get current BRR price from TWAP (in HONEY, 18 decimals)
    uint256 brrPrice = twap.consult(1e9);  // Price of 1 BRR
    
    // 2. Calculate base value
    if (isLiquidityBond) {
        // LP bond: use bonding calculator
        value_ = IBeraReserveBondingCalculator(bondCalculator).valuation(_token, _amount);
    } else {
        // Reserve bond: convert decimals
        value_ = _amount.mulDiv(
            10 ** IERC20Metadata(BRR).decimals(),  // 9
            10 ** IERC20Metadata(_token).decimals() // 6 for USDC
        );
    }
    
    // 3. Apply discount
    discountedPriceInHoney = getBondPrice(brrPrice);  // Discounted price per BRR
    
    // 4. Calculate payout: value / discounted_price
    if (discountedPriceInHoney != 0) {
        value_ = value_.mulDiv(PRECISION, discountedPriceInHoney);
    }
}

function getBondPrice(uint256 price) public view returns (uint256) {
    return price.mulDiv(BPS - terms.discountRate, BPS);
}
```

**Price Calculation Example:**
```
- USDC deposited: 100 USDC (100e6)
- BRR price from TWAP: $1.00 (1e18 in HONEY)
- Discount rate: 500 (5%)

1. Base value = 100e6 * 10^9 / 10^6 = 100e9 (100 BRR worth)
2. Discounted price = 1e18 * (10000-500) / 10000 = 0.95e18 ($0.95)
3. Payout = 100e9 * 1e18 / 0.95e18 = 105.26e9 BRR

User gets 105.26 BRR for $100 (5.26% discount)
```

### Redemption Function

```solidity
function redeem() external whenNotPaused {
    Bond memory bond = bondInfo[msg.sender];
    if (bond.vesting == 0) revert NO_REDEEMABLE_BOND();
    
    uint256 percentVested = percentVestedFor(msg.sender);
    
    if (percentVested >= BPS) {
        // Fully vested - pay everything
        delete bondInfo[msg.sender];
        emit BondRedeemed(msg.sender, bond.payout, 0);
        IERC20(BRR).safeTransfer(msg.sender, bond.payout);
    } else {
        // Partially vested - pay proportional amount
        uint256 payout = bond.payout.mulDiv(percentVested, BPS);
        
        // Update bond info
        bondInfo[msg.sender].payout = bond.payout - payout;
        bondInfo[msg.sender].vesting = bond.vesting - (block.number - bond.lastBlock);
        bondInfo[msg.sender].lastBlock = block.number;
        
        emit BondRedeemed(msg.sender, payout, bondInfo[msg.sender].payout);
        IERC20(BRR).safeTransfer(msg.sender, payout);
    }
}

function percentVestedFor(address _depositor) public view returns (uint256 percentVested_) {
    Bond memory bond = bondInfo[_depositor];
    
    uint256 blocksSinceLast = block.number - bond.lastBlock;
    uint256 vesting = bond.vesting;
    
    if (vesting > 0) {
        percentVested_ = blocksSinceLast.mulDiv(BPS, vesting);
    }
}

function pendingPayoutFor(address _depositor) external view returns (uint256 pendingPayout_) {
    uint256 percentVested = percentVestedFor(_depositor);
    uint256 payout = bondInfo[_depositor].payout;
    
    if (percentVested >= 10_000) {
        pendingPayout_ = payout;
    } else {
        pendingPayout_ = payout.mulDiv(percentVested, 10_000);
    }
}
```

### Max Payout Calculation

```solidity
function maxPayout() public view returns (uint256) {
    uint256 totalAllocatedToTreasury = IBeraReserveToken(BRR).allocationLimits(treasury);
    return totalAllocatedToTreasury.mulDiv(terms.maxPayout, BPS);
}
```

### Admin Functions

```solidity
function setBondTerms(PARAMETER _parameter, uint256 _input) external onlyOwner {
    if (_parameter == PARAMETER.VESTING) {
        if (_input < 64_800) revert InvalidVestingTerm();  // Min ~36 hours
        terms.vestingTerm = _input;
    } else if (_parameter == PARAMETER.PAYOUT) {
        if (_input > 100) revert InvalidMaxPayout();  // Max 0.1%
        terms.maxPayout = _input;
    } else if (_parameter == PARAMETER.FEE) {
        if (_input > 10_000) revert InvalidFee();  // Max 100%
        terms.fee = _input;
    } else if (_parameter == PARAMETER.DISCOUNT_RATE) {
        if (_input > 10_000) revert InvalidDiscountRate();
        terms.discountRate = _input;
    } else if (_parameter == PARAMETER.MAX_DEBT) {
        terms.maxDebt = _input;
    }
    emit BondTermsUpdated(_parameter, _input);
}

function setDAO(address _dao) external onlyOwner;
function updateTwap(address _twap) external onlyOwner;
function pause() external onlyOwner;
function unpause() external onlyOwner;
function clawBackTokens(address _token, uint256 _amount) external onlyOwner;
```

### Bonding Calculator (`src/BeraReserveBondingCalculator.sol`)

Calculates the value of LP tokens for liquidity bonds:

```solidity
contract BeraReserveBondingCalculator is IBondingCalculator {
    address public immutable BRR;
    
    // Get K value (reserve0 × reserve1) normalized
    function getKValue(address _pair) public view returns (uint256 k_) {
        uint256 token0 = IERC20(IUniswapV2Pair(_pair).token0()).decimals();
        uint256 token1 = IERC20(IUniswapV2Pair(_pair).token1()).decimals();
        uint256 decimals = token0 + token1 - IERC20(_pair).decimals();
        
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(_pair).getReserves();
        k_ = (reserve0 * reserve1) / (10 ** decimals);
    }
    
    // Total value = 2 × sqrt(K) (for constant product AMM)
    function getTotalValue(address _pair) public view returns (uint256 _value) {
        _value = Babylonian.sqrt(getKValue(_pair)) * 2;
    }
    
    // Value of LP tokens = totalValue × (amount / totalSupply)
    function valuation(address _pair, uint256 amount_) external view returns (uint256 _value) {
        uint256 totalValue = getTotalValue(_pair);
        uint256 totalSupply = IUniswapV2Pair(_pair).totalSupply();
        _value = (totalValue * amount_) / totalSupply;
    }
}
```

---

## Staking System

### Contract: `BeraReserveStaking` (`src/Staking.sol`)

Manages staking of BRR for sBRR with warmup periods and epoch-based rebases.

### Immutables
```solidity
address public immutable BRR;   // BRR token
address public immutable sBRR;  // sBRR token
```

### State Variables
```solidity
uint256 public totalStaked;                    // Total BRR staked
Epoch public epoch;                            // Current epoch info
address public distributor;                    // Reward distributor
address public locker;                         // Lock bonus contract
uint256 public totalBonus;                     // Bonus from locker
address public warmupContract;                 // Holds sBRR during warmup
uint256 public warmupPeriod;                   // Epochs to wait
mapping(address => Claim) public warmupInfo;   // User warmup claims
```

### Constructor
```solidity
constructor(
    address _BRR,
    address _sBRR,
    uint256 _epochLength,      // Blocks per epoch
    uint256 _firstEpochNumber, // Starting epoch
    uint256 _firstEpochBlock   // Block when first epoch ends
) {
    require(_BRR != address(0));
    BRR = _BRR;
    require(_sBRR != address(0));
    sBRR = _sBRR;
    
    epoch = Epoch({
        length: _epochLength,
        number: _firstEpochNumber,
        endBlock: _firstEpochBlock,
        distribute: 0
    });
}
```

### Staking Flow

```solidity
function stake(uint256 _amount, address _recipient) external whenNotPaused returns (bool) {
    // 1. Trigger rebase if needed
    rebase();
    
    // 2. Update recipient's last staked time (for decay protection)
    IBR(BRR).updateLastStakedTime(_recipient);
    
    // 3. Transfer BRR from sender
    IERC20(BRR).safeTransferFrom(msg.sender, address(this), _amount);
    
    // 4. Check for deposit lock
    Claim memory info = warmupInfo[_recipient];
    require(!info.lock, "Deposits for account are locked");
    
    // 5. Update warmup info
    warmupInfo[_recipient] = Claim({
        deposit: info.deposit.add(_amount),
        gons: info.gons.add(IsBRR(sBRR).gonsForBalance(_amount)),
        expiry: epoch.number.add(warmupPeriod),
        lock: false
    });
    
    // 6. Update total staked
    totalStaked = totalStaked.add(_amount);
    
    // 7. Send sBRR to warmup contract (not user yet!)
    IERC20(sBRR).safeTransfer(warmupContract, _amount);
    
    return true;
}
```

### Claiming After Warmup

```solidity
function claim(address _recipient) public whenNotPaused {
    Claim memory info = warmupInfo[_recipient];
    
    // Only claim if warmup period has passed
    if (epoch.number >= info.expiry && info.expiry != 0) {
        delete warmupInfo[_recipient];
        
        // Transfer sBRR from warmup to recipient
        // Uses gons to account for any rebases during warmup
        IWarmup(warmupContract).retrieve(
            _recipient, 
            IsBRR(sBRR).balanceForGons(info.gons)
        );
    }
}
```

### Forfeiting Stake

```solidity
function forfeit() external whenNotPaused {
    Claim memory info = warmupInfo[msg.sender];
    delete warmupInfo[msg.sender];
    
    // Return sBRR from warmup to staking contract
    IWarmup(warmupContract).retrieve(address(this), IsBRR(sBRR).balanceForGons(info.gons));
    
    // Return original BRR deposit to user
    IERC20(BRR).safeTransfer(msg.sender, info.deposit);
}
```

### Unstaking

```solidity
function unstake(uint256 _amount, bool _trigger) external whenNotPaused {
    // Optionally trigger rebase
    if (_trigger) {
        rebase();
    }
    
    // Update total staked
    totalStaked = totalStaked.sub(_amount);
    
    // Receive sBRR from user
    IERC20(sBRR).safeTransferFrom(msg.sender, address(this), _amount);
    
    // Return BRR to user
    IERC20(BRR).safeTransfer(msg.sender, _amount);
}

// Special unstake for locker contract
function unstakeFor(address _recipient, uint256 _amount) external whenNotPaused {
    require(msg.sender == locker, "Only locker can call this function");
    
    rebase();
    totalStaked = totalStaked.sub(_amount);
    
    IERC20(sBRR).safeTransferFrom(_recipient, address(this), _amount);
    IERC20(BRR).safeTransfer(_recipient, _amount);
}
```

### Rebase Mechanism

```solidity
function rebase() public {
    // Only rebase if epoch has ended
    if (epoch.endBlock <= block.number) {
        // 1. Call sBRR rebase (distributes rewards)
        IsBRR(sBRR).rebase(epoch.distribute, epoch.number);
        
        // 2. Advance epoch
        epoch.endBlock = epoch.endBlock.add(epoch.length);
        epoch.number++;
        
        // 3. Call distributor to send new rewards
        if (distributor != address(0)) {
            IDistributor(distributor).distribute();
        }
        
        // 4. Calculate next distribution
        uint256 balance = contractBalance();
        uint256 staked = IsBRR(sBRR).circulatingSupply();
        
        if (balance <= staked) {
            epoch.distribute = 0;
        } else {
            // Distribute excess BRR held by staking contract
            epoch.distribute = balance.sub(staked);
        }
    }
}

function contractBalance() public view returns (uint256) {
    return IERC20(BRR).balanceOf(address(this)).add(totalBonus);
}

function index() public view returns (uint256) {
    return IsBRR(sBRR).index();
}
```

### Lock Bonus System

```solidity
// Locker can provide bonus sBRR
function giveLockBonus(uint256 _amount) external {
    require(msg.sender == locker);
    totalBonus = totalBonus.add(_amount);
    IERC20(sBRR).safeTransfer(locker, _amount);
}

function returnLockBonus(uint256 _amount) external {
    require(msg.sender == locker);
    totalBonus = totalBonus.sub(_amount);
    IERC20(sBRR).safeTransferFrom(locker, address(this), _amount);
}
```

### Admin Functions

```solidity
enum CONTRACTS { DISTRIBUTOR, WARMUP, LOCKER }

function setContract(CONTRACTS _contract, address _address) external onlyManager {
    if (_contract == CONTRACTS.DISTRIBUTOR) {
        distributor = _address;
    } else if (_contract == CONTRACTS.WARMUP) {
        require(warmupContract == address(0), "Warmup cannot be set more than once");
        warmupContract = _address;
    } else if (_contract == CONTRACTS.LOCKER) {
        require(locker == address(0), "Locker cannot be set more than once");
        locker = _address;
    }
}

function setWarmup(uint256 _warmupPeriod) external onlyManager {
    warmupPeriod = _warmupPeriod;
}

function toggleDepositLock() external whenNotPaused {
    warmupInfo[msg.sender].lock = !warmupInfo[msg.sender].lock;
}

function pause() external onlyManager;
function unpause() external onlyManager;
function retrieve(address token, uint256 amount) external onlyManager;
```

### Staking Distributor (`src/StakingDistributor.sol`)

Manages reward distribution rates:

```solidity
contract Distributor is Policy {
    address public immutable BRR;
    address public immutable treasury;
    uint256 public immutable epochLength;
    uint256 public nextEpochBlock;
    
    struct Info {
        uint256 rate;      // Reward rate (in millionths: 5000 = 0.5%)
        address recipient; // Staking contract
    }
    Info[] public info;
    
    struct Adjust {
        bool add;          // Increase or decrease
        uint256 rate;      // Rate of change per epoch
        uint256 target;    // Target rate
    }
    mapping(uint256 => Adjust) public adjustments;
    
    function distribute() external returns (bool) {
        if (nextEpochBlock <= block.number) {
            nextEpochBlock = nextEpochBlock.add(epochLength);
            
            for (uint256 i = 0; i < info.length; i++) {
                if (info[i].rate > 0) {
                    // Mint rewards from treasury
                    ITreasury(treasury).mintRewards(
                        info[i].recipient,
                        nextRewardAt(info[i].rate)
                    );
                    adjust(i);  // Adjust rate toward target
                }
            }
            return true;
        }
        return false;
    }
    
    function nextRewardAt(uint256 _rate) public view returns (uint256) {
        return circulatingTotalSupply().mul(_rate).div(1_000_000);
    }
    
    // Circulating = Total - 150,000 (unbacked initial supply)
    function circulatingTotalSupply() public view returns (uint256) {
        return IERC20(BRR).totalSupply().sub(150_000e9);
    }
}
```

---

## Treasury System

### TreasuryV2 (`src/BeraReserveTreasuryV2.sol`)

Simplified treasury for bond deposits:

```solidity
contract BeraReserveTreasuryV2 is IBeraReserveTreasuryV2, Ownable2Step {
    // Immutables
    IBeraReserveToken public immutable BRR_TOKEN;
    address public immutable pair;  // LP pair reference
    
    // Token type mappings
    mapping(address => bool) public isReserveToken;      // e.g., USDC
    mapping(address => bool) public isLiquidityToken;    // e.g., BRR/HONEY LP
    
    // Depositor authorization
    mapping(address => bool) public isReserveDepositor;  // Can deposit reserves
    mapping(address => bool) public isLiquidityDepositor; // Can deposit LP
    
    // Accounting
    mapping(address => uint256) public totalReserves;    // Reserves per token
    mapping(address => uint256) public totalBorrowed;    // Borrowed per token
    address public reservesManager;                       // Can borrow/repay
    
    constructor(address admin, address _brr, address _usdc, address _lp) Ownable(admin) {
        BRR_TOKEN = IBeraReserveToken(_brr);
        pair = _lp;
        isReserveToken[_usdc] = true;
        isLiquidityToken[_lp] = true;
    }
    
    function deposit(uint256 _amount, address _token, uint256 value) external returns (uint256) {
        // Validate token type
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();
        
        // Validate depositor authorization
        if (isReserveToken[_token]) {
            if (!isReserveDepositor[msg.sender]) revert InvalidReserveDepositor();
        } else {
            if (!isLiquidityDepositor[msg.sender]) revert InvalidLiquidityDepositor();
        }
        
        // Transfer tokens (approved by bond depository)
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        totalReserves[_token] += _amount;
        
        // Mint BRR to depositor (bond depository)
        BRR_TOKEN.mint(msg.sender, value);
        
        emit Deposit(_token, _amount, value);
        return value;
    }
    
    function borrowReserves(uint256 _amount, address _token) external onlyReserveManager {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();
        
        totalReserves[_token] -= _amount;
        totalBorrowed[_token] += _amount;
        
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Withdrawal(_token, _amount);
    }
    
    function repayReserves(uint256 _amount, address _token) external onlyReserveManager {
        if (!isReserveToken[_token] && !isLiquidityToken[_token]) revert InvalidToken();
        
        totalBorrowed[_token] -= _amount;
        totalReserves[_token] += _amount;
        
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit ReservesRepaid(_token, _amount);
    }
    
    // Admin setters
    function setReservesManager(address _manager) external onlyOwner;
    function setReserveDepositor(address _depositor, bool _status) external onlyOwner;
    function setLiquidityDepositor(address _depositor, bool _status) external onlyOwner;
    function setReserveToken(address _token, bool _status) external onlyOwner;
    function setLiquidityToken(address _token, bool _status) external onlyOwner;
}
```

### Treasury V1 (`src/Treasury.sol`)

Full Olympus-style treasury with queue system:

```solidity
contract BeraReserveTreasury is Ownable {
    address public immutable BRR;
    uint256 public immutable blocksNeededForQueue;
    
    // Reserve tokens (USDC, etc.)
    address[] public reserveTokens;
    mapping(address => bool) public isReserveToken;
    mapping(address => uint256) public reserveTokenQueue;
    
    // Reserve depositors (bond contracts)
    address[] public reserveDepositors;
    mapping(address => bool) public isReserveDepositor;
    mapping(address => uint256) public reserveDepositorQueue;
    
    // Reserve spenders (can burn BRR for reserves)
    address[] public reserveSpenders;
    mapping(address => bool) public isReserveSpender;
    mapping(address => uint256) public reserveSpenderQueue;
    
    // LP tokens
    address[] public liquidityTokens;
    mapping(address => bool) public isLiquidityToken;
    mapping(address => uint256) public LiquidityTokenQueue;
    mapping(address => address) public bondCalculator;  // LP → calculator
    
    // Liquidity depositors
    address[] public liquidityDepositors;
    mapping(address => bool) public isLiquidityDepositor;
    mapping(address => uint256) public LiquidityDepositorQueue;
    
    // Managers
    mapping(address => bool) public isReserveManager;
    mapping(address => bool) public isLiquidityManager;
    
    // Debtors (can borrow against sBRR)
    mapping(address => bool) public isDebtor;
    mapping(address => uint256) public debtorBalance;
    
    // Reward managers
    mapping(address => bool) public isRewardManager;
    
    // sBRR reference
    address public sBRR;
    
    // Accounting
    uint256 public totalReserves;    // Risk-free value of all assets
    uint256 public totalDebt;        // Initially 150,000 (unbacked)
    
    constructor(address _BRR, address _USDC, uint256 _blocksNeededForQueue) {
        BRR = _BRR;
        isReserveToken[_USDC] = true;
        reserveTokens.push(_USDC);
        blocksNeededForQueue = _blocksNeededForQueue;
        totalDebt = 150_000e9;  // Initially unbacked
    }
```

### Treasury V1 Core Functions

```solidity
// Deposit reserves and receive minted BRR
function deposit(uint256 _amount, address _token, uint256 _profit) external returns (uint256 send_) {
    require(isReserveToken[_token] || isLiquidityToken[_token], "Not accepted");
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    
    if (isReserveToken[_token]) {
        require(isReserveDepositor[msg.sender], "Not approved");
    } else {
        require(isLiquidityDepositor[msg.sender], "Not approved");
    }
    
    uint256 value = valueOf(_token, _amount);
    send_ = value.sub(_profit);  // Profit stays in treasury
    
    IERC20Mintable(BRR).mintToTreasury(msg.sender, send_);
    
    totalReserves = totalReserves.add(value);
    emit Deposit(_token, _amount, value);
}

// Burn BRR to withdraw reserves
function withdraw(uint256 _amount, address _token) external {
    require(isReserveToken[_token], "Not accepted");
    require(isReserveSpender[msg.sender], "Not approved");
    
    uint256 value = valueOf(_token, _amount);
    IBRRERC20(BRR).burnFrom(msg.sender, value);
    
    totalReserves = totalReserves.sub(value);
    IERC20(_token).safeTransfer(msg.sender, _amount);
}

// Borrow reserves against sBRR collateral
function incurDebt(uint256 _amount, address _token) external {
    require(isDebtor[msg.sender], "Not approved");
    require(isReserveToken[_token], "Not accepted");
    
    uint256 value = valueOf(_token, _amount);
    uint256 maximumDebt = IERC20(sBRR).balanceOf(msg.sender);
    uint256 availableDebt = maximumDebt.sub(debtorBalance[msg.sender]);
    require(value <= availableDebt, "Exceeds debt limit");
    
    debtorBalance[msg.sender] += value;
    totalDebt += value;
    totalReserves -= value;
    
    IERC20(_token).transfer(msg.sender, _amount);
}

// Repay debt with reserves
function repayDebtWithReserve(uint256 _amount, address _token) external {
    require(isDebtor[msg.sender], "Not approved");
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    
    uint256 value = valueOf(_token, _amount);
    debtorBalance[msg.sender] -= value;
    totalDebt -= value;
    totalReserves += value;
}

// Repay debt with BRR (burn)
function repayDebtWithBRR(uint256 _amount) external {
    require(isDebtor[msg.sender], "Not approved");
    IBRRERC20(BRR).burnFrom(msg.sender, _amount);
    debtorBalance[msg.sender] -= _amount;
    totalDebt -= _amount;
}

// Mint rewards for staking (only from excess reserves)
function mintRewards(address _recipient, uint256 _amount) external {
    require(isRewardManager[msg.sender], "Not approved");
    require(_amount <= excessReserves(), "Insufficient reserves");
    IERC20Mintable(BRR).mintToTreasury(_recipient, _amount);
}

// Excess = reserves - (supply - debt)
function excessReserves() public view returns (uint256) {
    return totalReserves.sub(IERC20(BRR).totalSupply().sub(totalDebt));
}

// Calculate BRR value of token amount
function valueOf(address _token, uint256 _amount) public view returns (uint256 value_) {
    if (isReserveToken[_token]) {
        // Convert decimals: USDC (6) → BRR (9)
        value_ = _amount.mul(10 ** IERC20(BRR).decimals()).div(10 ** IERC20(_token).decimals());
    } else if (isLiquidityToken[_token]) {
        value_ = IBondCalculator(bondCalculator[_token]).valuation(_token, _amount);
    }
}
```

### Treasury V1 Queue System

```solidity
// Queue a permission change
function queue(MANAGING _managing, address _address) external onlyManager returns (bool) {
    require(_address != address(0));
    
    if (_managing == MANAGING.RESERVEDEPOSITOR) {
        reserveDepositorQueue[_address] = block.number.add(blocksNeededForQueue);
    } else if (_managing == MANAGING.RESERVESPENDER) {
        reserveSpenderQueue[_address] = block.number.add(blocksNeededForQueue);
    } else if (_managing == MANAGING.RESERVETOKEN) {
        reserveTokenQueue[_address] = block.number.add(blocksNeededForQueue);
    } else if (_managing == MANAGING.RESERVEMANAGER) {
        ReserveManagerQueue[_address] = block.number.add(blocksNeededForQueue.mul(2));  // 2x delay
    }
    // ... similar for other types
    
    emit ChangeQueued(_managing, _address);
    return true;
}

// Toggle permission after queue expires
function toggle(MANAGING _managing, address _address, address _calculator) external onlyManager returns (bool) {
    require(_address != address(0));
    bool result;
    
    if (_managing == MANAGING.RESERVEDEPOSITOR) {
        if (requirements(reserveDepositorQueue, isReserveDepositor, _address)) {
            reserveDepositorQueue[_address] = 0;
            if (!listContains(reserveDepositors, _address)) {
                reserveDepositors.push(_address);
            }
        }
        result = !isReserveDepositor[_address];
        isReserveDepositor[_address] = result;
    }
    // ... similar for other types
    
    emit ChangeActivated(_managing, _address, result);
    return true;
}

function requirements(
    mapping(address => uint256) storage queue_,
    mapping(address => bool) storage status_,
    address _address
) internal view returns (bool) {
    if (!status_[_address]) {
        require(queue_[_address] != 0, "Must queue");
        require(queue_[_address] <= block.number, "Queue not expired");
        return true;
    }
    return false;
}
```

---

## Vesting & Lockup

### Contract: `BeraReserveLockUp` (`src/BeraReserveLockUp.sol`)

Manages token vesting for team, marketing, and seed investors with different schedules.

### Inheritance
```
BeraReserveLockUp
├── Ownable2Step (OpenZeppelin)
│   └── Ownable
└── IBeraReserveLockUp (interface)
```

### Constants
```solidity
uint256 public constant DENOMINATOR = 10_000;  // For percentage calculations
uint32 public constant TEAM_VESTING_DURATION = 365 days;
uint32 public constant TEAM_VESTING_CLIFF = 90 days;
uint32 public constant MARKETING_VESTING_DURATION = 365 days;
uint32 public constant SEED_ROUND_VESTING_DURATION = 180 days;
```

### Immutables
```solidity
IERC20 public immutable sBRR;                        // sBRR token
IBeraReserveStaking public immutable stakingContract; // Staking reference
```

### State Variables
```solidity
uint256 public tgeTimestamp;     // Token Generation Event timestamp
bool public isTGEunlocked;       // Whether TGE has occurred

mapping(address => VestingSchedule) public vestingSchedules;
mapping(address => MemberType) public memberTypes;
```

### Vesting Parameters by Type

| Type | Duration | Cliff | TGE Unlock |
|------|----------|-------|------------|
| TEAM | 365 days | 90 days | 0% |
| MARKETING | 365 days | 0 days | 0% |
| SEED | 180 days | 0 days | 30% |

### Admin: Locking sBRR for Investors

```solidity
function lockSbrrFor(
    address[] calldata investors,
    uint256[] calldata amounts,
    MemberType memberType
) external onlyOwner {
    if (investors.length != amounts.length) revert ArrayLengthMismatch();
    if (isTGEunlocked) revert TGEAlreadyHappened();
    
    for (uint256 i = 0; i < investors.length; i++) {
        address investor = investors[i];
        uint256 amount = amounts[i];
        
        if (investor == address(0)) revert InvalidAddress();
        if (vestingSchedules[investor].totalAmount != 0) revert InvestorAlreadyAdded();
        
        // Transfer sBRR from owner to this contract
        sBRR.safeTransferFrom(msg.sender, address(this), amount);
        
        // Set member type
        memberTypes[investor] = memberType;
        
        // Create vesting schedule (cliff/duration set at TGE)
        vestingSchedules[investor] = VestingSchedule({
            totalAmount: amount,
            amountClaimed: 0,
            startTime: 0,          // Set at TGE
            vestingDuration: 0,    // Set at TGE
            cliffDuration: 0,      // Set at TGE
            initialUnlockPercent: 0 // Set at TGE
        });
        
        emit TokensLocked(investor, amount, memberType);
    }
}
```

### TGE Unlock

```solidity
function unlockTGE() external onlyOwner {
    if (isTGEunlocked) revert TGEAlreadyHappened();
    
    tgeTimestamp = block.timestamp;
    isTGEunlocked = true;
    
    emit TGEUnlocked(tgeTimestamp);
}
```

### User Claiming Function

```solidity
function unlockSbrr() external {
    if (!isTGEunlocked) revert TGENotHappenedYet();
    
    VestingSchedule storage schedule = vestingSchedules[msg.sender];
    if (schedule.totalAmount == 0) revert NoVestingSchedule();
    
    // Initialize vesting parameters on first claim
    if (schedule.startTime == 0) {
        _initializeVestingParams(msg.sender);
    }
    
    uint256 claimable = _calculateClaimable(msg.sender);
    if (claimable == 0) revert NothingToClaim();
    
    // Update claimed amount
    schedule.amountClaimed += claimable;
    
    // Transfer sBRR to user
    sBRR.safeTransfer(msg.sender, claimable);
    
    emit TokensClaimed(msg.sender, claimable);
}
```

### Vesting Timeline Examples

**Team Member (1000 sBRR):**
```
Day 0 (TGE):     0 sBRR claimable (cliff)
Day 90 (Cliff):  246.58 sBRR claimable (90/365 of total)
Day 180:         493.15 sBRR claimable
Day 365:         1000 sBRR claimable (fully vested)
```

**Seed Investor (1000 sBRR):**
```
Day 0 (TGE):     300 sBRR claimable (30% TGE)
Day 90:          650 sBRR claimable (300 + 350 linear)
Day 180:         1000 sBRR claimable (fully vested)
```

---

### Contract: `BeraReservePreSaleBond` (`src/BeraReservePreSaleBond.sol`)

Whitelist-based pre-sale allowing early investors to purchase BRR at a fixed price.

### Constants
```solidity
uint256 private constant PRESALE_BRR_PRICE = 1e18;  // $1.00 in USDC (18 decimals)
uint256 private constant BPS = 10_000;               // Basis points
uint256 public constant PRESALE_DURATION = 5 days;
uint256 public constant VESTING_DURATION_IN_BLOCKS = 432_000;  // ~5 days
uint256 public constant PRE_BOND_SALE_TOTAL_BRR_AMOUNT = 50_000e9;
uint128 public bondPurchaseLimit = 2_500e9;  // Max per wallet
uint128 public tokenPrice = 2e17;             // $0.20
```

### State Variables
```solidity
bytes32 public merkleRoot;                // Whitelist Merkle root
uint256 public maxBRRAllocation;          // Max BRR available (50,000)
uint256 public totalBrrPurchased;         // Total BRR sold
uint256 public maxAllocationPerInvestor;  // Per-user cap
uint256 public presaleStartTime;          // Start timestamp
address public treasury;                  // Receives USDC

PreSaleBondState public bondState;        // NOTSTARTED, STARTED, ENDED
mapping(address => InvestorBondInfo) public investorBondInfo;
```

### Pre-Sale States
```solidity
enum PreSaleBondState { NOTSTARTED, STARTED, ENDED }
```

### Purchase Function

```solidity
function purchaseBRR(
    uint256 usdcAmount,
    bytes32[] calldata merkleProof
) external whenNotPaused {
    // 1. Validate state
    if (bondState != PreSaleBondState.STARTED) revert InvalidState();
    if (block.timestamp > presaleStartTime + PRESALE_DURATION) revert PresaleEnded();
    
    // 2. Verify whitelist using Merkle proof
    if (!isWhitelisted(msg.sender, merkleProof)) revert NotWhitelisted();
    
    // 3. Calculate BRR amount
    uint256 brrAmount = (usdcAmount * 1e9) / PRESALE_BRR_PRICE;
    
    // 4. Check allocation limits
    InvestorBondInfo storage info = investorBondInfo[msg.sender];
    if (info.brrPurchased + brrAmount > maxAllocationPerInvestor) 
        revert ExceedsMaxAllocation();
    if (totalBrrPurchased + brrAmount > maxBRRAllocation) 
        revert ExceedsTotalAllocation();
    
    // 5. Transfer USDC from user to treasury
    usdc.safeTransferFrom(msg.sender, treasury, usdcAmount);
    
    // 6. Update bond info with vesting schedule
    if (info.vestingStartBlock == 0) {
        info.vestingStartBlock = block.number;
        info.vestingEndBlock = block.number + VESTING_DURATION_IN_BLOCKS;
    }
    info.amountDeposited += usdcAmount;
    info.brrPurchased += brrAmount;
    totalBrrPurchased += brrAmount;
    
    // 7. Mint BRR to this contract (for vesting)
    brr.mint(address(this), brrAmount);
    
    emit BondPurchased(msg.sender, usdcAmount, brrAmount);
}
```

### Whitelist Verification

```solidity
function isWhitelisted(
    address user,
    bytes32[] calldata merkleProof
) public view returns (bool) {
    bytes32 leaf = keccak256(abi.encodePacked(user));
    return MerkleProof.verify(merkleProof, merkleRoot, leaf);
}
```

### Claiming Function

```solidity
function claimBRR() external whenNotPaused {
    if (bondState != PreSaleBondState.ENDED) revert InvalidState();
    
    InvestorBondInfo storage info = investorBondInfo[msg.sender];
    if (info.brrPurchased == 0) revert NoBondExists();
    
    uint256 claimable = calculateClaimable(msg.sender);
    if (claimable == 0) revert NothingToClaim();
    
    info.claimedBrr += claimable;
    
    brr.transfer(msg.sender, claimable);
    
    emit BondClaimed(msg.sender, claimable);
}

function calculateClaimable(address investor) public view returns (uint256) {
    InvestorBondInfo memory info = investorBondInfo[investor];
    
    if (info.brrPurchased == 0) return 0;
    if (bondState != PreSaleBondState.ENDED) return 0;
    
    uint256 currentBlock = block.number;
    
    if (currentBlock >= info.vestingEndBlock) {
        // Fully vested
        return info.brrPurchased - info.claimedBrr;
    }
    
    // Linear vesting
    uint256 totalBlocks = info.vestingEndBlock - info.vestingStartBlock;
    uint256 elapsedBlocks = currentBlock - info.vestingStartBlock;
    
    uint256 totalVested = (info.brrPurchased * elapsedBlocks) / totalBlocks;
    
    return totalVested - info.claimedBrr;
}
```

---

## Fee Distribution

### Contract: `BeraReserveFeeDistributor` (`src/BeraReserveFeeDistributor.sol`)

Distributes protocol fees from token transfers to team, POL, and treasury.

### Constants
```solidity
uint256 public constant TEAM_FEE = 3_300;      // 33%
uint256 public constant POL_FEE = 3_300;       // 33%
uint256 public constant TREASURY_FEE = 3_400;  // 34%
uint256 public constant BPS = 10_000;
```

### State Variables
```solidity
address public teamWallet;
address public polWallet;     // Protocol-Owned Liquidity
address public treasury;
```

### Distribution Function

```solidity
function distributeFees(address _feeToken) external {
    uint256 balance = IERC20(_feeToken).balanceOf(address(this));
    if (balance == 0) revert NoFeesToDistribute();
    
    // Calculate shares
    uint256 teamShare = (balance * TEAM_FEE) / BPS;
    uint256 polShare = (balance * POL_FEE) / BPS;
    uint256 treasuryShare = balance - teamShare - polShare;  // Remainder to treasury
    
    // Transfer to recipients
    if (teamShare > 0) {
        IERC20(_feeToken).safeTransfer(teamWallet, teamShare);
    }
    if (polShare > 0) {
        IERC20(_feeToken).safeTransfer(polWallet, polShare);
    }
    if (treasuryShare > 0) {
        IERC20(_feeToken).safeTransfer(treasury, treasuryShare);
    }
    
    emit FeesDistributed(_feeToken, teamShare, polShare, treasuryShare);
}
```

### Integration with BRR Token

The BRR token's `_update` function sends fees to the FeeDistributor:

```solidity
// In BeraReserveToken._update():
if (feeAmount > 0 && feeDistributor != address(0)) {
    super._update(from, feeDistributor, feeAmount);
}
```

Anyone can then call `distributeFees(address(BRR))` to split accumulated fees.

---

## Oracle System

### Contract: `BeraReserveUniswapV2TwapOracle` (`src/utils/BeraReserveUniswapV2TwapOracle.sol`)

Provides time-weighted average price (TWAP) for BRR pricing in bonds.

### Constants
```solidity
uint32 public constant PERIOD = 1 hours;  // TWAP window
```

### Immutables
```solidity
IUniswapV2Pair public immutable pair;
address public immutable token0;
address public immutable token1;
```

### State Variables
```solidity
uint256 public price0CumulativeLast;
uint256 public price1CumulativeLast;
uint32 public blockTimestampLast;
FixedPoint.uq112x112 public price0Average;
FixedPoint.uq112x112 public price1Average;
```

### Update Function

```solidity
function update() external {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = 
        UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    
    uint32 timeElapsed = blockTimestamp - blockTimestampLast;
    
    // Require at least 1 hour between updates
    require(timeElapsed >= PERIOD, "Period not elapsed");
    
    // Calculate TWAP: (current_cumulative - last_cumulative) / time_elapsed
    price0Average = FixedPoint.uq112x112(
        uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
    );
    price1Average = FixedPoint.uq112x112(
        uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
    );
    
    // Store current values for next update
    price0CumulativeLast = price0Cumulative;
    price1CumulativeLast = price1Cumulative;
    blockTimestampLast = blockTimestamp;
}
```

### Consult Function

```solidity
function consult(uint256 amountIn) external returns (uint256 amountOut) {
    // Auto-update if period elapsed
    (,, uint32 blockTimestamp) = pair.getReserves();
    if (blockTimestamp - blockTimestampLast >= PERIOD) {
        update();
    }
    
    // Return price based on which token is being queried
    // If BRR is token0, use price0Average (BRR → token1 price)
    amountOut = price0Average.mul(amountIn).decode144();
}
```

### TWAP Math Explanation

```
TWAP Window: 1 hour
Pair: BRR/HONEY

At time T0: price0Cumulative = 1000, blockTimestamp = 0
At time T1 (1 hour later): price0Cumulative = 4600, blockTimestamp = 3600

TWAP = (4600 - 1000) / 3600 = 1.0 (price of 1 BRR in HONEY)

This protects against flash loan manipulation by averaging over time.
```

---

## Contract Interactions

### Staking Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         STAKING FLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  User                                                            │
│    │                                                             │
│    │ stake(amount)                                               │
│    ▼                                                             │
│  [BeraReserveStaking]                                           │
│    │                                                             │
│    ├──► rebase() ───► [sBRR.rebase()]                           │
│    │                      │                                      │
│    │                      ▼                                      │
│    │               [StakingDistributor]                          │
│    │                      │                                      │
│    │                      ▼                                      │
│    │               [Treasury.mintRewards()]                      │
│    │                                                             │
│    ├──► BRR.updateLastStakedTime(user)                          │
│    │                                                             │
│    ├──► BRR.transferFrom(user, staking, amount)                 │
│    │                                                             │
│    ├──► warmupInfo[user].gons += gonsForBalance(amount)         │
│    │                                                             │
│    └──► sBRR.transfer(warmupContract, amount)                   │
│                                                                  │
│  [After warmupPeriod epochs]                                    │
│                                                                  │
│  User                                                            │
│    │                                                             │
│    │ claim()                                                     │
│    ▼                                                             │
│  [StakingWarmup]                                                │
│    │                                                             │
│    └──► sBRR.transfer(user, balanceForGons(gons))               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Bonding Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         BONDING FLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  User                                                            │
│    │                                                             │
│    │ deposit(usdcAmount, maxPrice)                              │
│    ▼                                                             │
│  [BeraReserveBondDepositoryV2]                                  │
│    │                                                             │
│    ├──► twap.consult(1e9) ───► Get BRR price in HONEY           │
│    │                                                             │
│    ├──► Calculate discounted price                               │
│    │      price = brrPrice * (10000 - discountRate) / 10000     │
│    │                                                             │
│    ├──► Calculate payout                                         │
│    │      payout = usdcValue * 1e18 / discountedPrice           │
│    │                                                             │
│    ├──► USDC.transferFrom(user, depository, amount)             │
│    │                                                             │
│    ├──► USDC.approve(treasury, amount)                          │
│    │                                                             │
│    ├──► Treasury.deposit(amount, USDC, payout)                  │
│    │           │                                                 │
│    │           └──► BRR.mint(depository, payout)                │
│    │                                                             │
│    ├──► BRR.transfer(dao, fee)                                  │
│    │                                                             │
│    └──► Store bondInfo[user] with vesting                       │
│                                                                  │
│  [After vesting period]                                          │
│                                                                  │
│  User                                                            │
│    │                                                             │
│    │ redeem()                                                    │
│    ▼                                                             │
│  [BeraReserveBondDepositoryV2]                                  │
│    │                                                             │
│    ├──► Calculate percentVested                                  │
│    │                                                             │
│    └──► BRR.transfer(user, vestedAmount)                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Fee Collection Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      FEE COLLECTION FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Any BRR Transfer                                                │
│    │                                                             │
│    ▼                                                             │
│  [BeraReserveToken._update()]                                   │
│    │                                                             │
│    ├──► Check if fee exempt                                      │
│    │                                                             │
│    ├──► Calculate fee (sliding scale + decay)                   │
│    │                                                             │
│    └──► BRR.transfer(feeDistributor, feeAmount)                 │
│                                                                  │
│  Anyone                                                          │
│    │                                                             │
│    │ distributeFees(BRR)                                         │
│    ▼                                                             │
│  [BeraReserveFeeDistributor]                                    │
│    │                                                             │
│    ├──► 33% ───► teamWallet                                     │
│    │                                                             │
│    ├──► 33% ───► polWallet                                      │
│    │                                                             │
│    └──► 34% ───► treasury                                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Rebase Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         REBASE FLOW                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [Block reaches epoch.endBlock]                                 │
│    │                                                             │
│    ▼                                                             │
│  Anyone calls rebase() on Staking                               │
│    │                                                             │
│    ├──► sBRR.rebase(distribute, epochNumber)                    │
│    │         │                                                   │
│    │         ├──► Increase _totalSupply                         │
│    │         │                                                   │
│    │         └──► Decrease _gonsPerFragment                     │
│    │              (all balances increase!)                       │
│    │                                                             │
│    ├──► Advance epoch (number++, endBlock += length)            │
│    │                                                             │
│    ├──► Distributor.distribute()                                │
│    │         │                                                   │
│    │         └──► Treasury.mintRewards(staking, amount)         │
│    │                                                             │
│    └──► Calculate next epoch.distribute                         │
│         distribute = contractBalance - circulatingSupply        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Dependency Graph

```
                    ┌──────────────────┐
                    │    BRR Token     │
                    │ (BeraReserveToken)│
                    └────────┬─────────┘
                             │ MINTER_ROLE
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   Treasury   │  │    Staking   │  │BondDepository│
    │ (V1 or V2)   │  │              │  │     V2       │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
           │         ┌───────┴───────┐         │
           │         │               │         │
           ▼         ▼               ▼         │
    ┌──────────┐  ┌──────────┐  ┌──────────┐  │
    │   USDC   │  │   sBRR   │  │  Warmup  │  │
    │ (reserve)│  │(staked)  │  │          │  │
    └──────────┘  └──────────┘  └──────────┘  │
                                              │
                               ┌──────────────┴──────────────┐
                               │                             │
                               ▼                             ▼
                        ┌──────────────┐              ┌──────────────┐
                        │    TWAP      │              │   Bonding    │
                        │   Oracle     │              │  Calculator  │
                        └──────────────┘              └──────────────┘
```

---

## Development Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/)
- Node.js (for package.json dependencies)

### Installation

```bash
# Clone repository
git clone <repo-url>
cd BeraReserve-contracts-main

# Install dependencies
forge install

# Build contracts
forge build
```

### Environment Variables

Create a `.env` file:
```env
BERACHAIN_RPC_URL=<your-rpc-url>
BEPOLIA_RPC_URL=<testnet-rpc-url>
BERASCAN_API_KEY=<api-key>
PRIVATE_KEY=<deployer-private-key>
```

### Configuration (`foundry.toml`)

```toml
[profile.default]
src = 'src'
out = 'out'
optimizer = false
evm_version = 'shanghai'
auto_detect_solc = true
libs = ["node_modules", "lib"]

[fuzz]
runs = 1024
```

---

## Testing

### Run Tests

```bash
# All tests
forge test

# Verbose output
forge test -vvv

# Specific test file
forge test --match-path test/BeraReserveBondDepositoryV2.t.sol

# Specific test function
forge test --match-test testDeposit

# With gas report
forge test --gas-report

# Fork testing
forge test --fork-url $BERACHAIN_RPC_URL
```

### Test Files Overview

| Test File | Contract Tested |
|-----------|-----------------|
| `BeraReserveBondDepositoryV2.t.sol` | Bond Depository V2 |
| `BeraReserveFeeDistributor.t.sol` | Fee Distribution |
| `BeraReserveLockup.t.sol` | Vesting/Lockup |
| `BeraReservePreBondSale.t.sol` | Pre-sale Bonds |
| `BeraReserveStaking.t.sol` | Staking |
| `BeraReserveTreasuryV2.t.sol` | Treasury V2 |
| `BeraTokenTest.t.sol` | BRR Token |
| `Treasury.t.sol` | Treasury V1 |

### Test Setup Pattern

```solidity
// test/setup/TestSetup.sol
contract TestSetup is Test {
    BeraReserveToken public brr;
    sBeraReserveERC20 public sbrr;
    BeraReserveStaking public staking;
    
    address public admin = address(1);
    address public user1 = address(2);
    
    function setUp() public virtual {
        vm.startPrank(admin);
        // Deploy and configure contracts
        vm.stopPrank();
    }
}
```

---

## Key Constants Reference

### Basis Points (BPS)
- `10,000 BPS = 100%`
- `1,000 BPS = 10%`
- `100 BPS = 1%`
- `10 BPS = 0.1%`

### Token Decimals
- **BRR**: 9 decimals (like OHM)
- **sBRR**: 9 decimals
- **HONEY**: 18 decimals
- **USDC**: 6 decimals

### Time Constants
```solidity
// Vesting
TEAM_VESTING_DURATION = 365 days
TEAM_VESTING_CLIFF = 90 days
MARKETING_VESTING_DURATION = 365 days
SEED_ROUND_VESTING_DURATION = 180 days
PRE_BOND_SALE_VESTING_DURATION = 5 days
VESTING_DURATION_IN_BLOCKS = 432_000 (~5 days at 1 block/sec)

// Oracle
TWAP_PERIOD = 1 hours

// Decay
DEFAULT_DECAY_INTERVAL = 28800 seconds (8 hours)

// Bonding
MIN_VESTING_TERM = 64,800 blocks (~36 hours)
```

### Token Constants
```solidity
// sBRR
INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10**9;  // 5M sBRR
TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
MAX_SUPPLY = ~uint128(0);  // 2^128 - 1

// BRR
MAX_FEE = 3000;  // 30%
```

---

## Security Considerations

### Access Control Patterns

**Role-Based (AccessControl):**
```solidity
// BRR Token Roles
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

// DEFAULT_ADMIN_ROLE (bytes32(0)) can:
// - Grant/revoke all roles
// - Set fee parameters
// - Configure exemptions
```

**Two-Step Ownership (Ownable2Step):**
```solidity
// Step 1: Current owner calls
transferOwnership(newOwner);

// Step 2: New owner accepts
acceptOwnership();

// Prevents accidental transfers to wrong addresses
```

**Contracts Using Ownable2Step:**
- BeraReserveBondDepositoryV2
- BeraReserveTreasuryV2
- BeraReserveFeeDistributor
- BeraReserveLockUp
- BeraReservePreSaleBond

### Pausability

```solidity
// Pausable contracts
function pause() external onlyOwner { _pause(); }
function unpause() external onlyOwner { _unpause(); }

// Protected functions use modifier
function deposit(...) external whenNotPaused { ... }
function redeem() external whenNotPaused { ... }
```

**Pausable Contracts:**
- BeraReserveBondDepositoryV2
- BeraReserveStaking
- BeraReservePreSaleBond

### Key Security Patterns

| Pattern | Purpose | Used In |
|---------|---------|---------|
| **SafeERC20** | Safe token transfers | All contracts |
| **ReentrancyGuard** | Prevent reentrancy | Staking, Treasury |
| **Slippage Protection** | `maxPriceInHoney` | BondDepository |
| **Debt Ceiling** | `maxDebt` limit | BondDepository |
| **Allocation Limits** | Per-minter caps | BRR Token |
| **Queue System** | Time-delayed permissions | Treasury V1 |
| **Merkle Proofs** | Whitelist verification | PreSaleBond |

### Fee Exemptions

```solidity
// In BeraReserveToken:
mapping(address => bool) public feeExempt;

// Typically exempt:
// - Staking contract
// - Treasury
// - Bond depositories
// - Warmup contract
// - Owner/Admin
```

### Critical Limits

| Parameter | Limit | Reason |
|-----------|-------|--------|
| Max Fee | 30% | Prevent excessive fees |
| Max Payout | 0.1% of allocation | Control bond size |
| Min Vesting | 64,800 blocks | ~36 hours minimum |
| Max Discount | 100% | Prevent negative prices |
| Max Decay | Configurable | Limit holder penalties |
| TWAP Period | 1 hour | Manipulation resistance |

### Audit Scope (from `AUDIT_SCOPE.md`)

**Primary Focus:**
- `BeraReserveBondDepositoryV2.sol`
- `BeraReserveTreasuryV2.sol`
- `BeraReserveUniswapV2TwapOracle.sol`

**Known Considerations:**
- TWAP can be manipulated over long periods
- Bond pricing depends on oracle accuracy
- Fee exemptions must be carefully managed

---

## Complete Type Reference

### All Enums

```solidity
// src/types/BeraReserveTypes.sol
enum MemberType {
    TEAM,       // 0
    MARKETING,  // 1
    SEED        // 2
}

enum PreSaleBondState {
    NOTSTARTED, // 0
    STARTED,    // 1
    ENDED       // 2
}

// src/Treasury.sol
enum MANAGING {
    RESERVEDEPOSITOR,   // 0
    RESERVESPENDER,     // 1
    RESERVETOKEN,       // 2
    RESERVEMANAGER,     // 3
    LIQUIDITYDEPOSITOR, // 4
    LIQUIDITYTOKEN,     // 5
    LIQUIDITYMANAGER,   // 6
    DEBTOR,             // 7
    REWARDMANAGER,      // 8
    SBRR                // 9
}

// src/BeraReserveBondDepositoryV2.sol
enum PARAMETER {
    VESTING,       // 0
    PAYOUT,        // 1
    FEE,           // 2
    DISCOUNT_RATE, // 3
    MAX_DEBT       // 4
}

// src/Staking.sol
enum CONTRACTS {
    DISTRIBUTOR, // 0
    WARMUP,      // 1
    LOCKER       // 2
}
```

### All Structs

```solidity
// Vesting (BeraReserveLockUp)
struct VestingSchedule {
    uint256 totalAmount;
    uint256 amountClaimed;
    uint256 startTime;
    uint256 vestingDuration;
    uint256 cliffDuration;
    uint256 initialUnlockPercent;
}

// Pre-Sale (BeraReservePreSaleBond)
struct InvestorBondInfo {
    uint256 amountDeposited;
    uint256 brrPurchased;
    uint256 claimedBrr;
    uint256 vestingStartBlock;
    uint256 vestingEndBlock;
}

// Bond Depository
struct Terms {
    uint256 vestingTerm;    // Vesting blocks
    uint256 maxPayout;      // Max payout (thousandths)
    uint256 fee;            // DAO fee (hundredths)
    uint256 discountRate;   // Discount BPS
    uint256 maxDebt;        // Max total debt
}

struct Bond {
    uint256 amountBonded;   // Principal deposited
    uint256 payout;         // BRR remaining
    uint256 vesting;        // Blocks left
    uint256 lastBlock;      // Last interaction
    uint256 pricePaid;      // Price in HONEY
}

// Staking
struct Epoch {
    uint256 length;      // Blocks per epoch
    uint256 number;      // Current epoch
    uint256 endBlock;    // When epoch ends
    uint256 distribute;  // BRR to distribute
}

struct Claim {
    uint256 deposit;    // Original BRR deposit
    uint256 gons;       // Gons held
    uint256 expiry;     // Epoch when claimable
    bool lock;          // Deposit lock flag
}

// sBRR Rebase History
struct Rebase {
    uint256 epoch;              // Epoch number
    uint256 rebase;             // Rebase % (18 decimals)
    uint256 totalStakedBefore;  // Before rebase
    uint256 totalStakedAfter;   // After rebase
    uint256 amountRebased;      // BRR distributed
    uint256 index;              // New index
    uint256 blockNumberOccured; // Block number
}

// Staking Distributor
struct Info {
    uint256 rate;      // Reward rate (millionths)
    address recipient; // Staking contract
}

struct Adjust {
    bool add;          // Increase or decrease
    uint256 rate;      // Change per epoch
    uint256 target;    // Target rate
}

// Treasury V1
struct TreasuryValueData {
    uint256 totalReserves;
    uint256 totalDebt;
    uint256 totalSupply;
    uint256 excessReserves;
}
```

---

## Quick Reference - File Locations

```
src/
├── BeraReserveBondDepositoryV2.sol    # Main bond contract (V2)
├── BeraReserveBondingCalculator.sol   # LP valuation
├── BeraReserveFeeDistributor.sol      # Fee distribution
├── BeraReserveLockUp.sol              # Vesting/lockup
├── BeraReservePreBondClaims.sol       # Pre-bond claims
├── BeraReservePreSaleBond.sol         # Pre-sale bonds
├── BeraReserveToken.sol               # BRR token
├── BeraReserveTreasuryV2.sol          # Treasury V2
├── sBeraReserveERC20.sol              # sBRR staking token
├── Staking.sol                        # Staking contract
├── StakingDistributor.sol             # Reward distribution
├── StakingDistributorV2.sol           # Distributor V2
├── Treasury.sol                       # Treasury V1
├── VaultOwned.sol                     # Vault ownership
├── wETHBondDepository.sol             # wETH bonds
├── wOHM.sol                           # Wrapped OHM
├── interfaces/
│   ├── IBeraReserveBondingCalculator.sol
│   ├── IBeraReserveFeeDistributor.sol
│   ├── IBeraReserveLockUp.sol
│   ├── IBeraReservePreBondClaims.sol
│   ├── IBeraReservePreSaleBond.sol
│   ├── IBeraReserveStaking.sol
│   └── ...
├── libs/
│   ├── Babylonian.sol        # Square root
│   ├── FixedPoint.sol        # Fixed-point math
│   ├── FullMath.sol          # Full precision math
│   └── SafeMath.sol          # Safe arithmetic
├── types/
│   └── BeraReserveTypes.sol  # Enums and structs
└── utils/
    ├── BeraReserveTokenUtils.sol         # Decay/fee utils
    └── BeraReserveUniswapV2TwapOracle.sol # TWAP oracle
```

---

## Additional Resources

- **Foundry Book**: https://book.getfoundry.sh/
- **OpenZeppelin Docs**: https://docs.openzeppelin.com/
- **Olympus DAO Docs**: https://docs.olympusdao.finance/ (original fork source)
- **Berachain Docs**: https://docs.berachain.com/
- **Uniswap V2 Docs**: https://docs.uniswap.org/contracts/v2/overview

---

*This reference document provides a comprehensive overview for studying the BeraReserve protocol. For detailed implementation specifics, refer to the source code and test files.*
