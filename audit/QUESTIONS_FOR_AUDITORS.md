# Questions for Security Auditors

Critical questions and areas of concern for Apiary protocol security audit.

---

## Critical Security Questions

### 1. Flash Loan Attack Prevention

**Question**: Is our `lastTimeStaked` mechanism sufficient to prevent flash loan yield extraction attacks?

**Context**:
- `ApiaryToken.sol` tracks `lastTimeStaked[user]` when staking
- `ApiaryStaking.sol` has warmup period before unstaking
- Concern: If warmup = 0 or `lastTimeStaked` not checked, flash loan attack possible

**Attack Scenario**:
```solidity
// Flash loan 10,000 APIARY
// Stake → immediately unstake after rebase → profit from yield
// If no enforcement, attacker extracts yield without risk
```

**Our Implementation**:
```solidity
// ApiaryToken.sol line ~50
mapping(address => uint48) public lastTimeStaked;

// Called in stake():
lastTimeStaked[recipient] = uint48(block.timestamp);

// Question: Should we enforce this in unstake()?
function unstake(uint256 amount, bool trigger) external {
    // Missing: require(block.timestamp >= lastTimeStaked[msg.sender] + warmupPeriod)?
}
```

**What We Need from Auditors**:
1. Is `lastTimeStaked` tracking sufficient, or should we enforce minimum staking duration?
2. What's the optimal warmup period to prevent flash loans? (1 block? 1 epoch? 24h?)
3. Are there other flash loan attack vectors we haven't considered?

---

### 2. TWAP Oracle Manipulation

**Question**: Can our TWAP oracle be manipulated with sustained price manipulation over 30-60 minutes?

**Context**:
- `ApiaryUniswapV2TwapOracle.sol` uses cumulative price TWAP
- `minimumUpdateInterval` prevents rapid updates
- Bond prices depend on TWAP (not spot price)

**Attack Scenario**:
```solidity
// Attacker identifies TWAP window (e.g., 30 minutes)
// At minute 0: Pump APIARY price with large buy
// At minute 1-29: Keep price elevated
// At minute 29: Call oracle.update() → captures inflated price
// At minute 30: Buy bonds at "discounted" price (but real price already reverted)
```

**Our Implementation**:
```solidity
// ApiaryUniswapV2TwapOracle.sol
uint256 public minimumUpdateInterval; // Set to ?

function update() external {
    require(block.timestamp - blockTimestampLast >= minimumUpdateInterval);
    // ... calculate TWAP from cumulative prices
}
```

**What We Need from Auditors**:
1. What's the minimum safe TWAP window? (30min? 1h? 2h?)
2. Should we add price change circuit breaker? (e.g., revert if price moves >20% in one update)
3. Is cumulative price TWAP resistant to multi-block manipulation?
4. Should we aggregate multiple oracles (Kodiak + Uniswap + Chainlink)?

---

### 3. iBGT Borrowing Safety

**Question**: Is it safe for YieldManager to borrow iBGT from treasury without on-chain repayment enforcement?

**Context**:
- `ApiaryTreasury.borrowIBGT()` lends reserves to YieldManager
- No borrowing limit (can borrow 100% of available iBGT)
- No repayment deadline (trust-based repayment)
- If YieldManager compromised, all borrowed iBGT could be lost

**Attack Scenario**:
```solidity
// Admin key compromised
// Attacker sets malicious YieldManager
treasury.setYieldManager(attackerContract);

// Borrow all iBGT
treasury.borrowIBGT(1000000e18); // All reserves

// Malicious YieldManager transfers to attacker
// Treasury becomes insolvent
```

**Our Implementation**:
```solidity
// ApiaryTreasury.sol
function borrowIBGT(uint256 amount) external {
    require(msg.sender == yieldManager);
    require(availableBalance >= amount); // No limit check!
    
    availableBalance -= amount;
    totalStaked += amount;
    totalBorrowed[IBGT] += amount;
    
    IERC20(IBGT).safeTransfer(yieldManager, amount);
}

// Repayment is voluntary:
function repayIBGT(uint256 principal, uint256 yield) external {
    // No deadline enforcement
}
```

**What We Need from Auditors**:
1. Should we add borrowing limit? (e.g., max 50% of available iBGT)
2. Should we add repayment deadline with liquidation mechanism?
3. Should we add timelock for `setYieldManager()`? (48h delay)
4. Is multi-sig sufficient protection, or do we need more on-chain safeguards?

---

### 4. Allocation Limit Bypass

**Question**: Can admins bypass allocation limits by setting multiple allocations before deployment?

**Context**:
- `ApiaryToken.setAllocationLimit()` can only be called once per address
- Total supply cap is 200,000 APIARY
- No on-chain check that sum of all allocations ≤ 200,000

**Attack Scenario**:
```solidity
// Admin sets allocations during deployment:
setAllocationLimit(treasury, 50000e9);     // 50k
setAllocationLimit(preSale, 50000e9);      // 50k
setAllocationLimit(ibgtBond, 50000e9);     // 50k
setAllocationLimit(lpBond, 50000e9);       // 50k
setAllocationLimit(reserve, 50000e9);      // 50k
// Total: 250k > 200k cap!

// Each minter can mint up to their limit
// Total minted could exceed 200k
```

**Our Implementation**:
```solidity
// ApiaryToken.sol
uint256 public constant INITIAL_SUPPLY = 200_000e9;
mapping(address => uint256) public allocationLimits;

function setAllocationLimit(address minter, uint256 maxTokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(allocationLimits[minter] == 0); // One-time only
    // Missing: require(totalAllocated + maxTokens <= INITIAL_SUPPLY)
    
    allocationLimits[minter] = maxTokens;
    _grantRole(MINTER_ROLE, minter);
}

function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
    require(totalMintedSupply + amount <= INITIAL_SUPPLY); // Global check
    require(amount <= allocationLimits[msg.sender]); // Per-minter check
    // ...
}
```

**What We Need from Auditors**:
1. Should we add `totalAllocated` tracking to prevent over-allocation?
2. Is deployment script verification sufficient, or should we enforce on-chain?
3. What happens if allocations sum to exactly 200k but some are never used? (Locked forever?)

---

### 5. Adapter Trustlessness

**Question**: How can we make adapters (Infrared, Kodiak) more trustless?

**Context**:
- YieldManager calls external adapters for staking and swaps
- Adapters are upgradeable by owner
- If adapter is compromised or upgraded maliciously, all funds in adapter are at risk

**Current Trust Assumptions**:
- Infrared staking contract is secure
- Kodiak DEX is secure
- Neither will rug pull or upgrade maliciously

**Attack Scenario**:
```solidity
// Infrared upgrades staking contract
infraredStaking.upgradeTo(maliciousImplementation);

// Malicious implementation:
function withdraw(uint256 amount) external {
    // Send to attacker instead of user
    IBGT.transfer(ATTACKER, amount);
}

// Apiary calls infraredAdapter.unstake()
// Funds go to attacker
```

**Our Implementation**:
```solidity
// ApiaryInfraredAdapter.sol
function stake(uint256 amount) external onlyYieldManager {
    IERC20(ibgt).approve(address(infrared), amount);
    infrared.stake(amount); // Trust Infrared
    totalStaked += amount;
}

function unstake(uint256 amount) external onlyYieldManager {
    infrared.withdraw(amount); // Trust Infrared to return funds
    totalStaked -= amount;
}
```

**What We Need from Auditors**:
1. Should we limit staking to X% of treasury? (e.g., max 50%)
2. Should we monitor Infrared/Kodiak for upgrades and auto-pause if detected?
3. Should we add multiple adapter redundancy? (stake across 3 protocols)
4. Is emergency withdrawal sufficient, or do we need more proactive safeguards?

---

### 6. Pre-Sale Dump Risk

**Question**: Is 30-day linear vesting sufficient to prevent pre-sale dump?

**Context**:
- Pre-sale offers 110% bonus (buy 100 APIARY, get 110)
- Vesting is linear over 30 days (3.67% per day)
- No vesting cliff (can sell from day 1)

**Attack Scenario**:
```solidity
// Pre-sale: 10,000 users buy 100 APIARY each = 1M APIARY
// With 110% bonus: 1.1M APIARY to vest

// Day 1 after TGE: 1.1M * 3.67% = 40,370 APIARY unlocked
// If liquidity is only $100k, 40k APIARY dump crashes price
// Day 2-30: Continuous sell pressure
```

**Our Implementation**:
```solidity
// ApiaryPreSaleBond.sol
uint256 public constant VESTING_PERIOD = 30 days;

function calculateVested(address user) internal view returns (uint256) {
    uint256 elapsed = block.timestamp - tgeStartTime;
    if (elapsed >= VESTING_PERIOD) return apiaryPurchased;
    
    // Linear vesting (no cliff)
    return (apiaryPurchased * elapsed) / VESTING_PERIOD;
}
```

**What We Need from Auditors**:
1. Should we add vesting cliff? (e.g., 0% for 7 days, then linear 23 days)
2. Should we limit daily unlock? (e.g., max 5% per week)
3. What's optimal vesting period? (30d? 60d? 90d?)
4. Should we add sell limits post-TGE? (off-chain or on-chain?)

---

### 7. Yield Distribution Split Validation

**Question**: Should we enforce split percentages sum to 100% on-chain?

**Context**:
- `ApiaryYieldManager.setSplitConfig()` updates yield splits
- Currently no validation that splits sum to 10000 (100%)
- If sum ≠ 10000, funds could be lost or double-counted

**Attack Scenario**:
```solidity
// Admin (or compromised admin) sets invalid splits:
setSplitConfig({
    toHoney: 3000,     // 30%
    toApiaryLP: 3000,  // 30%
    toBurn: 3000,      // 30%
    toStakers: 0,
    toCompound: 0
});
// Sum = 9000 (90%) → 10% of yield goes nowhere (lost)

// Or sum > 10000:
setSplitConfig({
    toHoney: 5000,     // 50%
    toApiaryLP: 5000,  // 50%
    toBurn: 5000,      // 50%
    toStakers: 0,
    toCompound: 0
});
// Sum = 15000 (150%) → execution will revert or double-spend
```

**Our Implementation**:
```solidity
// ApiaryYieldManager.sol
function setSplitConfig(SplitConfig memory newConfig) external onlyOwner {
    // Missing validation!
    splitConfig = newConfig;
    emit SplitConfigUpdated(...);
}

// Invariant test exists but not enforced on-chain:
function invariant_SplitPercentagesSum() public view {
    assertEq(
        config.toHoney + config.toApiaryLP + config.toBurn + 
        config.toStakers + config.toCompound,
        10000
    );
}
```

**What We Need from Auditors**:
1. Should we add on-chain validation? (require sum == 10000)
2. Is off-chain invariant testing sufficient?
3. What happens if execution logic doesn't handle sum ≠ 10000 gracefully?

---

## Medium Priority Questions

### 8. Reentrancy in Multi-Hop Flows

**Question**: Are there reentrancy risks in yield execution flow across multiple contracts?

**Flow**:
```
YieldManager.executeYield()
  → Treasury.borrowIBGT()
    → InfraredAdapter.claimRewards()
      → KodiakAdapter.swap()
        → KodiakAdapter.addLiquidity()
          → KodiakAdapter.stakeLPTokens()
      → Treasury.repayIBGT()
```

Each contract has `ReentrancyGuard`, but is there a risk of reentrancy across contracts?

---

### 9. Bond Debt Decay

**Question**: Does debt decay mechanism work as expected under edge cases?

```solidity
// ApiaryBondDepository.sol
function _decayDebt() internal {
    totalDebt -= (totalDebt * (block.timestamp - lastDecay)) / terms.vestingTerm;
    lastDecay = block.timestamp;
}
```

Edge cases:
- What if `block.timestamp - lastDecay > vestingTerm`? (Debt underflows to 0?)
- What if no one bonds for months? (Stale debt decay)

---

### 10. sApiary Rebase Limits

**Question**: Should we add max rebase per epoch to prevent index manipulation?

```solidity
// sApiary.sol
function rebase(uint256 profit, uint256 epoch) external {
    require(msg.sender == stakingContract);
    // Missing: require(profit <= totalSupply * MAX_REBASE_BPS / 10000)?
    
    _gonsPerFragment -= ... // Increases index
}
```

What if staking contract has bug and rebases with 1000x profit?

---

### 11. Warmup Retrieval Edge Cases

**Question**: What happens if warmup period changes mid-staking?

```solidity
// User stakes with warmup = 7 days
// Admin changes warmup = 14 days
// Can user still retrieve after 7 days, or must wait 14?
```

---

### 12. Oracle Price Deviation

**Question**: How should we handle extreme price volatility?

Example:
- APIARY trades at $1 for months
- Sudden pump to $10 in 1 hour
- Oracle updates to $10
- Bond prices jump 10x
- Users panic

Should we add gradual price update mechanism or circuit breaker?

---

## Low Priority Questions

### 13. Gas Optimization

**Question**: Are there gas optimizations we should consider for high-frequency functions?

Functions to optimize:
- `executeYield()` (called daily/weekly)
- `rebase()` (called every epoch)
- `stake()` / `unstake()` (user-facing, high frequency)

---

### 14. Upgradeability

**Question**: Should any contracts be upgradeable (proxy pattern)?

Current: All contracts are non-upgradeable
Future: If critical bug found, must deploy new contracts and migrate

Trade-off:
- Upgradeable: Can fix bugs, but adds complexity and centralization risk
- Non-upgradeable: Immutable, but bugs are permanent

---

### 15. Multi-Chain Deployment

**Question**: Are there any Berachain-specific considerations for deployment?

Berachain differences:
- Block time: ~5-6 seconds (vs Ethereum 12s)
- Gas costs: Lower
- Tooling: Standard EVM

Do we need to adjust:
- Epoch length (blocks vs time)?
- TWAP window (blocks vs time)?
- Vesting periods (blocks vs time)?

---

## Attack Vectors to Test

Please specifically test these attack scenarios:

### 1. Flash Loan Yield Extraction
```solidity
// Flash loan APIARY → stake → rebase → unstake → repay → profit
```
**Expected**: Should fail due to warmup or lastTimeStaked check

### 2. TWAP Manipulation
```solidity
// Sustained price pump for 30-60 min → update oracle → buy bonds → dump
```
**Expected**: Should be unprofitable due to long TWAP window

### 3. Sandwich Attack on Yield Execution
```solidity
// Front-run executeYield() → manipulate DEX price → back-run → profit
```
**Expected**: Should fail due to slippage tolerance

### 4. Oracle Staleness Exploit
```solidity
// Don't update oracle for days → market price diverges → arbitrage bonds
```
**Expected**: Should fail due to staleness check (if implemented)

### 5. Admin Key Compromise
```solidity
// Attacker gets admin key → set malicious adapters → drain funds
```
**Expected**: Timelock should prevent immediate drainage

### 6. Infrared Rug Pull
```solidity
// Infrared upgrades to malicious contract → steals all staked iBGT
```
**Expected**: Emergency withdrawal should recover funds (if detected in time)

### 7. Pre-Sale Sybil Attack
```solidity
// Attacker controls 100 whitelisted addresses → buys max → dumps
```
**Expected**: Vesting should prevent immediate dump

### 8. Bond Griefing
```solidity
// Whale maxes out bond debt → legitimate users can't bond
```
**Expected**: Per-user limit should prevent monopolization (if implemented)

---

## Specific Code Sections to Review

Please pay special attention to:

1. **ApiaryToken.sol lines 50-100**: Allocation limit logic
2. **ApiaryTreasury.sol lines 150-200**: iBGT borrowing/repaying
3. **ApiaryYieldManager.sol lines 200-300**: Yield execution flow
4. **sApiary.sol lines 80-120**: Rebase mechanism
5. **ApiaryUniswapV2TwapOracle.sol lines 40-80**: TWAP calculation
6. **ApiaryBondDepository.sol lines 120-180**: Bond pricing and debt decay

---

## Expected Findings

We expect auditors may find:

**Critical**:
- Flash loan attack vector (if lastTimeStaked not enforced)
- Oracle manipulation (if TWAP window too short)
- Allocation limit bypass (if no sum validation)

**High**:
- Missing timelock on critical functions
- No borrowing limit on iBGT
- No split percentage validation

**Medium**:
- Missing NatSpec comments
- Gas optimization opportunities
- Edge cases in vesting/rebasing

**Low**:
- Code style inconsistencies
- Minor input validation improvements

---

## Questions About Audit Process

1. **Scope**: Are all 12 contracts in scope, or should we prioritize?
2. **Timeline**: What's expected audit duration? (3-4 weeks?)
3. **Remediation**: How many rounds of fixes/re-audit are typical?
4. **Report**: What format will findings be delivered in?
5. **Communication**: How often will we sync during audit? (daily? weekly?)
6. **Re-audit**: If critical issues found, what's re-audit timeline/cost?

---

## Additional Context for Auditors

### Protocol Goals
- Decentralized reserve currency on Berachain
- Bonding mechanism for protocol-owned liquidity
- Sustainable yield distribution to stakers
- Phase 1: 25/25/50 yield split (HONEY/burn/LP)
- Phase 2+: Dynamic yield based on market cap / total value ratio

### Key Innovations
- iBGT staking via Infrared for yield generation
- Kodiak LP for liquidity provision
- Two-token model (APIARY/sAPIARY) with rebasing
- Pre-sale with 110% bonus and linear vesting
- Multi-phase yield strategy

### Known Limitations
- Centralized oracle (working on multi-oracle)
- Single DEX (working on multi-DEX)
- Centralized admin (working on governance)
- No upgradeability (working on upgrade path)

---

**Prepared for**: [Audit Firm Name]
**Protocol**: Apiary (formerly BeraReserve)
**Version**: v1.0
**Contact**: [Your Team Email/Discord]
