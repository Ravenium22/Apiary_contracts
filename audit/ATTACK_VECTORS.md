# Apiary Protocol Attack Vectors

Detailed attack scenarios for security audit focus areas.

---

## Table of Contents

1. [Flash Loan Attacks](#1-flash-loan-attacks)
2. [Oracle Manipulation](#2-oracle-manipulation)
3. [Front-Running Attacks](#3-front-running-attacks)
4. [Reentrancy Exploits](#4-reentrancy-exploits)
5. [Griefing Attacks](#5-griefing-attacks)
6. [Admin Key Compromise](#6-admin-key-compromise)
7. [External Protocol Exploits](#7-external-protocol-exploits)
8. [Economic Manipulation](#8-economic-manipulation)
9. [Sybil Attacks](#9-sybil-attacks)
10. [MEV Extraction](#10-mev-extraction)

---

## 1. Flash Loan Attacks

### ATTACK-1.1: Flash Loan Yield Extraction

**Attacker Goal**: Extract yield without long-term staking.

**Prerequisites**:
- Flash loan access (e.g., Balancer, Aave)
- No warmup period or warmup = 0

**Attack Steps**:
```solidity
// 1. Flash loan 10,000 APIARY
flashLoan(APIARY, 10000e9);

// 2. Stake all APIARY
staking.stake(10000e9, attacker);
// Receives 10,000 sAPIARY (assuming index = 1.0)

// 3. Trigger rebase (if epoch ended)
staking.rebase();
// All sAPIARY holders earn yield (e.g., 0.5% → 50 APIARY distributed)

// 4. Attacker's share of yield
// If total staked = 100,000 APIARY, attacker has 10%
// Attacker earns: 50 * 10% = 5 APIARY

// 5. Unstake
staking.unstake(10000e9 + 5e9, true);
// Receives 10,005 APIARY

// 6. Repay flash loan
repayFlashLoan(10000e9);
// Net profit: 5 APIARY (minus gas)
```

**Impact**: 🔴 CRITICAL (if warmup disabled)
- Attacker profits without risk
- Dilutes yield for legitimate stakers

**Current Mitigations**:
✅ **Warmup period**: Prevents immediate unstaking
✅ **`lastTimeStaked` tracking**: Prevents flash loan staking (if checked)

**Exploitation Conditions**:
- Warmup contract not set or warmup = 0
- `lastTimeStaked` not enforced in unstake

**Recommendations**:
1. **Enforce minimum warmup period (1 epoch = ~8 hours)**
2. **Check `lastTimeStaked` in unstake**:
   ```solidity
   function unstake(uint256 amount, bool trigger) external {
       if (trigger) {
           require(block.timestamp >= lastTimeStaked[msg.sender] + warmupPeriod);
       }
       // ... rest of unstake logic
   }
   ```
3. **Add entry/exit fee (0.1%)** to make flash loan unprofitable

---

### ATTACK-1.2: Flash Loan LP Manipulation

**Attacker Goal**: Manipulate LP token value for discounted bonds.

**Prerequisites**:
- Flash loan access to HONEY
- Low liquidity in APIARY/HONEY pair

**Attack Steps**:
```solidity
// 1. Flash loan 100,000 HONEY
flashLoan(HONEY, 100000e18);

// 2. Swap 50,000 HONEY → APIARY on Kodiak
// This dumps APIARY price (e.g., $1.00 → $0.80)
kodiakRouter.swap(50000e18, HONEY, APIARY);

// 3. Create APIARY/HONEY LP with remaining HONEY
kodiakRouter.addLiquidity(
    APIARY, 
    HONEY, 
    receivedApiary, // From step 2
    50000e18
);
// Receives LP tokens

// 4. Deposit LP to bond depository
// Bond calculator values LP using current reserves (manipulated)
bondDepository.deposit(lpAmount, maxPrice, attacker);
// Receives more APIARY bonds than fair value

// 5. Remove liquidity
kodiakRouter.removeLiquidity(lpAmount);

// 6. Swap APIARY back → HONEY
kodiakRouter.swap(apiaryAmount, APIARY, HONEY);

// 7. Repay flash loan
repayFlashLoan(100000e18);

// 8. Wait for bond vesting, redeem profit
```

**Impact**: ⚠️ MEDIUM (if LP pool small)

**Current Mitigations**:
✅ **TWAP oracle**: Bond price uses time-weighted price (not spot)
❌ **Bond calculator may use spot reserves**: LP valuation could be manipulated

**Exploitation Conditions**:
- LP pool has <$100k liquidity (easy to manipulate)
- Bond calculator uses `pair.getReserves()` directly
- No cooldown between LP deposit and bond purchase

**Recommendations**:
1. **Use time-weighted reserves in bond calculator**:
   ```solidity
   function calculateLPValue(uint256 lpAmount) public view returns (uint256) {
       // Use TWAP reserves, not spot
       (uint112 reserve0TWAP, uint112 reserve1TWAP) = getTWAPReserves();
       // ... calculate LP value
   }
   ```
2. **Require minimum LP pool TVL ($100k)**
3. **Add LP deposit cooldown (1 hour before bonds)**

---

## 2. Oracle Manipulation

### ATTACK-2.1: TWAP Oracle Short-Window Manipulation

**Attacker Goal**: Manipulate oracle price for cheaper bonds.

**Prerequisites**:
- TWAP window < 1 hour
- Medium liquidity pool ($50k-$200k)

**Attack Steps**:
```solidity
// Assume TWAP window = 30 minutes, current time = 12:00 PM

// 12:00 PM: Swap 10,000 HONEY → APIARY (pump APIARY price)
kodiakRouter.swap(10000e18, HONEY, APIARY);
// APIARY price: $1.00 → $1.20

// 12:01-12:28 PM: Wait (27 minutes)
// Keep price elevated with small buys

// 12:29 PM: Call oracle.update()
oracle.update();
// Oracle captures price0Average = $1.20 (manipulated)

// 12:30 PM: Buy bonds (APIARY appears expensive, bonds are "discounted")
// Bond price = oraclePrice * (1 - discount)
// But real market price already back to $1.00
bondDepository.deposit(ibgtAmount, maxPrice, attacker);

// 12:31 PM: Swap APIARY → HONEY (dump, return to $1.00)
kodiakRouter.swap(apiaryAmount, APIARY, HONEY);

// Wait for vesting, redeem bonds at profit
```

**Impact**: ⚠️ MEDIUM

**Cost Analysis**:
- To manipulate $1.00 → $1.20 for 30 minutes:
  - Need to keep $50k buy pressure (in $200k pool)
  - Cost ≈ $1k in slippage + LP fees
- Profit from 20% bond discount on $10k deposit:
  - Receive $12k worth of APIARY
  - Net profit ≈ $1k (break-even)

**Current Mitigations**:
✅ **TWAP oracle**: Time-weighted average resists single-block attacks
✅ **minimumUpdateInterval**: Prevents rapid updates

**Exploitation Conditions**:
- TWAP window < 1 hour (vulnerable to sustained manipulation)
- Low pool liquidity (cheap to manipulate)
- High bond discount (>10%)

**Recommendations**:
1. **Set TWAP window to 2 hours minimum**
2. **Set minimumUpdateInterval to 1 hour**
3. **Add price change circuit breaker**:
   ```solidity
   function update() public {
       // ... calculate new price
       require(newPrice <= oldPrice * 11000 / 10000, "Price jumped >10%");
       require(newPrice >= oldPrice * 9000 / 10000, "Price dropped >10%");
   }
   ```
4. **Monitor oracle updates for anomalies**

---

### ATTACK-2.2: Oracle Staleness Exploitation

**Attacker Goal**: Exploit outdated oracle price.

**Prerequisites**:
- Oracle not updated for >24 hours
- Real market price moved significantly

**Attack Steps**:
```solidity
// Day 1: APIARY market price = $1.00, oracle shows $1.00
// (Oracle last updated 24 hours ago)

// Day 2: APIARY pumps to $2.00 on external DEX (Uniswap)
// Oracle still shows $1.00 (no one called update())

// Attacker sees opportunity
// Bond price = oraclePrice * (1 - 10% discount) = $0.90
// Real market price = $2.00

// Attacker buys max bonds
bondDepository.deposit(10000e18 /* iBGT */, maxPrice, attacker);
// Receives bonds valued at $0.90 per APIARY
// But real value is $2.00 per APIARY (122% profit!)

// Wait for vesting, sell APIARY at $2.00
```

**Impact**: 🔴 CRITICAL (if oracle stale >1 day)

**Current Mitigations**:
❌ **No staleness check in bond depository**

**Exploitation Conditions**:
- No one calls `oracle.update()` for days
- Market price moves significantly
- No keeper to auto-update oracle

**Recommendations**:
1. **Add staleness check in bond deposit**:
   ```solidity
   function deposit(uint256 amount, uint256 maxPrice, address depositor) external {
       require(block.timestamp - twap.blockTimestampLast() < 1 hours, "Oracle stale");
       // ... rest of deposit logic
   }
   ```
2. **Incentivize oracle updates** (small APIARY reward)
3. **Add keeper to update every 30 minutes**
4. **Alert if oracle not updated in 2 hours**

---

### ATTACK-2.3: Multi-DEX Price Divergence

**Attacker Goal**: Arbitrage between Kodiak (oracle) and other DEXs.

**Prerequisites**:
- APIARY listed on multiple DEXs (Kodiak, Uniswap)
- Oracle only uses Kodiak

**Attack Steps**:
```solidity
// Kodiak: APIARY = $1.00 (oracle source)
// Uniswap: APIARY = $1.10 (due to demand)

// 1. Buy bonds using Kodiak oracle price
bondDepository.deposit(ibgtAmount, maxPrice, attacker);
// Bond price = $0.90 (10% discount from $1.00)

// 2. Immediately sell received APIARY on Uniswap at $1.10
// Profit: $1.10 - $0.90 = $0.20 per APIARY (22% profit)

// 3. Repeat until prices converge
```

**Impact**: ⚠️ MEDIUM

**Current Mitigations**:
❌ **Single oracle source (Kodiak only)**

**Recommendations**:
1. **Add multi-oracle aggregation**:
   - Primary: Kodiak TWAP
   - Secondary: Uniswap TWAP
   - Tertiary: Chainlink (if available)
   - Use median of 3 prices
2. **Add price deviation alert** (>5% between DEXs)

---

## 3. Front-Running Attacks

### ATTACK-3.1: Bond Purchase Front-Running

**Attacker Goal**: Front-run bond purchases to increase debt and worsen victim's price.

**Prerequisites**:
- Public mempool (typical on most chains)
- Bond has limited capacity (maxDebt)

**Attack Steps**:
```solidity
// 1. Victim submits bond purchase
// TX in mempool: deposit(1000 iBGT, maxPrice=1.05, victim)

// 2. Attacker sees TX, submits higher gas
// Attacker TX: deposit(5000 iBGT, maxPrice=1.10, attacker)

// 3. Attacker's TX executes first
// - totalDebt increases by 5000 APIARY
// - Debt decay reduces (higher debt = higher price)

// 4. Victim's TX executes second
// - Bond price now higher (or TX reverts if maxDebt exceeded)
// - Victim pays more or fails

// 5. Attacker redeems bonds later at profit
```

**Impact**: 🟡 LOW (victim has slippage protection with `maxPrice`)

**Current Mitigations**:
✅ **`maxPrice` parameter**: Victim can set tight slippage
✅ **Vesting period**: Prevents immediate dump

**Exploitation Conditions**:
- Victim sets loose `maxPrice` (>5%)
- Bond has high demand (near maxDebt)

**Recommendations**:
1. **Use Flashbots/private mempool** (if available)
2. **Add per-block bond limit**:
   ```solidity
   mapping(uint256 => uint256) public bondsPerBlock;
   
   function deposit(...) external {
       require(bondsPerBlock[block.number] < MAX_PER_BLOCK, "Block limit reached");
       bondsPerBlock[block.number] += payout;
       // ... rest of logic
   }
   ```
3. **Implement bond queue (FIFO)**

---

### ATTACK-3.2: Yield Execution Sandwich Attack

**Attacker Goal**: Sandwich `executeYield()` to profit from swaps.

**Prerequisites**:
- Public mempool
- Yield execution involves large swaps

**Attack Steps**:
```solidity
// 1. Keeper submits executeYield()
// Will swap 1000 iBGT → HONEY on Kodiak

// 2. Attacker front-runs with large iBGT → HONEY swap
// Pumps HONEY price (or dumps iBGT price)

// 3. executeYield() executes at worse price
// Receives less HONEY than expected (e.g., 5% slippage)

// 4. Attacker back-runs with HONEY → iBGT swap
// Profits from price reversal

// Net effect: Attacker extracts 5% of yield value
```

**Impact**: ⚠️ MEDIUM (5-10% yield loss per attack)

**Current Mitigations**:
✅ **slippageTolerance parameter**: Limits bad swaps (reverts if >tolerance)
❌ **Public mempool**: Transactions visible to MEV bots

**Exploitation Conditions**:
- High slippage tolerance (>1%)
- Large yield amounts ($10k+)
- Low DEX liquidity

**Recommendations**:
1. **Use private mempool (Flashbots-style)**
2. **Set tight slippage (0.5% max)**
3. **Add time-delay for execution**:
   ```solidity
   mapping(uint256 => uint256) public scheduledExecution;
   
   function scheduleYield() external {
       scheduledExecution[block.number + 5] = block.timestamp;
   }
   
   function executeYield() external {
       require(scheduledExecution[block.number] > 0, "Not scheduled");
       // Execute 5 blocks later (prevents same-block sandwich)
   }
   ```
4. **Split large swaps into smaller batches**

---

### ATTACK-3.3: Oracle Update Front-Running

**Attacker Goal**: Update oracle before bond buyers to gain price advantage.

**Prerequisites**:
- Oracle can be updated by anyone
- Bond prices depend on oracle

**Attack Steps**:
```solidity
// 1. Attacker monitors Kodiak APIARY/HONEY pair
// Detects price increase: $1.00 → $1.10

// 2. Before bond buyers react, attacker calls update()
oracle.update();
// Oracle price updated to $1.10

// 3. Bond price increases (discount from $1.10, not $1.00)
// Bond price = $1.10 * 0.9 = $0.99 (vs $0.90 before)

// 4. Attacker bought bonds earlier at $0.90
// Other buyers now pay $0.99 (10% worse)

// 5. Attacker profits from early information
```

**Impact**: 🟡 LOW (minor information advantage)

**Current Mitigations**:
✅ **Anyone can update**: No monopoly on updates
✅ **minimumUpdateInterval**: Prevents rapid updates

**Recommendations**:
1. **Add update incentive** (0.1 APIARY per update)
2. **Add update cooldown per caller** (1 update per 10 minutes)

---

## 4. Reentrancy Exploits

### ATTACK-4.1: Malicious ERC20 Reentrancy

**Attacker Goal**: Re-enter protocol functions via malicious token callbacks.

**Prerequisites**:
- Malicious ERC20 with `transferFrom` hook
- Protocol accepts this token as reserve

**Attack Steps**:
```solidity
contract MaliciousToken is ERC20 {
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Hook before transfer
        if (to == address(treasury)) {
            // Re-enter deposit()
            treasury.deposit(amount, address(this), 9999999e9);
        }
        // Actual transfer
        return super.transferFrom(from, to, amount);
    }
}

// Attacker's exploit
maliciousToken.approve(treasury, 1000e18);
treasury.deposit(1000e18, maliciousToken, 100e9);

// During transferFrom, re-enters deposit()
// Could mint APIARY multiple times for single deposit
```

**Impact**: 🔴 CRITICAL (if malicious token approved)

**Current Mitigations**:
✅ **ReentrancyGuard**: Prevents reentrancy
✅ **Token whitelist**: Only approved tokens (`isReserveToken`)

**Exploitation Conditions**:
- Admin approves malicious token as reserve (unlikely)
- ReentrancyGuard not applied to `deposit()`

**Recommendations**:
1. **Verify ReentrancyGuard on all external calls**
2. **Audit token contracts before whitelisting**
3. **Use `safeTransferFrom` (OpenZeppelin)**

---

### ATTACK-4.2: Yield Adapter Reentrancy

**Attacker Goal**: Re-enter YieldManager via malicious adapter.

**Prerequisites**:
- Compromised or malicious adapter set
- ReentrancyGuard not on `executeYield()`

**Attack Steps**:
```solidity
contract MaliciousAdapter {
    function claimRewards() external returns (uint256) {
        // Re-enter executeYield()
        yieldManager.executeYield();
        
        // Could drain funds or manipulate state
        return 1000e18; // Fake rewards
    }
}

// Admin (compromised) sets malicious adapter
yieldManager.setInfraredAdapter(maliciousAdapter);

// Attacker calls executeYield()
yieldManager.executeYield();
// During adapter.claimRewards(), re-enters executeYield()
```

**Impact**: 🔴 CRITICAL (if admin compromised)

**Current Mitigations**:
✅ **ReentrancyGuard on YieldManager**: Prevents reentrancy

**Exploitation Conditions**:
- Admin sets malicious adapter (requires admin compromise)
- ReentrancyGuard removed or bypassed

**Recommendations**:
1. **Verify ReentrancyGuard on YieldManager**
2. **Timelock adapter changes (48 hours)**
3. **Adapter interface validation**:
   ```solidity
   function setInfraredAdapter(address _adapter) external onlyOwner {
       require(IAdapter(_adapter).supportsInterface(ADAPTER_INTERFACE_ID));
       // ... set adapter after 48h timelock
   }
   ```

---

## 5. Griefing Attacks

### ATTACK-5.1: Bond Capacity Griefing

**Attacker Goal**: Block legitimate users from bonding.

**Prerequisites**:
- Bond has maxDebt limit
- Attacker has capital

**Attack Steps**:
```solidity
// Bond maxDebt = 10,000 APIARY
// Current debt = 0

// 1. Attacker deposits to max capacity
bondDepository.deposit(ibgtAmount, maxPrice, attacker);
// totalDebt = 10,000 APIARY (maxed out)

// 2. Legitimate users try to bond
bondDepository.deposit(ibgtAmount, maxPrice, user);
// Reverts: "Max debt exceeded"

// 3. Attacker holds bonds, preventing others from bonding
// Legitimate users miss out on bonding opportunity

// 4. Attacker redeems bonds later (no loss, just griefing)
```

**Impact**: 🟡 LOW (attacker gains no profit, but annoys users)

**Current Mitigations**:
✅ **First-come-first-serve**: Fair access
❌ **No bond limit per user**: Whale can monopolize

**Recommendations**:
1. **Add per-user bond limit**:
   ```solidity
   mapping(address => uint256) public userBondAmount;
   uint256 public constant MAX_BOND_PER_USER = 100e9; // 100 APIARY
   
   function deposit(...) external {
       require(userBondAmount[msg.sender] + payout <= MAX_BOND_PER_USER, "User limit");
       userBondAmount[msg.sender] += payout;
   }
   ```
2. **Increase maxDebt dynamically based on demand**
3. **Add bond queue (everyone gets fair share)**

---

### ATTACK-5.2: Rebase Delay Griefing

**Attacker Goal**: Delay rebase to frustrate stakers.

**Prerequisites**:
- `rebase()` is public (anyone can call)
- Gas costs prevent legitimate callers

**Attack Steps**:
```solidity
// Epoch ends at block 1000
// Current block = 1000 (rebase eligible)

// 1. Attacker front-runs all rebase() calls
// Submits TX with higher gas: rebase()
// But reverts at the end (e.g., require(false))

// 2. All legitimate rebase() calls execute after attacker's revert
// But they paid gas for nothing

// 3. Attacker repeats, preventing rebase for hours
// Stakers don't earn yield during delay
```

**Impact**: 🟡 LOW (costly for attacker, minor annoyance)

**Current Mitigations**:
✅ **rebase() is permissionless**: Anyone can call
❌ **No griefing protection**

**Recommendations**:
1. **Add rebase incentive** (small APIARY reward to caller)
2. **Add keeper to auto-rebase** (guaranteed execution)
3. **Ignore reverts, auto-retry**

---

## 6. Admin Key Compromise

### ATTACK-6.1: Malicious Admin Drains Treasury

**Scenario**: Admin private key is compromised.

**Attack Steps**:
```solidity
// Attacker has admin key

// 1. Set malicious yield manager
treasury.setYieldManager(attackerEOA);

// 2. Borrow all iBGT
treasury.borrowIBGT(10000000e18); // All reserves
// Transfer to attacker

// 3. Set malicious adapters
yieldManager.setInfraredAdapter(attackerContract);
yieldManager.setKodiakAdapter(attackerContract);

// 4. Execute yield (all funds go to attacker adapters)
yieldManager.executeYield();

// 5. Emergency withdraw from adapters
infraredAdapter.emergencyWithdraw(); // Sends to treasury (controlled by attacker)
kodiakAdapter.emergencyWithdraw(IBGT);

// Protocol drained
```

**Impact**: 🔴 CRITICAL (total loss)

**Current Mitigations**:
✅ **Ownable2Step**: Prevents accidental transfers (but not malicious)
❌ **No timelock**: Immediate effect
❌ **No multi-sig enforcement**

**Recommendations**:
1. **Mandatory multi-sig (3-of-5 or 5-of-9)**
2. **48-hour timelock on critical functions**:
   - `setYieldManager()`
   - `setInfraredAdapter()`
   - `setKodiakAdapter()`
   - `setBondTerms()`
3. **Emergency pause by separate role** (not admin)
4. **On-chain governance** (future phase)

---

### ATTACK-6.2: Malicious Admin Manipulates Bond Terms

**Scenario**: Admin changes bond terms to benefit themselves.

**Attack Steps**:
```solidity
// 1. Admin (or compromised admin) sets bond discount to 50%
bondDepository.setBondTerms(1, 5000); // 50% discount

// 2. Admin front-runs public announcement
bondDepository.deposit(largeAmount, maxPrice, admin);
// Gets 50% discount (buys $1 bonds for $0.50)

// 3. Admin changes discount back to 10%
bondDepository.setBondTerms(1, 1000);

// 4. Admin waits for vesting, sells at 100% profit
```

**Impact**: ⚠️ MEDIUM (admin profits, protocol loses)

**Current Mitigations**:
❌ **No timelock on setBondTerms()**
❌ **No event monitoring/alerts**

**Recommendations**:
1. **Add 24-hour timelock on setBondTerms()**
2. **Emit events for all parameter changes**
3. **Alert community on Discord/Twitter for changes**
4. **Require multi-sig approval (3-of-5)**

---

## 7. External Protocol Exploits

### ATTACK-7.1: Infrared Protocol Rug Pull

**Scenario**: Infrared protocol is malicious or hacked.

**Attack Steps**:
```solidity
// Apiary has staked 100,000 iBGT on Infrared

// 1. Infrared team (or hacker) upgrades contract
// New contract: withdraw() sends to attacker, not user

// 2. Apiary calls infraredAdapter.unstake(100000e18)
infrared.withdraw(100000e18);
// Instead of returning iBGT, sends to attacker

// 3. Apiary loses all staked iBGT (100k)
// Treasury becomes insolvent
```

**Impact**: 🔴 CRITICAL (if Infrared is compromised)

**Current Mitigations**:
✅ **emergencyWithdraw()**: Can pull out if detected early
❌ **No monitoring**: May not detect until too late
❌ **No staking limit**: Can stake 100% of treasury

**Recommendations**:
1. **Limit staking to 50% of treasury iBGT**:
   ```solidity
   function borrowIBGT(uint256 amount) external {
       require(totalBorrowed[IBGT] + amount <= totalReserves[IBGT] / 2, "Max 50% staked");
   }
   ```
2. **Monitor Infrared for upgrades** (auto-alert if proxy changed)
3. **Audit Infrared's upgrade mechanism** (timelock? multi-sig?)
4. **Diversify staking** (Phase 2: vBGT staking)

---

### ATTACK-7.2: Kodiak DEX Liquidity Drain

**Scenario**: Kodiak DEX is exploited, liquidity drained.

**Attack Steps**:
```solidity
// Kodiak APIARY/HONEY pool has $500k liquidity
// Apiary has $100k LP staked

// 1. Attacker exploits Kodiak (e.g., reentrancy in router)
// Drains all liquidity from pool

// 2. Apiary's LP tokens now worthless
// $100k lost

// 3. Oracle breaks (pair has no liquidity)
// All bond pricing fails
```

**Impact**: ⚠️ MEDIUM (LP loss + oracle failure)

**Current Mitigations**:
✅ **emergencyWithdraw()**: Can pull LP tokens before exploit
❌ **Single DEX dependency**: No backup
❌ **No liquidity monitoring**: Won't detect until too late

**Recommendations**:
1. **Monitor Kodiak pool liquidity** (alert if <$100k)
2. **Add backup DEX** (Uniswap V3)
3. **Add backup oracle** (Chainlink if available)
4. **Limit LP exposure** (max 30% of treasury in LP)

---

## 8. Economic Manipulation

### ATTACK-8.1: Bond Discount Arbitrage Loop

**Attacker Goal**: Continuously arbitrage bond discount.

**Prerequisites**:
- Bond discount ≥ 10%
- Short vesting period (1-3 days)
- Liquid secondary market

**Attack Steps**:
```solidity
// Day 1: Buy bonds at 10% discount
bondDepository.deposit(10000e18 /* iBGT */, maxPrice, attacker);
// Receives bonds for 11,000 APIARY (worth $11k)
// Paid $10k iBGT

// Day 2-4: Wait for vesting (partial)
// 33% vested per day (if 3-day vesting)

// Day 2: Redeem 33% (3,666 APIARY)
bondDepository.redeem(attacker, false);
// Sell on DEX for $3,666

// Day 3: Redeem 33% (3,666 APIARY)
// Sell for $3,666

// Day 4: Redeem 34% (3,668 APIARY)
// Sell for $3,668

// Total received: $11k
// Total paid: $10k
// Profit: $1k (10%)

// Repeat daily (compound profits)
```

**Impact**: 🟡 LOW (intended feature, but could be abused at scale)

**Current Mitigations**:
✅ **Vesting period**: Delays profit realization
✅ **maxDebt limit**: Caps total bonds

**Exploitation Conditions**:
- High discount (>10%)
- Short vesting (<5 days)
- Unlimited bonds

**Recommendations**:
1. **Limit discount to 5-7%** (reduce arbitrage profit)
2. **Extend vesting to 7 days minimum**
3. **Add per-epoch bond limit**:
   ```solidity
   mapping(uint256 => uint256) public bondsPerEpoch;
   
   function deposit(...) external {
       uint256 currentEpoch = block.timestamp / 8 hours;
       require(bondsPerEpoch[currentEpoch] < MAX_PER_EPOCH, "Epoch limit");
       bondsPerEpoch[currentEpoch] += payout;
   }
   ```
4. **Implement bond decay** (discount decreases as bonds sold)

---

### ATTACK-8.2: Pre-Sale Dump Attack

**Attacker Goal**: Buy max pre-sale, dump after TGE.

**Prerequisites**:
- Pre-sale 110% bonus
- Low liquidity at TGE
- No vesting cliff

**Attack Steps**:
```solidity
// Pre-sale: Buy 100 APIARY for 100 HONEY
preSaleBond.purchaseApiary(100e18, merkleProof);
// Receives 110 APIARY (with 110% bonus)

// TGE Day 1: 1/30 vests (3.66 APIARY)
preSaleBond.unlockApiary();
// Sell 3.66 APIARY immediately on DEX
// If liquidity is low, dumps price 10%

// Day 2-30: Unlock and sell daily (3.66 APIARY/day)
// Continuous sell pressure for 30 days

// If many participants do this:
// 10,000 APIARY * 1.1 = 11,000 APIARY vesting
// 366 APIARY dumped per day (for 30 days)
// Price crashes from sell pressure
```

**Impact**: ⚠️ MEDIUM (price suppression post-TGE)

**Current Mitigations**:
✅ **30-day vesting**: Spreads sell pressure
✅ **Purchase limits**: Caps per-user amount
❌ **No vesting cliff**: Can sell from day 1

**Recommendations**:
1. **Add 7-day cliff** (0% unlock, then linear 23 days):
   ```solidity
   function calculateVested(address user) internal view returns (uint256) {
       uint256 elapsed = block.timestamp - tgeStartTime;
       if (elapsed < 7 days) return 0; // Cliff
       
       uint256 vestedTime = elapsed - 7 days;
       uint256 vestingPeriod = 23 days;
       // Linear vesting after cliff
   }
   ```
2. **Add sell limits post-TGE** (max 10% of holdings per week)
3. **Bootstrap liquidity before TGE** ($100k+ TVL)

---

## 9. Sybil Attacks

### ATTACK-9.1: Pre-Sale Whitelist Bypass

**Attacker Goal**: Buy more than allowed using multiple addresses.

**Prerequisites**:
- Merkle whitelist
- Per-address purchase limit (100 APIARY)
- No KYC

**Attack Steps**:
```solidity
// Attacker controls 50 addresses (all whitelisted)

// Address 1: Buy 100 APIARY
preSaleBond.purchaseApiary(100e18, proof1);

// Address 2: Buy 100 APIARY
preSaleBond.purchaseApiary(100e18, proof2);

// ... Address 50: Buy 100 APIARY

// Total: 5,000 APIARY (with 110% bonus = 5,500 APIARY)
// Exceeds intended limit
```

**Impact**: 🟡 LOW (intended for early supporters, not critical)

**Current Mitigations**:
✅ **Merkle whitelist**: Limits participants
❌ **No Sybil resistance**: One person can have many addresses

**Recommendations**:
1. **Implement KYC for large purchases** (>50 APIARY)
2. **Off-chain monitoring** (flag similar behavior patterns)
3. **Add purchase limit per IP/device** (off-chain enforcement)
4. **Use Gitcoin Passport or similar Sybil resistance**

---

## 10. MEV Extraction

### ATTACK-10.1: Generalized Front-Running Bot

**Attacker Goal**: Automate front-running of all protocol transactions.

**Attack Steps**:
```solidity
// Bot monitors mempool for Apiary transactions

// If bond deposit detected:
//   - Front-run with larger deposit (increase debt)
//   - Victim pays more or reverts

// If yield execution detected:
//   - Sandwich attack (front-run + back-run swaps)
//   - Extract 5-10% of yield value

// If rebase detected:
//   - Front-run with stake (earn immediate yield)
//   - Back-run with unstake (if no warmup)

// Automated, continuous extraction
```

**Impact**: ⚠️ MEDIUM (5-10% value leaked per transaction)

**Current Mitigations**:
✅ **Slippage protection**: Limits some MEV
❌ **Public mempool**: Transactions visible

**Recommendations**:
1. **Use Flashbots Protect** (private mempool)
2. **Implement delayed execution**:
   - User submits intent (hashed)
   - Execution happens N blocks later (commit-reveal)
3. **Add MEV protection module**:
   ```solidity
   function executeYieldWithProtection() external {
       // Use Flashbots auction or similar
       // Ensure TX not visible in public mempool
   }
   ```

---

## Attack Severity Summary

**Critical (Immediate Fix Required)**:
1. 🔴 Flash loan yield extraction (if warmup = 0)
2. 🔴 Oracle staleness exploitation
3. 🔴 Malicious ERC20 reentrancy (if bad token approved)
4. 🔴 Admin key compromise (all funds drained)
5. 🔴 Infrared rug pull (if >50% staked)

**High (Fix Before Mainnet)**:
1. 🟠 TWAP oracle manipulation (if window < 1 hour)
2. 🟠 Yield sandwich attacks (if slippage > 1%)
3. 🟠 Allocation limit bypass

**Medium (Monitor & Mitigate)**:
1. 🟡 Flash loan LP manipulation
2. 🟡 Bond front-running
3. 🟡 Pre-sale dump
4. 🟡 MEV extraction

**Low (Acceptable Risk)**:
1. 🟢 Bond capacity griefing
2. 🟢 Pre-sale Sybil attack
3. 🟢 Bond discount arbitrage

---

**For mitigations, see [SECURITY.md](./SECURITY.md)**
**For testing, see [TEST_COVERAGE.md](./TEST_COVERAGE.md)**
