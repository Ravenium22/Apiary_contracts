# BeraReserve Contracts - Codebase Reference Guide

A comprehensive reference guide for studying the BeraReserve smart contract protocol, a DeFi protocol built on the Berachain network, forked from Olympus DAO.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Token Economics](#token-economics)
4. [Core Contracts](#core-contracts)
5. [Bonding System](#bonding-system)
6. [Staking System](#staking-system)
7. [Treasury System](#treasury-system)
8. [Vesting & Lockup](#vesting--lockup)
9. [Fee Distribution](#fee-distribution)
10. [Oracle System](#oracle-system)
11. [Contract Interactions](#contract-interactions)
12. [Development Setup](#development-setup)
13. [Testing](#testing)

---

## Project Overview

BeraReserve is a reserve currency protocol built on Berachain. It implements:
- **Bonding mechanisms** for protocol-owned liquidity (POL)
- **Staking rewards** via rebasing sBRR tokens
- **Treasury management** for backing the BRR token
- **Fee distribution** across team, POL, and treasury

### Technology Stack
- **Solidity Version**: 0.8.26
- **Framework**: Foundry
- **Target Chain**: Berachain (Chain ID: 80094)
- **Dependencies**: OpenZeppelin, Uniswap V2

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BeraReserve Protocol                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐           │
│  │  BRR Token   │◄──►│   Treasury   │◄──►│   Staking    │           │
│  │  (ERC20)     │    │   (V1/V2)    │    │   Contract   │           │
│  └──────────────┘    └──────────────┘    └──────────────┘           │
│         │                   ▲                    │                   │
│         │                   │                    │                   │
│         ▼                   │                    ▼                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐           │
│  │  Fee         │    │   Bond       │    │   sBRR Token │           │
│  │  Distributor │    │  Depository  │    │  (Rebasing)  │           │
│  └──────────────┘    └──────────────┘    └──────────────┘           │
│                             │                                        │
│                             ▼                                        │
│                      ┌──────────────┐                                │
│                      │  TWAP Oracle │                                │
│                      │  (UniV2)     │                                │
│                      └──────────────┘                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Token Economics

### BRR Token Distribution

| Allocation          | Percentage | Amount (BRR) | Vesting/Notes                              |
|---------------------|------------|--------------|-------------------------------------------|
| **Team**            | 20%        | 40,000       | 1 year linear vesting, 3-month cliff      |
| **Marketing**       | 5%         | 10,000       | 1 year linear vesting                     |
| **Treasury**        | 20%        | 40,000       | Protocol-controlled                       |
| **Liquidity**       | 5%         | 10,000       | Initial DEX liquidity                     |
| **Seed Round**      | 20%        | 40,000       | 30% TGE, 6-month vesting for remaining    |
| **Pre-Bonds**       | 5%         | 10,000       | 5-day vesting                             |
| **Airdrop**         | 12%        | 24,000       | Community distribution                    |
| **Rewards**         | 13%        | 26,000       | Staking incentives                        |
| **Total**           | 100%       | 200,000      |                                           |

### Key Token Parameters
- **Initial Supply**: 200,000 BRR
- **Initial Price**: $1.01
- **Initial Market Cap**: $200,000
- **Decimals**: 9

---

## Core Contracts

### 1. BeraReserveToken (`src/BeraReserveToken.sol`)

The main protocol token with advanced features:

```solidity
// Key Features:
- AccessControl for minting/burning roles
- Buy/Sell fee mechanism
- Token decay mechanism (reduces balance over time if not staked)
- Fee exclusion lists
- Allocation limits per minter
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `mint(address, uint256)` | Mints tokens (requires MINTER_ROLE) |
| `burn(uint256)` | Burns tokens from caller |
| `setAllocationLimit(address, uint256)` | Sets max mint allocation per address |
| `setBuyFee(uint256)` / `setSellFee(uint256)` | Configures trading fees (in BPS) |
| `setDecayRatio(uint256)` | Sets token decay rate |

**Key State Variables:**
- `buyFee`, `sellFee`: Trading fees (default 300 = 3%)
- `decayRatio`: Balance decay rate (default 2000 = 20%)
- `decayInterval`: Time between decay calculations (default 28800 = 8 hours)
- `allocationLimits`: Max tokens each minter can create

### 2. sBeraReserveERC20 (`src/sBeraReserveERC20.sol`)

The staked/rebasing version of BRR:

```solidity
// Key Features:
- Rebasing mechanism (balances increase with each rebase)
- Gons-based accounting (internal balance representation)
- Index tracking for reward calculations
```

**Key Concepts:**
- **Gons**: Internal balance unit that remains constant
- **Index**: Multiplier that increases with each rebase
- `balance = gons / gonsPerFragment`

---

## Bonding System

### BeraReserveBondDepositoryV2 (`src/BeraReserveBondDepositoryV2.sol`)

Enables users to purchase BRR at a discount by providing assets (USDC or LP tokens).

**Bond Structure:**
```solidity
struct Bond {
    uint256 amountBonded;   // Principal deposited
    uint256 payout;         // BRR remaining to be paid
    uint256 vesting;        // Blocks left to vest
    uint256 lastBlock;      // Last interaction block
    uint256 pricePaid;      // Price paid in HONEY (18 decimals)
}
```

**Bond Terms:**
```solidity
struct Terms {
    uint256 vestingTerm;    // Vesting period in blocks
    uint256 maxPayout;      // Max payout per bond (in thousandths %)
    uint256 fee;            // Fee to DAO (in hundredths %)
    uint256 discountRate;   // Discount from market price (BPS)
    uint256 maxDebt;        // Maximum total debt allowed
}
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `deposit(uint256 amount, uint256 maxPriceInHoney)` | Purchase a bond |
| `redeem()` | Claim vested BRR |
| `initializeBondTerms(...)` | Set initial bond parameters |
| `setBondTerms(PARAMETER, uint256)` | Modify bond parameters |

**Bond Flow:**
1. User deposits principle token (USDC/LP)
2. Contract calculates BRR payout based on TWAP oracle price
3. Discount is applied based on `discountRate`
4. Fee is deducted and sent to DAO
5. Bond is created with vesting period
6. User can redeem vested portions over time

### BeraReserveBondingCalculator (`src/BeraReserveBondingCalculator.sol`)

Calculates LP token valuations for liquidity bonds:

```solidity
// Key Libraries:
- FullMath: Precision math operations
- Babylonian: Square root calculations
- FixedPoint: Fixed-point arithmetic

// Main Function:
function valuation(address _pair, uint256 amount_) external view returns (uint256)
```

---

## Staking System

### BeraReserveStaking (`src/Staking.sol`)

The main staking contract with warmup period:

**Epoch Structure:**
```solidity
struct Epoch {
    uint256 length;      // Epoch duration in blocks
    uint256 number;      // Current epoch number
    uint256 endBlock;    // Block when epoch ends
    uint256 distribute;  // Amount to distribute this epoch
}
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `stake(uint256 _amount, address _recipient)` | Stake BRR to receive sBRR |
| `claim(address _recipient)` | Claim sBRR from warmup |
| `unstake(uint256 _amount, bool _trigger)` | Unstake sBRR for BRR |
| `forfeit()` | Cancel stake in warmup, get BRR back |
| `rebase()` | Trigger rebase if epoch ended |

**Staking Flow:**
1. User stakes BRR → enters warmup period
2. After warmup, user claims sBRR
3. sBRR balance increases with each rebase
4. User can unstake to convert sBRR back to BRR

### StakingDistributor (`src/StakingDistributor.sol`)

Distributes staking rewards based on rates:

```solidity
struct Info {
    uint256 rate;    // Reward rate (in ten-thousandths)
    address recipient;
}
```

---

## Treasury System

### BeraReserveTreasuryV2 (`src/BeraReserveTreasuryV2.sol`)

Simplified V2 treasury for managing protocol reserves:

**Key Mappings:**
```solidity
mapping(address => bool) public isReserveToken;
mapping(address => bool) public isLiquidityToken;
mapping(address => bool) public isReserveDepositor;
mapping(address => bool) public isLiquidityDepositor;
mapping(address => uint256) public totalReserves;
mapping(address => uint256) public totalBorrowed;
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `deposit(uint256, address, uint256)` | Deposit reserves, mint BRR |
| `borrowReserves(uint256, address)` | Borrow from reserves (manager only) |
| `repayReserves(uint256, address)` | Repay borrowed reserves |
| `setReserveDepositor(address, bool)` | Authorize depositor |

### Treasury V1 (`src/Treasury.sol`)

Legacy treasury with more complex queue system for permission management.

---

## Vesting & Lockup

### BeraReserveLockUp (`src/BeraReserveLockUp.sol`)

Manages vesting schedules for team, marketing, and seed round allocations:

**Vesting Durations:**
```solidity
uint32 public constant TEAM_VESTING_DURATION = 365 days;
uint32 public constant TEAM_VESTING_CLIFF = 90 days;
uint32 public constant MARKETING_VESTING_DURATION = 365 days;
uint32 public constant SEED_ROUND_VESTING_DURATION = 180 days;
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `mintAndStakeBRR()` | Mint and auto-stake vesting tokens |
| `addTeamMember(address, uint128)` | Add team member vesting |
| `addMarketingMember(address, uint128)` | Add marketing vesting |
| `addSeedRoundMember(address, uint128)` | Add seed round vesting |
| `unlockSbrr()` | Claim vested sBRR |

### BeraReservePreSaleBond (`src/BeraReservePreSaleBond.sol`)

Pre-sale bond mechanism with Merkle tree whitelist:

**Key Parameters:**
```solidity
uint256 public constant PRE_BOND_SALE_TOTAL_BRR_AMOUNT = 50_000e9;
uint48 public constant PRE_BOND_SALE_VESTING_DURATION = 5 days;
uint128 public bondPurchaseLimit = 2_500e9;  // Max per wallet
uint128 public tokenPrice = 2e17;             // $0.20
```

---

## Fee Distribution

### BeraReserveFeeDistributor (`src/BeraReserveFeeDistributor.sol`)

Distributes protocol fees to team, POL, and treasury:

**Default Shares:**
```solidity
uint16 public teamShare = 3_300;      // 33%
uint16 public polShare = 3_300;       // 33%
uint16 public treasuryShare = 3_400;  // 34%
```

**Key Functions:**
| Function | Description |
|----------|-------------|
| `updateAllocations()` | Calculate new fee allocations |
| `allocateToAll()` | Distribute fees to all recipients |
| `updateAddresses(...)` | Update recipient addresses |

---

## Oracle System

### BeraReserveUniswapV2TwapOracle (`src/utils/BeraReserveUniswapV2TwapOracle.sol`)

Provides Time-Weighted Average Price (TWAP) from Uniswap V2:

```solidity
uint256 public constant PERIOD = 1 hours;

// Key Functions:
function update() public;                          // Update TWAP
function consult(uint256 amountIn) external returns (uint256 amountOut);  // Get price
```

**TWAP Mechanics:**
1. Tracks cumulative price from UniV2 pair
2. Updates only after `PERIOD` has elapsed
3. Returns time-weighted average to resist manipulation

---

## Contract Interactions

### Typical Bond Purchase Flow

```
User                BondDepository           Treasury            BRR Token
  │                      │                      │                    │
  │──deposit(amount)────►│                      │                    │
  │                      │──valuation()────────►│                    │
  │                      │◄─────payout──────────│                    │
  │                      │                      │                    │
  │                      │──deposit(principle)─►│                    │
  │                      │                      │──mint(payout)─────►│
  │                      │                      │◄──────────────────│
  │                      │◄──────BRR────────────│                    │
  │◄──bondInfo───────────│                      │                    │
```

### Typical Staking Flow

```
User              Staking               sBRR              Warmup           Distributor
  │                  │                    │                  │                  │
  │──stake(amount)──►│                    │                  │                  │
  │                  │──transfer(sBRR)───►│                  │                  │
  │                  │                    │──transfer()─────►│                  │
  │                  │◄───────────────────┼──────────────────│                  │
  │                  │                    │                  │                  │
  │──claim()────────►│                    │                  │                  │
  │                  │                    │◄─retrieve()──────│                  │
  │◄────sBRR─────────│                    │                  │                  │
  │                  │                    │                  │                  │
  │                  │──rebase()─────────►│                  │                  │
  │                  │                    │──distribute()───►│──────────────────│
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

---

## Key Constants Reference

### Basis Points (BPS)
- `10,000 BPS = 100%`
- `1,000 BPS = 10%`
- `100 BPS = 1%`
- `10 BPS = 0.1%`

### Token Decimals
- **BRR**: 9 decimals
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

// Oracle
TWAP_PERIOD = 1 hours

// Decay
DEFAULT_DECAY_INTERVAL = 28800 seconds (8 hours)
```

---

## Security Considerations

### Access Control
- **Ownable2Step**: Two-step ownership transfer
- **AccessControl**: Role-based permissions (MINTER_ROLE, BURNER_ROLE)
- **Pausable**: Emergency pause functionality

### Key Security Patterns
1. **Reentrancy Protection**: SafeERC20 for token transfers
2. **Slippage Protection**: `maxPriceInHoney` in bond deposits
3. **Debt Ceiling**: `maxDebt` limits in bond depository
4. **Allocation Limits**: Per-minter caps on token creation

### Audit Scope (from `AUDIT_SCOPE.md`)
- `BeraReserveBondDepositoryV2.sol`
- `BeraReserveTreasuryV2.sol`
- `BeraReserveUniswapV2TwapOracle.sol`

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
├── Treasury.sol                       # Treasury V1
├── interfaces/                        # Contract interfaces
├── libs/                              # Custom libraries
├── types/                             # Type definitions
└── utils/
    └── BeraReserveUniswapV2TwapOracle.sol  # TWAP oracle
```

---

## Additional Resources

- **Foundry Book**: https://book.getfoundry.sh/
- **OpenZeppelin Docs**: https://docs.openzeppelin.com/
- **Olympus DAO Docs**: https://docs.olympusdao.finance/ (original fork source)
- **Berachain Docs**: https://docs.berachain.com/

---

*This reference document provides a comprehensive overview for studying the BeraReserve protocol. For detailed implementation specifics, refer to the source code and test files.*
