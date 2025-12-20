# Apiary Protocol Audit Readiness Checklist

Comprehensive checklist to prepare Apiary protocol for security audit.

---

## Pre-Audit Requirements

### ✅ Documentation Complete

- [x] **ARCHITECTURE.md** - System overview, contract relationships, trust model
- [x] **CONTRACTS.md** - Detailed contract reference with all functions
- [x] **SECURITY.md** - Known risks, mitigations, security analysis
- [x] **INVARIANTS.md** - Protocol invariants that must hold
- [x] **ATTACK_VECTORS.md** - Detailed attack scenarios and mitigations
- [x] **TEST_COVERAGE.md** - Test suite analysis and coverage gaps
- [x] **AUDIT_READINESS_CHECKLIST.md** - This document
- [x] **QUESTIONS_FOR_AUDITORS.md** - Specific areas of concern
- [x] **AUDIT_SCOPE.md** - Contracts in scope, priorities

### ⏳ Code Quality

#### NatSpec Comments
- [ ] All public/external functions have `@notice`
- [ ] All parameters have `@param` descriptions
- [ ] All return values have `@return` descriptions
- [ ] Complex internal logic has `@dev` explanations
- [ ] All events documented
- [ ] All custom errors documented

**Current Status**: ~60% complete
**Action**: Add missing NatSpec to all contracts

#### Compiler Warnings
- [ ] Zero compiler warnings with Solidity 0.8.26
- [ ] No unused variables
- [ ] No unused imports
- [ ] No unreachable code

**Run**: `forge build` and check for warnings

#### Code Style
- [ ] Consistent naming conventions
- [ ] Proper indentation (4 spaces)
- [ ] No magic numbers (use constants)
- [ ] Clear variable names
- [ ] Functions <50 lines where possible

### ⏳ Security Checks

#### Access Control
- [ ] All admin functions use `onlyOwner` or role-based checks
- [ ] No functions missing access control
- [ ] Ownership transferred to multi-sig (not EOA)
- [ ] Deployer has renounced all roles
- [ ] Critical functions have timelock (48h)

**Current Issues**:
- ⚠️ No timelock on `setYieldManager()`, `setInfraredAdapter()`, `setKodiakAdapter()`
- ⚠️ No multi-sig enforcement (manual check needed)

#### Reentrancy Protection
- [ ] All external calls protected with `ReentrancyGuard`
- [ ] Checks-Effects-Interactions pattern followed
- [ ] No external calls in loops
- [ ] No delegate calls to untrusted contracts

**Status**: ✅ Most contracts have ReentrancyGuard

#### Integer Safety
- [ ] All contracts use Solidity 0.8+ (built-in overflow protection)
- [ ] No `unchecked` blocks bypassing overflow checks
- [ ] All downcasts (uint256 → uint128) validated
- [ ] All multiplication before division for precision

**Status**: ✅ Solidity 0.8.26 used everywhere

#### Input Validation
- [ ] All functions validate inputs (non-zero, within bounds)
- [ ] All addresses checked for zero address
- [ ] All amounts checked for min/max limits
- [ ] All percentages checked ≤ 10000 (100%)

**Current Issues**:
- ⚠️ `setSplitConfig()` doesn't validate sum = 10000
- ⚠️ Some functions missing zero address checks

### ⏳ Economic Security

#### Allocation Limits
- [ ] Total allocations sum ≤ 200,000 APIARY
- [ ] Each allocation verified in deployment script
- [ ] Allocations cannot be changed after set
- [ ] No way to bypass allocation limits

**Manual Check**: Verify deployment script sets:
- Treasury: 40,000
- Pre-sale: 10,000  
- iBGT Bond: 30,000
- LP Bond: 30,000
- Reserve: 30,000
- **Total: 140,000** ✅ (60k reserved for future)

#### Bond Economics
- [ ] Bond discount ≤ 10%
- [ ] Vesting period ≥ 5 days
- [ ] Max debt limits set per bond
- [ ] Bond pricing uses TWAP (not spot)

**Current Settings**: Verify in deployment scripts

#### Oracle Safety
- [ ] TWAP window ≥ 1 hour
- [ ] minimumUpdateInterval ≥ 30 minutes
- [ ] Oracle staleness check in bond deposit
- [ ] Price change circuit breaker (±20%)

**Current Issues**:
- ⚠️ TWAP window unknown (check oracle config)
- ❌ No staleness check in bond deposit
- ❌ No price change circuit breaker

#### Yield Distribution
- [ ] Split percentages always sum to 10000
- [ ] Slippage tolerance ≤ 100 bps (1%)
- [ ] Min yield amount set (prevent dust)
- [ ] Max execution amount set (limit risk)

**Current Issues**:
- ⚠️ Split validation not enforced in `setSplitConfig()`

### ⏳ External Dependencies

#### Infrared Protocol
- [ ] Infrared contracts audited
- [ ] Infrared upgrade mechanism reviewed (timelock?)
- [ ] Staking limit set (max 50% of treasury)
- [ ] Emergency withdrawal tested
- [ ] Monitor for Infrared upgrades

**Action**: Audit Infrared integration

#### Kodiak DEX
- [ ] Kodiak contracts audited
- [ ] Kodiak pool liquidity monitored (alert if <$100k)
- [ ] Alternative DEX configured (backup)
- [ ] Slippage tolerance conservative (0.5-1%)

**Action**: Set up monitoring

#### Berachain Tokens
- [ ] iBGT contract verified on explorer
- [ ] HONEY contract verified on explorer
- [ ] BGT contract verified on explorer
- [ ] Peg monitoring (iBGT/BGT, HONEY/USD)

### ⏳ Testing

#### Unit Test Coverage
- [ ] ApiaryToken: 95%+
- [ ] sApiary: 95%+
- [ ] ApiaryTreasury: 95%+
- [ ] ApiaryStaking: 95%+
- [ ] ApiaryBondDepository: 95%+
- [ ] ApiaryPreSaleBond: 95%+
- [ ] ApiaryYieldManager: 95%+
- [ ] ApiaryInfraredAdapter: 95%+
- [ ] ApiaryKodiakAdapter: 95%+
- [ ] **ApiaryUniswapV2TwapOracle: 95%+** ⚠️ CRITICAL (currently ~40%)

**Current**: ~84% average

#### Integration Tests
- [ ] Full bond lifecycle tested
- [ ] Full staking lifecycle tested
- [ ] Full yield distribution tested
- [ ] Multi-user scenarios tested
- [ ] Failure cascades tested

**Current**: ~68%

#### Fuzz Tests
- [ ] All parameter bounds tested
- [ ] Edge cases (zero, max uint) tested
- [ ] 10,000+ fuzz runs pass
- [ ] No unexpected reverts

**Current**: ~59%, needs expansion

#### Invariant Tests
- [ ] Total supply cap invariant
- [ ] Supply equals balances invariant
- [ ] Staked equals index invariant
- [ ] Total debt consistency invariant
- [ ] Treasury iBGT accounting invariant
- [ ] Split percentages sum invariant
- [ ] Handler-based invariant testing implemented

**Current**: ~3% ⚠️ CRITICAL GAP

#### Attack Simulation Tests
- [ ] Flash loan attack tests
- [ ] Oracle manipulation tests
- [ ] Front-running tests
- [ ] Sandwich attack tests
- [ ] Admin compromise tests
- [ ] External protocol failure tests

**Current**: 0% ⚠️ CRITICAL GAP

### ⏳ Deployment

#### Deployment Scripts
- [x] Individual deployment scripts (01-06)
- [x] Master orchestration script (DeployAll.s.sol)
- [x] Configuration script (07_ConfigureProtocol.s.sol)
- [x] Verification script (VerifyDeployment.s.sol)
- [x] Deployment guide (DEPLOYMENT_GUIDE.md)

#### Environment Variables
- [ ] All variables documented in `.env.example`
- [ ] Testnet deployment successful
- [ ] Testnet verification successful
- [ ] Mainnet variables prepared (not committed!)

#### Post-Deployment Verification
- [ ] All 45+ checks in VerifyDeployment.s.sol pass
- [ ] Ownership transferred to multi-sig
- [ ] Deployer access revoked
- [ ] Contract addresses recorded
- [ ] Etherscan/Berascan verification complete

### ⏳ Operational Security

#### Multi-Sig Setup
- [ ] Gnosis Safe deployed
- [ ] 3-of-5 or 5-of-9 signers configured
- [ ] All signers identified and KYC'd
- [ ] Test transaction executed successfully
- [ ] All contracts owned by multi-sig

#### Monitoring & Alerts
- [ ] Oracle update monitoring (alert if not updated 2h)
- [ ] Pool liquidity monitoring (alert if <$100k)
- [ ] Large transactions monitoring (alert if >$10k)
- [ ] Infrared upgrade monitoring
- [ ] Kodiak pool monitoring
- [ ] Discord/Telegram alerts configured

#### Emergency Procedures
- [ ] Emergency pause runbook documented
- [ ] Emergency withdrawal runbook documented
- [ ] Emergency contacts list
- [ ] Incident response plan
- [ ] Multi-sig signer coordination process

---

## Audit Scope Verification

### In-Scope Contracts (12 total)

#### Core Contracts (5)
- [ ] `src/ApiaryToken.sol` - Priority: 🔴 CRITICAL
- [ ] `src/sApiary.sol` - Priority: 🔴 CRITICAL
- [ ] `src/ApiaryTreasury.sol` - Priority: 🔴 CRITICAL
- [ ] `src/ApiaryStaking.sol` - Priority: 🟠 HIGH
- [ ] `src/ApiaryStakingWarmup.sol` - Priority: 🟡 MEDIUM

#### Bond Contracts (4)
- [ ] `src/ApiaryBondDepository.sol` (iBGT) - Priority: 🟠 HIGH
- [ ] `src/ApiaryBondDepository.sol` (LP) - Priority: 🟠 HIGH
- [ ] `src/ApiaryPreSaleBond.sol` - Priority: 🟠 HIGH
- [ ] `src/ApiaryUniswapV2TwapOracle.sol` - Priority: 🔴 CRITICAL

#### Yield Management (3)
- [ ] `src/ApiaryYieldManager.sol` - Priority: 🔴 CRITICAL (most complex)
- [ ] `src/ApiaryInfraredAdapter.sol` - Priority: 🟠 HIGH
- [ ] `src/ApiaryKodiakAdapter.sol` - Priority: 🟠 HIGH

### Out-of-Scope
- Infrared protocol contracts (external)
- Kodiak DEX contracts (external)
- Berachain token contracts (external)
- Deployment scripts (informational only)

---

## Critical Issues to Address Before Audit

### 🔴 CRITICAL (Must Fix)

1. **Oracle Test Coverage**
   - Current: ~40%
   - Target: 95%
   - Add: TWAP manipulation tests, staleness tests, circuit breaker tests

2. **Invariant Test Suite**
   - Current: 4 invariants
   - Target: 15+ invariants
   - Add: Handler-based testing, ghost variables, comprehensive invariants

3. **Flash Loan Protection**
   - Current: `lastTimeStaked` tracked but not enforced
   - Fix: Add `lastTimeStaked` check in `unstake()`
   - Test: Flash loan attack simulations

4. **Split Configuration Validation**
   - Current: No sum validation
   - Fix: Add `require(sum == 10000)` in `setSplitConfig()`
   - Test: Fuzz test with invalid splits

5. **Oracle Staleness Check**
   - Current: No check in bond deposit
   - Fix: Add `require(block.timestamp - oracle.blockTimestampLast() < 1 hours)`
   - Test: Deposit with stale oracle should revert

### 🟠 HIGH (Strongly Recommend)

1. **Timelock for Critical Functions**
   - Add 48h timelock for:
     - `setYieldManager()`
     - `setInfraredAdapter()`
     - `setKodiakAdapter()`
     - `setBondTerms()`

2. **Borrowing Limit**
   - Add max 50% limit in `borrowIBGT()`
   - Prevents single point of failure risk

3. **Price Change Circuit Breaker**
   - Add ±20% limit in oracle `update()`
   - Prevents manipulation

4. **Attack Simulation Tests**
   - Add flash loan attack tests
   - Add sandwich attack tests
   - Add front-running tests

5. **NatSpec Completion**
   - Add missing NatSpec to all contracts
   - Target: 100% coverage

### 🟡 MEDIUM (Recommend)

1. **Multi-DEX Support**
   - Add backup DEX for swaps
   - Reduces single point of failure

2. **Oracle Aggregation**
   - Use median of 3 oracles
   - Reduces manipulation risk

3. **Vesting Cliff**
   - Add 7-day cliff to pre-sale vesting
   - Reduces dump pressure

4. **Gas Optimization**
   - Review gas usage in hot paths
   - Optimize `executeYield()` flow

---

## Questions for Auditors

See [QUESTIONS_FOR_AUDITORS.md](./QUESTIONS_FOR_AUDITORS.md) for detailed list.

**Top 3 Questions**:
1. Is `lastTimeStaked` enforcement sufficient to prevent flash loan yield extraction?
2. Can TWAP oracle be manipulated with sustained price manipulation (30min-1h)?
3. Is iBGT borrowing by YieldManager safe without on-chain repayment enforcement?

---

## Audit Timeline

### Pre-Audit (2-3 weeks)
- [ ] Week 1: Fix critical issues (oracle tests, invariants, flash loan protection)
- [ ] Week 2: Address high priority items (timelock, borrowing limit, NatSpec)
- [ ] Week 3: Final review, testnet deployment, verification

### Audit (3-4 weeks)
- [ ] Week 1: Initial review by auditors
- [ ] Week 2-3: Auditor deep dive, questions, findings
- [ ] Week 4: Final report, remediation planning

### Post-Audit (1-2 weeks)
- [ ] Week 1: Fix critical/high findings
- [ ] Week 2: Re-audit (if needed), final approval

---

## Sign-Off Checklist

Before submitting to auditors:

- [ ] All critical issues addressed
- [ ] Test coverage ≥85% overall
- [ ] Invariant tests implemented
- [ ] Attack simulations pass
- [ ] NatSpec 100% complete
- [ ] Deployment scripts tested on testnet
- [ ] Multi-sig configured
- [ ] Monitoring set up
- [ ] Emergency procedures documented
- [ ] Questions for auditors prepared
- [ ] Audit scope finalized

---

**Prepared by**: [Your Team]
**Date**: [Date]
**Protocol Version**: v1.0
**Audit Firm**: [TBD]
**Target Audit Start**: [Date]
