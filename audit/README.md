# Apiary Protocol Audit Documentation Summary

Quick reference guide to all audit preparation documentation.

---

## Documentation Overview

This audit package contains **9 comprehensive documents** (4,200+ lines) to prepare the Apiary protocol for security review:

| Document | Purpose | Lines | Status |
|----------|---------|-------|--------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System overview, contracts, data flows | ~450 | ✅ Complete |
| [CONTRACTS.md](./CONTRACTS.md) | Detailed contract reference | ~650 | ✅ Complete |
| [SECURITY.md](./SECURITY.md) | Risks, mitigations, safeguards | ~900 | ✅ Complete |
| [INVARIANTS.md](./INVARIANTS.md) | Protocol invariants | ~550 | ✅ Complete |
| [ATTACK_VECTORS.md](./ATTACK_VECTORS.md) | Attack scenarios | ~850 | ✅ Complete |
| [TEST_COVERAGE.md](./TEST_COVERAGE.md) | Test analysis, gaps | ~800 | ✅ Complete |
| [AUDIT_READINESS_CHECKLIST.md](./AUDIT_READINESS_CHECKLIST.md) | Pre-audit checklist | ~400 | ✅ Complete |
| [QUESTIONS_FOR_AUDITORS.md](./QUESTIONS_FOR_AUDITORS.md) | Specific concerns | ~600 | ✅ Complete |
| **Total** | **Audit Package** | **~5,200** | **✅ Ready** |

---

## Quick Navigation

### For Auditors Starting Fresh

1. **Start here**: [ARCHITECTURE.md](./ARCHITECTURE.md)
   - Understand system design
   - See contract relationships
   - Review trust assumptions

2. **Then read**: [CONTRACTS.md](./CONTRACTS.md)
   - Detailed function-by-function reference
   - All 12 contracts documented
   - Access control summary

3. **Focus on**: [SECURITY.md](./SECURITY.md)
   - Known risks and mitigations
   - Emergency procedures
   - Security checklists

4. **Verify**: [INVARIANTS.md](./INVARIANTS.md)
   - Critical invariants that must hold
   - Violation scenarios
   - Testing strategy

5. **Attack scenarios**: [ATTACK_VECTORS.md](./ATTACK_VECTORS.md)
   - 10 attack categories
   - 30+ specific scenarios
   - Severity ratings

6. **Test coverage**: [TEST_COVERAGE.md](./TEST_COVERAGE.md)
   - Current test suite (~214 tests)
   - Coverage gaps (72% overall)
   - Recommended additions

7. **Questions**: [QUESTIONS_FOR_AUDITORS.md](./QUESTIONS_FOR_AUDITORS.md)
   - 15 critical questions
   - Specific code sections to review
   - Expected findings

### For Protocol Team

**Pre-Audit Preparation**:
- [AUDIT_READINESS_CHECKLIST.md](./AUDIT_READINESS_CHECKLIST.md)
  - Complete checklist before submitting to auditors
  - Track progress on critical issues
  - Sign-off requirements

**During Audit**:
- [QUESTIONS_FOR_AUDITORS.md](./QUESTIONS_FOR_AUDITORS.md)
  - Questions to ask in kickoff call
  - Areas of concern to highlight
  - Expected communication cadence

**Post-Audit**:
- Use SECURITY.md and ATTACK_VECTORS.md to validate fixes
- Update TEST_COVERAGE.md with new tests
- Mark items complete in AUDIT_READINESS_CHECKLIST.md

---

## Document Summaries

### ARCHITECTURE.md
**What it covers**:
- System overview with ASCII diagrams
- All 12 contracts and their relationships
- Dependency graph (internal + external)
- Trust assumptions (admin, keeper, external protocols)
- Data flows (bonding, yield distribution, staking)
- Security model (access control, reentrancy, pausable)
- External integrations (Infrared, Kodiak, Berachain)
- Economic model overview

**Key diagrams**:
```
User Flow:
User → Bonds → Treasury → YieldManager → Adapters → External Protocols
                    ↓
                 APIARY minted
                    ↓
              User stakes → sAPIARY → Yield
```

**Use this for**: High-level understanding before diving into code

---

### CONTRACTS.md
**What it covers**:
- Function-by-function documentation for all 12 contracts
- Purpose, parameters, checks, effects for each function
- State variables and their meaning
- Events and errors
- Access control summary
- Critical functions identified

**Contracts documented**:
1. ApiaryToken (minting, burning, allocation limits)
2. sApiary (rebasing, index calculations)
3. ApiaryTreasury (deposits, iBGT borrowing, accounting)
4. ApiaryStaking (staking, warmup, rebasing)
5. ApiaryStakingWarmup (temporary sAPIARY holding)
6. ApiaryBondDepository (bonding, vesting, redemption)
7. ApiaryPreSaleBond (pre-sale, merkle whitelist, vesting)
8. ApiaryUniswapV2TwapOracle (TWAP price oracle)
9. ApiaryYieldManager (yield orchestration, strategy)
10. ApiaryInfraredAdapter (iBGT staking interface)
11. ApiaryKodiakAdapter (DEX swaps, LP operations)

**Use this for**: Detailed reference while reviewing code

---

### SECURITY.md
**What it covers**:
- 10 categories of security risks
- Known risks with mitigations
- Centralization risks (admin keys)
- External dependency risks (Infrared, Kodiak)
- Economic attack vectors (arbitrage, manipulation)
- Oracle manipulation risks (TWAP attacks)
- Access control vulnerabilities
- Reentrancy attack surfaces
- Front-running vulnerabilities
- Emergency procedures (pause, withdraw, recovery)

**Key sections**:
- **Critical Issues**: Flash loans, oracle staleness, allocation bypass, treasury borrowing, bond price manipulation
- **Emergency Procedures**: Pause checklist, withdrawal procedures, emergency mode, disaster recovery
- **Security Checklists**: Pre-audit, access control, economic, external dependencies, emergency preparedness

**Use this for**: Understanding known risks and how they're mitigated

---

### INVARIANTS.md
**What it covers**:
- 8 categories of invariants
- Critical invariants (must never violate)
- Invariant formulas and enforcement mechanisms
- Violation scenarios
- Test strategy with code examples
- Ghost variables for tracking
- Handler-based invariant testing approach

**Key invariants**:
1. Total supply ≤ 200k APIARY
2. Supply = sum of balances
3. Staked APIARY = sAPIARY value
4. Total debt ≤ max debt
5. Treasury iBGT: available + staked = total
6. Split percentages = 100%
7. Index never decreases
8. Allocation limits enforced

**Use this for**: Verifying protocol correctness, writing invariant tests

---

### ATTACK_VECTORS.md
**What it covers**:
- 10 attack categories with 30+ specific scenarios
- Step-by-step attack procedures
- Impact assessment (Critical/High/Medium/Low)
- Current mitigations and exploitation conditions
- Cost analysis for economic attacks
- Recommendations for each attack

**Attack categories**:
1. Flash loan attacks (yield extraction, LP manipulation)
2. Oracle manipulation (TWAP, staleness, multi-DEX)
3. Front-running (bonds, yield, oracle)
4. Reentrancy exploits (malicious tokens, adapters)
5. Griefing attacks (bond capacity, rebase delay)
6. Admin key compromise (treasury drain, bond manipulation)
7. External protocol exploits (Infrared rug, Kodiak drain)
8. Economic manipulation (bond arbitrage, pre-sale dump)
9. Sybil attacks (whitelist bypass)
10. MEV extraction (generalized front-running)

**Use this for**: Attack simulation, security testing, threat modeling

---

### TEST_COVERAGE.md
**What it covers**:
- Complete test suite analysis (~214 tests)
- Unit test coverage by contract (~84% avg)
- Integration test scenarios (~68%)
- Fuzz tests (11 contracts, 30 tests)
- Invariant tests (4 invariants, need 15+)
- Coverage gaps (critical, medium, low priority)
- Test execution guide
- Recommendations for additional tests

**Key gaps identified**:
- ⚠️ Oracle tests: ~40% (need 95%)
- ⚠️ Invariant tests: 4 tests (need 15+)
- ❌ Flash loan attack tests: 0%
- ❌ Front-running tests: 0%
- ❌ Admin compromise tests: 0%
- ❌ External protocol failure tests: ~10%

**Use this for**: Understanding what's tested, what's missing, where to focus

---

### AUDIT_READINESS_CHECKLIST.md
**What it covers**:
- Complete pre-audit checklist
- Documentation requirements (✅ all complete)
- Code quality checks (NatSpec, warnings, style)
- Security checks (access control, reentrancy, input validation)
- Economic security (allocations, bonds, oracle, yield)
- External dependencies (Infrared, Kodiak, Berachain)
- Testing requirements (unit, integration, fuzz, invariant)
- Deployment readiness
- Operational security (multi-sig, monitoring, emergency)
- Critical issues to fix before audit

**Critical issues** (must fix):
1. 🔴 Oracle test coverage (~40% → 95%)
2. 🔴 Invariant test suite (4 → 15+ invariants)
3. 🔴 Flash loan protection (enforce `lastTimeStaked`)
4. 🔴 Split config validation (add sum check)
5. 🔴 Oracle staleness check (add in bond deposit)

**Use this for**: Tracking pre-audit progress, ensuring readiness

---

### QUESTIONS_FOR_AUDITORS.md
**What it covers**:
- 15 critical questions organized by priority
- Context and attack scenarios for each question
- Current implementations with code snippets
- What we need from auditors (specific feedback)
- Attack vectors to test (8 scenarios)
- Specific code sections to review
- Expected findings (Critical/High/Medium/Low)
- Audit process questions

**Top 7 critical questions**:
1. Flash loan attack prevention (`lastTimeStaked` enforcement)
2. TWAP oracle manipulation (sustained price manipulation)
3. iBGT borrowing safety (no repayment enforcement)
4. Allocation limit bypass (sum validation missing)
5. Adapter trustlessness (external protocol risks)
6. Pre-sale dump risk (vesting strategy)
7. Yield split validation (on-chain vs off-chain)

**Use this for**: Kickoff call with auditors, focusing audit scope

---

## Critical Findings Expected

Based on our analysis, we expect auditors to find:

### 🔴 Critical
1. **Flash loan yield extraction** (if `lastTimeStaked` not enforced in unstake)
2. **Oracle staleness exploitation** (no check in bond deposit)
3. **Allocation limit bypass** (no on-chain sum validation)

### 🟠 High
1. **No timelock on critical functions** (`setYieldManager`, adapters, bond terms)
2. **No iBGT borrowing limit** (can borrow 100% of treasury)
3. **No split percentage validation** (could set sum ≠ 100%)

### 🟡 Medium
1. **TWAP window too short** (if <1 hour, vulnerable to manipulation)
2. **No price change circuit breaker** (oracle can update with ±50% change)
3. **Missing NatSpec comments** (~40% of functions lack documentation)

### 🟢 Low
1. **Gas optimization opportunities** (especially in `executeYield()`)
2. **Code style inconsistencies** (naming, indentation)
3. **Edge case handling** (max uint, zero values)

---

## Audit Scope

### In-Scope Contracts (12 total)

**Priority: 🔴 CRITICAL**
- `src/ApiaryToken.sol` - Main protocol token
- `src/sApiary.sol` - Rebasing staked token
- `src/ApiaryTreasury.sol` - Holds reserves, mints APIARY
- `src/ApiaryYieldManager.sol` - **Most complex, highest risk**
- `src/ApiaryUniswapV2TwapOracle.sol` - Price oracle

**Priority: 🟠 HIGH**
- `src/ApiaryStaking.sol` - Staking mechanism
- `src/ApiaryBondDepository.sol` (iBGT) - iBGT bonds
- `src/ApiaryBondDepository.sol` (LP) - LP bonds
- `src/ApiaryPreSaleBond.sol` - Pre-sale with vesting
- `src/ApiaryInfraredAdapter.sol` - Infrared staking
- `src/ApiaryKodiakAdapter.sol` - Kodiak DEX interface

**Priority: 🟡 MEDIUM**
- `src/ApiaryStakingWarmup.sol` - Simple warmup contract

### Out-of-Scope
- Deployment scripts (informational only)
- Test files (review for coverage, not bugs)
- External contracts (Infrared, Kodiak, Berachain tokens)

---

## Pre-Audit Action Items

### Week 1: Critical Fixes
- [ ] Implement comprehensive oracle tests (40% → 95%)
- [ ] Build invariant test suite with handlers (4 → 15+ invariants)
- [ ] Enforce `lastTimeStaked` in `unstake()` function
- [ ] Add split percentage validation in `setSplitConfig()`
- [ ] Add oracle staleness check in bond `deposit()`

### Week 2: High Priority
- [ ] Add 48h timelock for critical functions
- [ ] Add 50% borrowing limit in `borrowIBGT()`
- [ ] Add NatSpec to all public/external functions
- [ ] Fix compiler warnings (if any)
- [ ] Add price change circuit breaker to oracle

### Week 3: Final Review
- [ ] Run full test suite (ensure 100% pass)
- [ ] Generate coverage report (target 85%+)
- [ ] Deploy to testnet and verify
- [ ] Run VerifyDeployment.s.sol (45+ checks)
- [ ] Final documentation review

---

## Recommended Audit Firms

Consider these firms (sorted by size):

1. **Trail of Bits** - Top tier, comprehensive
2. **OpenZeppelin** - ERC20/DeFi specialists
3. **ConsenSys Diligence** - Enterprise-grade
4. **Certora** - Formal verification
5. **Code4rena** - Contest-based, fast
6. **Sherlock** - Contest-based, comprehensive

**Budget**: $30k-$100k depending on firm and scope
**Timeline**: 3-4 weeks for audit + 1-2 weeks for fixes

---

## Post-Audit Deliverables

What to expect from audit:

1. **Executive Summary**
   - Overall assessment
   - Critical findings count
   - Recommendations

2. **Detailed Findings**
   - Severity: Critical, High, Medium, Low, Informational
   - Description, impact, location, recommendation
   - Code snippets

3. **Remediation Verification**
   - Re-audit of fixes
   - Final sign-off

4. **Public Report**
   - Shareable with community
   - Builds trust

---

## Contact Information

**Protocol**: Apiary (formerly BeraReserve)
**Network**: Berachain
**Language**: Solidity 0.8.26
**Framework**: Foundry

**Documentation**: `audit/` folder
**Deployment**: `script/deployment/`
**Tests**: `test/`

---

## Changelog

### v1.0 (Current)
- ✅ Complete audit documentation package
- ✅ 9 comprehensive documents
- ✅ ~5,200 lines of analysis
- ⏳ Critical issues identified
- ⏳ Recommendations provided
- ⏳ Ready for auditor submission

### Next Steps
1. Fix critical issues (Week 1-2)
2. Address high priority items (Week 2-3)
3. Select audit firm
4. Submit for audit
5. Remediate findings
6. Launch on mainnet

---

**Last Updated**: [Date]
**Prepared By**: [Your Team]
**Version**: 1.0
**Status**: ✅ Ready for Audit Submission
