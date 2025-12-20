# Apiary Protocol Architecture

## System Overview

Apiary is a DeFi protocol built on Berachain that implements a bonding mechanism with automated yield distribution. The protocol accepts iBGT (Infrared BGT) as reserves, mints APIARY tokens through bonds, and manages yield through strategic distribution.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         APIARY PROTOCOL                              │
│                                                                      │
│  ┌────────────┐         ┌─────────────┐        ┌──────────────┐   │
│  │   Users    │────────▶│    Bonds    │───────▶│   Treasury   │   │
│  │            │         │             │        │              │   │
│  │  - Stake   │         │ - iBGT Bond │        │ - Hold iBGT  │   │
│  │  - Bond    │         │ - LP Bond   │        │ - Mint APIARY│   │
│  │  - Pre-Sale│         │ - Pre-Sale  │        │              │   │
│  └────────────┘         └─────────────┘        └───────┬──────┘   │
│        │                                                │           │
│        │                                                ▼           │
│        │                                      ┌─────────────────┐  │
│        │                                      │ Yield Manager   │  │
│        │                                      │                 │  │
│        │                                      │ - Claim rewards │  │
│        │                                      │ - Execute 25/25/│  │
│        │                                      │   50 strategy   │  │
│        │                                      └────────┬────────┘  │
│        │                                               │           │
│        │                              ┌────────────────┼───────┐   │
│        │                              │                │       │   │
│        │                              ▼                ▼       ▼   │
│        │                      ┌──────────┐    ┌─────────────┐     │
│        │                      │Infrared  │    │   Kodiak    │     │
│        │                      │Adapter   │    │   Adapter   │     │
│        │                      │          │    │             │     │
│        │                      │-Stake    │    │-Swap        │     │
│        │                      │-Claim    │    │-Add LP      │     │
│        │                      └──────────┘    │-Stake LP    │     │
│        │                                      └─────────────┘     │
│        │                                                           │
│        ▼                                                           │
│  ┌────────────┐                                                    │
│  │  Staking   │                                                    │
│  │            │                                                    │
│  │ - APIARY → │                                                    │
│  │   sAPIARY  │                                                    │
│  │ - Warmup   │                                                    │
│  └────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────┘

External Dependencies:
├── Infrared Protocol (iBGT staking)
├── Kodiak DEX (swaps + liquidity)
├── Berachain (iBGT, HONEY tokens)
└── OpenZeppelin (access control, pausable, reentrancy)
```

---

## Contract Relationships

### Core Token Contracts

#### 1. **ApiaryToken** (APIARY)
- **Type**: ERC20 with AccessControl
- **Purpose**: Governance and utility token
- **Total Supply**: 200,000 APIARY (9 decimals)
- **Minting**: Controlled by allocation limits
- **Dependencies**: None (base token)
- **Dependents**: All other contracts

```solidity
ApiaryToken
├── Uses: AccessControl (OpenZeppelin)
├── Mints via: Treasury, Bonds, Pre-Sale
└── Burned by: YieldManager, Users
```

#### 2. **sApiary** (sAPIARY)
- **Type**: Rebasing ERC20
- **Purpose**: Staked APIARY representation
- **Supply**: Dynamic (based on staking)
- **Dependencies**: ApiaryStaking
- **Rebasing**: Index-based (increases over time in Phase 2+)

```solidity
sApiary
├── Initialized by: ApiaryStaking
├── Minted by: ApiaryStaking.stake()
└── Burned by: ApiaryStaking.unstake()
```

### Financial Contracts

#### 3. **ApiaryTreasury**
- **Purpose**: Reserve management and APIARY minting
- **Holds**: iBGT, APIARY/HONEY LP, HONEY
- **Mints APIARY** for: Bonds, Pre-Sale
- **Lends iBGT to**: YieldManager (for staking)

```solidity
ApiaryTreasury
├── Receives deposits from: BondDepositories
├── Mints APIARY via: IApiaryToken.mint()
├── Lends iBGT to: ApiaryYieldManager
└── Managed by: Multisig (owner)
```

#### 4. **ApiaryStaking**
- **Purpose**: Stake APIARY to earn sAPIARY
- **Mechanism**: Warmup period → receive sAPIARY
- **Rebase**: Epoch-based (no rebase in Phase 1)
- **Unstaking**: Burn sAPIARY → receive APIARY

```solidity
ApiaryStaking
├── Stakes: APIARY → sAPIARY
├── Warmup via: ApiaryStakingWarmup
├── Distributes yield: Phase 2+ (from YieldManager)
└── Rebases: sApiary index increases
```

#### 5. **ApiaryStakingWarmup**
- **Purpose**: Hold sAPIARY during warmup period
- **Duration**: Configurable warmup blocks
- **Retrieval**: After warmup, claim sAPIARY

### Bond Contracts

#### 6. **ApiaryBondDepository** (iBGT Bond)
- **Principle**: iBGT tokens
- **Payout**: Vested APIARY
- **Pricing**: TWAP-based with discount
- **Vesting**: Linear over N blocks

```solidity
ApiaryBondDepository (iBGT)
├── Accepts: iBGT
├── Deposits to: ApiaryTreasury
├── Vests: APIARY tokens
└── Pricing via: ApiaryUniswapV2TwapOracle
```

#### 7. **ApiaryBondDepository** (LP Bond)
- **Principle**: APIARY/HONEY LP tokens
- **Payout**: Vested APIARY
- **Pricing**: LP value calculation
- **Vesting**: Linear over N blocks

```solidity
ApiaryBondDepository (LP)
├── Accepts: APIARY/HONEY LP
├── Deposits to: ApiaryTreasury
├── Vests: APIARY tokens
└── Pricing via: ApiaryUniswapV2TwapOracle + BondCalculator
```

#### 8. **ApiaryPreSaleBond**
- **Payment**: HONEY tokens
- **Payout**: APIARY with 110% bonus
- **Whitelist**: Merkle tree verification
- **Vesting**: Linear over 30 days post-TGE

```solidity
ApiaryPreSaleBond
├── Accepts: HONEY
├── Whitelist via: Merkle proof
├── Bonus: 110% APIARY
└── Vesting: 30 days linear
```

#### 9. **ApiaryUniswapV2TwapOracle**
- **Purpose**: Time-weighted average price for APIARY
- **Updates**: Periodic (configurable interval)
- **Used by**: Bond depositories for pricing

### Yield Management

#### 10. **ApiaryYieldManager**
- **Most Critical Contract**: Orchestrates all yield distribution
- **Phase 1** (25/25/50):
  - 25% → swap to HONEY
  - 25% → swap to APIARY → burn
  - 50% → create APIARY/HONEY LP → stake
- **Phase 2**: MC/TV ratio-based distribution
- **Phase 3**: vBGT accumulation

```solidity
ApiaryYieldManager
├── Claims from: ApiaryInfraredAdapter
├── Swaps via: ApiaryKodiakAdapter
├── Burns: APIARY
├── Creates LP: APIARY/HONEY
└── Stakes LP: On Kodiak gauge
```

#### 11. **ApiaryInfraredAdapter**
- **Purpose**: Interface to Infrared protocol
- **Functions**: Stake iBGT, claim rewards
- **Access**: Only YieldManager can call
- **Emergency**: Owner can withdraw

```solidity
ApiaryInfraredAdapter
├── Stakes: iBGT on Infrared
├── Claims: Rewards for YieldManager
├── Treasury: Holds staked balance
└── Emergency: Owner withdrawal
```

#### 12. **ApiaryKodiakAdapter**
- **Purpose**: Interface to Kodiak DEX
- **Functions**: Swap, add liquidity, stake LP
- **Access**: Only YieldManager can call
- **Emergency**: Owner can withdraw

```solidity
ApiaryKodiakAdapter
├── Swaps: iBGT → HONEY/APIARY
├── Adds LP: APIARY/HONEY
├── Stakes LP: On Kodiak gauge
└── Claims: LP staking rewards
```

---

## Dependency Graph

```
External Protocols
├── Infrared Protocol
│   ├── Stake iBGT
│   └── Claim rewards
├── Kodiak DEX
│   ├── Swap tokens
│   ├── Add liquidity
│   └── Stake LP tokens
└── Berachain
    ├── iBGT token
    ├── HONEY token
    └── BGT token (Phase 3)

Internal Dependencies
├── ApiaryToken (base)
│   └── Used by: All contracts
├── sApiary
│   └── Depends on: ApiaryStaking
├── ApiaryTreasury
│   ├── Depends on: ApiaryToken
│   └── Used by: Bonds, YieldManager
├── ApiaryStaking
│   ├── Depends on: ApiaryToken, sApiary
│   └── Uses: ApiaryStakingWarmup
├── Bonds (iBGT, LP, Pre-Sale)
│   ├── Depend on: ApiaryTreasury, ApiaryToken
│   └── Use: ApiaryUniswapV2TwapOracle
├── ApiaryYieldManager
│   ├── Depends on: ApiaryTreasury
│   ├── Uses: ApiaryInfraredAdapter, ApiaryKodiakAdapter
│   └── Interacts with: ApiaryToken (burn)
└── Adapters
    ├── ApiaryInfraredAdapter → Infrared Protocol
    └── ApiaryKodiakAdapter → Kodiak DEX
```

---

## Trust Assumptions

### Protocol Admin (Multisig)

**Has Control Over:**
1. ✅ Setting bond terms (vesting, discount, max debt)
2. ✅ Pausing/unpausing all contracts
3. ✅ Configuring yield strategy splits
4. ✅ Setting adapters in yield manager
5. ✅ Emergency withdrawal of stuck tokens
6. ✅ Updating treasury depositors
7. ✅ Setting allocation limits (one-time)
8. ✅ Starting/ending pre-sale

**CANNOT:**
1. ❌ Mint APIARY arbitrarily (allocation limits enforced)
2. ❌ Steal user bonds (vested over time)
3. ❌ Change allocation limits after set
4. ❌ Bypass two-step ownership transfer
5. ❌ Override vesting schedules

**Trust Level**: HIGH
- Multisig should be 3/5 or 4/7
- Signers should be trusted community members
- Actions should be time-locked (not implemented, audit recommendation)

### Yield Manager Keeper

**Has Control Over:**
1. ✅ Executing yield distribution (public function)
2. ✅ Timing of yield execution

**CANNOT:**
1. ❌ Change yield strategy
2. ❌ Withdraw funds
3. ❌ Modify parameters

**Trust Level**: LOW (public function, anyone can call)

### External Protocols

#### Infrared Protocol
- **Trust**: Treasury iBGT staked on Infrared
- **Risk**: Infrared contract bug could lock funds
- **Mitigation**: Emergency withdrawal by owner

#### Kodiak DEX
- **Trust**: Swaps and LP creation via Kodiak
- **Risk**: Price manipulation, liquidity issues
- **Mitigation**: TWAP oracle, slippage protection

#### Berachain
- **Trust**: iBGT, HONEY token contracts
- **Risk**: Token contract bugs, freezing
- **Mitigation**: Well-audited protocol (assumed)

---

## Data Flow

### Bonding Flow (iBGT Bond)

```
User
  │
  │ 1. Approve iBGT
  ▼
BondDepository.deposit(amount, maxPrice, depositor)
  │
  │ 2. Transfer iBGT from user
  │ 3. Check price via TWAP oracle
  │ 4. Calculate payout
  │ 5. Create bond info (vesting)
  │
  ▼
Treasury.deposit(amount, iBGT, payoutValue)
  │
  │ 6. Receive iBGT
  │ 7. Mint APIARY to BondDepository
  │
  ▼
BondDepository
  │
  │ 8. Store bond info with vesting
  │ 9. Emit BondCreated event
  │
  ▼
User
  │
  │ (Wait for vesting)
  │
  ▼
BondDepository.redeem(depositor, all)
  │
  │ 10. Calculate vested amount
  │ 11. Transfer APIARY to depositor
  │ 12. Update bond info
  │ 13. Emit BondRedeemed event
  │
  ▼
User receives APIARY
```

### Yield Distribution Flow (Phase 1)

```
Keeper (or anyone)
  │
  │ 1. Call executeYield()
  ▼
YieldManager
  │
  │ 2. Claim iBGT rewards from Infrared
  ▼
InfraredAdapter.claimRewards()
  │
  │ 3. Claim from Infrared protocol
  │ 4. Return rewards to YieldManager
  │
  ▼
YieldManager
  │
  │ 5. Calculate splits (25/25/50)
  │
  ├─────────────────┬─────────────────┬──────────────────┐
  │                 │                 │                  │
  │ 25% HONEY       │ 25% BURN        │ 50% LP+STAKE    │
  ▼                 ▼                 ▼                  │
KodiakAdapter     KodiakAdapter     KodiakAdapter       │
  │                 │                 │                  │
  │ Swap iBGT→      │ Swap iBGT→      │ Swap iBGT→       │
  │ HONEY           │ APIARY          │ APIARY + HONEY   │
  │                 │                 │                  │
  │                 │ Burn APIARY     │ Add liquidity    │
  │                 │                 │ Stake LP         │
  │                 │                 │                  │
  ▼                 ▼                 ▼                  │
Treasury         Burned           LP staked on Kodiak   │
receives HONEY                                          │
                                                        │
                                    (Earn LP rewards)   │
```

### Staking Flow

```
User
  │
  │ 1. Approve APIARY
  ▼
ApiaryStaking.stake(amount, recipient)
  │
  │ 2. Transfer APIARY from user
  │ 3. Calculate sAPIARY amount (by index)
  │ 4. Mint sAPIARY to warmup
  │ 5. Create warmup info
  │
  ▼
ApiaryStakingWarmup
  │
  │ 6. Hold sAPIARY
  │ 7. Store warmup info
  │
  ▼
User
  │
  │ (Wait for warmup period)
  │
  ▼
ApiaryStaking.unstake(amount, trigger=false)
  │
  │ 8. Check if warmup complete
  │ 9. Transfer sAPIARY from warmup to user
  │
  ▼
User
  │
  │ (Later: unstake)
  │
  ▼
ApiaryStaking.unstake(amount, trigger=true)
  │
  │ 10. Burn sAPIARY
  │ 11. Calculate APIARY amount (by index)
  │ 12. Transfer APIARY to user
  │
  ▼
User receives APIARY
```

---

## Security Model

### Access Control Hierarchy

```
1. DEFAULT_ADMIN_ROLE (Multisig)
   ├── Grants/revokes MINTER_ROLE
   ├── Grants/revokes BURNER_ROLE
   └── Sets allocation limits

2. Owner (Multisig via Ownable2Step)
   ├── Treasury admin functions
   ├── Bond admin functions
   ├── Yield manager admin functions
   └── Adapter admin functions

3. Authorized Contracts
   ├── MINTER_ROLE (Treasury, Bonds)
   ├── Yield Manager (can borrow iBGT from treasury)
   └── Adapters (can only be called by Yield Manager)

4. Public Functions
   ├── stake()
   ├── unstake()
   ├── deposit() (bonds)
   ├── redeem() (bonds)
   └── executeYield() (anyone can trigger)
```

### Reentrancy Protection

**Contracts with ReentrancyGuard:**
- ApiaryTreasury (multiple external calls)
- ApiaryStaking (token transfers)
- ApiaryBondDepository (token transfers)
- ApiaryPreSaleBond (token transfers)
- ApiaryYieldManager (most critical - many external calls)
- ApiaryInfraredAdapter (external protocol calls)
- ApiaryKodiakAdapter (external DEX calls)

**Protected Functions:**
- All deposit/withdrawal functions
- executeYield() in YieldManager
- stake/unstake in Staking
- All adapter functions

### Pausable Mechanisms

**Contracts with Pausable:**
- ApiaryStaking
- ApiaryBondDepository (both)
- ApiaryPreSaleBond
- ApiaryYieldManager
- ApiaryInfraredAdapter
- ApiaryKodiakAdapter

**Paused Functions:**
- staking/unstaking
- bond deposits
- pre-sale purchases
- yield execution
- adapter operations

**Emergency Mode:**
- YieldManager has emergency mode (bypass adapters)
- Transfers yield directly to treasury
- Used if adapters are compromised

---

## Upgrade Path

**Current Contracts:** Non-upgradeable (no proxy pattern)

**If Upgrade Needed:**
1. Deploy new contracts
2. Migrate state (manual process)
3. Update addresses in dependencies
4. Transfer ownership

**Recommended:**
- Use proxy pattern for future versions
- Implement time-locked upgrades
- Multi-sig approval for upgrades

---

## System Invariants

See [INVARIANTS.md](./INVARIANTS.md) for complete list of protocol invariants that must always hold true.

---

## External Integrations

### Infrared Protocol
- **Contract**: `ApiaryInfraredAdapter`
- **Functions Used**: `stake()`, `withdraw()`, `getReward()`
- **Trust**: HIGH (treasury funds staked)

### Kodiak DEX
- **Contract**: `ApiaryKodiakAdapter`
- **Functions Used**: `swapExactTokensForTokens()`, `addLiquidity()`, `deposit()` (gauge)
- **Trust**: MEDIUM (temporary token holdings during swaps)

### Berachain Tokens
- **iBGT**: Reserve asset
- **HONEY**: Stablecoin for pre-sale and swaps
- **BGT**: Future use (Phase 3)

---

## Economic Model

**Revenue Sources:**
1. iBGT staking rewards (Infrared)
2. LP staking rewards (Kodiak)
3. Bond discounts (discount < market value)

**Value Accrual:**
- Phase 1: LP creation + APIARY burns
- Phase 2: Staker distributions + buybacks
- Phase 3: vBGT accumulation (POL benefits)

**Supply Dynamics:**
- Max supply: 200,000 APIARY
- Minting: Via bonds (allocation limited)
- Burning: Yield manager (25% in Phase 1)
- Net: Deflationary in Phase 1

---

**For detailed security analysis, see [SECURITY.md](./SECURITY.md)**
