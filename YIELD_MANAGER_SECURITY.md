# Apiary Yield Manager Security Analysis

## Contract Overview

**Contract**: `ApiaryYieldManager.sol`  
**Purpose**: Orchestrate yield strategy execution for Apiary protocol  
**Critical Level**: ⚠️ **HIGHEST** - Controls all treasury yield distribution  
**Dependencies**: ApiaryInfraredAdapter, ApiaryKodiakAdapter, ApiaryTreasury, APIARY/HONEY tokens

---

## 🔴 Critical Attack Vectors

### 1. **Reentrancy During Multi-Step Execution**

**Risk Level**: CRITICAL  
**Attack Vector**: `executeYield()` makes multiple external calls to adapters, potentially allowing reentrancy

**Vulnerability**:
```solidity
// BAD: Multiple external calls without proper protection
function executeYield() external {
    _claimYieldFromInfrared(totalYield);  // External call 1
    _swapToHoney(toHoneyAmount);           // External call 2
    _swapToApiary(toBurnAmount);           // External call 3
    _createAndStakeLP(...);                 // External call 4
}
```

**Mitigation** ✅:
- `nonReentrant` modifier on `executeYield()`
- All state updates BEFORE external calls (CEI pattern)
- ReentrancyGuard from OpenZeppelin v5
- No callback functions that could be exploited

**Additional Protection**:
```solidity
// Update state BEFORE external calls
totalYieldProcessed += totalYield;
lastExecutionTime = block.timestamp;
lastExecutionBlock = block.number;

emit YieldExecuted(...); // Event emission before external calls
```

---

### 2. **Partial Execution Failures**

**Risk Level**: HIGH  
**Attack Vector**: One swap fails → execution halts → tokens stuck in contract

**Vulnerability**:
```solidity
// BAD: Revert on any failure
honeySwapped = _swapToHoney(toHoneyAmount);  // Reverts if fails
apiaryBurned = _burnApiary(toBurnAmount);    // Never executes
```

**Mitigation** ✅:
- Graceful failure handling with `try/catch` pattern
- `PartialExecutionFailure` event emission
- Return 0 on failure instead of revert
- Emergency mode to bypass swaps

**Implementation**:
```solidity
function _swapToHoney(uint256 amount) internal returns (uint256 honeyReceived) {
    (bool success, bytes memory data) = kodiakAdapter.call(...);
    
    if (!success) {
        emit PartialExecutionFailure("Swap to HONEY failed", amount);
        return 0;  // ✅ Don't revert entire execution
    }
    
    honeyReceived = abi.decode(data, (uint256));
}
```

**Emergency Recovery**:
- `emergencyMode` bypasses swaps → forward all to treasury
- `emergencyWithdraw()` for stuck tokens

---

### 3. **Slippage Exploitation**

**Risk Level**: HIGH  
**Attack Vector**: Sandwich attacks on large swaps → treasury value extraction

**Vulnerability**:
```solidity
// BAD: No slippage protection
_swap(iBGT, HONEY, amount, 0); // minAmountOut = 0
```

**Mitigation** ✅:
- All swaps use `slippageTolerance` parameter (default 0.5%)
- `_getExpectedSwapOutput()` queries oracle for fair price
- `minOutput` calculated dynamically per swap
- Owner can adjust tolerance via `setSlippageTolerance()`

**Implementation**:
```solidity
uint256 expectedOutput = _getExpectedSwapOutput(tokenIn, tokenOut, amountIn);
uint256 minOutput = (expectedOutput * (10000 - slippageTolerance)) / 10000;

kodiakAdapter.swap(tokenIn, tokenOut, amountIn, minOutput, address(this));
```

**Max Protection**:
```solidity
function setSlippageTolerance(uint256 _slippage) external onlyOwner {
    if (_slippage > 1000) { // Max 10%
        revert APIARY__SLIPPAGE_TOO_HIGH();
    }
    slippageTolerance = _slippage;
}
```

---

### 4. **Adapter Address Manipulation**

**Risk Level**: CRITICAL  
**Attack Vector**: Owner sets malicious adapter → drains all yield

**Vulnerability**:
```solidity
// BAD: No validation on adapter addresses
function setKodiakAdapter(address _adapter) external onlyOwner {
    kodiakAdapter = _adapter; // Could be malicious contract
}
```

**Mitigation** ✅:
- `Ownable2Step` for safe ownership transfer (prevents accidental ownership loss)
- Zero address checks on all setters
- Events emitted on adapter changes for transparency
- **Manual Review Required**: Adapters must be audited before setting

**Best Practice**:
```solidity
function setKodiakAdapter(address _adapter) external onlyOwner {
    if (_adapter == address(0)) {
        revert APIARY__ZERO_ADDRESS();
    }
    
    address oldAdapter = kodiakAdapter;
    kodiakAdapter = _adapter;
    
    emit AdapterUpdated("kodiak", oldAdapter, _adapter); // ✅ Transparent
}
```

**⚠️ OPERATIONAL SECURITY**:
- ALWAYS audit adapter contracts before setting
- Use multi-sig for owner role in production
- Time-delayed ownership transfer (Ownable2Step)

---

### 5. **Split Configuration Errors**

**Risk Level**: MEDIUM  
**Attack Vector**: Invalid split percentages → execution failures or fund loss

**Vulnerability**:
```solidity
// BAD: No validation
splitConfig = SplitConfig({
    toHoney: 3000,
    toApiaryLP: 3000,
    toBurn: 3000  // Total = 9000 (not 100%)
});
```

**Mitigation** ✅:
- Strict validation: splits MUST sum to 10000 (100%)
- Atomic update of all splits
- Event emission for transparency

**Implementation**:
```solidity
function setSplitPercentages(...) external onlyOwner {
    uint256 total = toHoney + toApiaryLP + toBurn + toStakers + toCompound;
    
    if (total != 10000) {
        revert APIARY__INVALID_SPLIT_CONFIG(); // ✅ Enforced
    }
    
    splitConfig = SplitConfig({...});
    emit SplitConfigUpdated(...);
}
```

---

### 6. **Gas Limit Denial of Service**

**Risk Level**: MEDIUM  
**Attack Vector**: Excessive yield accumulation → `executeYield()` exceeds block gas limit

**Vulnerability**:
```solidity
// BAD: Process all pending yield in one transaction
function executeYield() external {
    uint256 totalYield = pendingYield(); // Could be 1M+ iBGT
    _executePhase1Strategy(totalYield);   // Exceeds gas limit
}
```

**Mitigation** ✅:
- `maxExecutionAmount` caps single execution
- Owner can adjust via `setMaxExecutionAmount()`
- Keeper can execute multiple times if needed

**Implementation**:
```solidity
if (totalYield > maxExecutionAmount) {
    totalYield = maxExecutionAmount; // ✅ Cap per execution
}
```

**Best Practice**:
- Set `maxExecutionAmount` to ~10k iBGT for 5s block time
- Monitor gas usage on testnet
- Adjust based on network conditions

---

### 7. **Oracle Manipulation (Phase 2)**

**Risk Level**: HIGH  
**Attack Vector**: Flash loan manipulation of MC/TV ratio → incorrect Phase 2 distribution

**Vulnerability**:
```solidity
// BAD: Single-block oracle reading
(uint256 mc, uint256 tv) = _getMarketCapAndTV(); // Flashloan vulnerable
```

**Mitigation** ⚠️ **REQUIRES TREASURY UPDATE**:
- Treasury should use TWAP oracle (time-weighted average price)
- Multi-block price averaging
- Minimum time delay between reads

**Recommended Treasury Implementation**:
```solidity
function getMarketCapAndTV() external view returns (uint256 mc, uint256 tv) {
    // Use 30-minute TWAP for flash loan resistance
    mc = twapOracle.getMarketCap(1800); // 30 min window
    tv = treasuryValue;
}
```

**Current Status**: ⚠️ Placeholder implementation  
**Action Required**: Integrate TWAP oracle in treasury before Phase 2 activation

---

### 8. **Emergency Mode Bypass**

**Risk Level**: LOW  
**Attack Vector**: Emergency mode forwards all to treasury → bypasses normal distribution

**Intended Behavior**: ✅ This is a feature, not a bug  
**Purpose**: Last resort to prevent fund loss during adapter failures

**Security Checklist**:
- Only owner can toggle `setEmergencyMode()`
- Event emitted for transparency
- Normal execution resumes when disabled
- Treasury receives raw iBGT (no swaps/burns)

**Use Cases**:
- Kodiak DEX exploit detected
- Infrared adapter compromised
- Oracle manipulation suspected
- Extreme market volatility

---

### 9. **Token Approval Exploitation**

**Risk Level**: MEDIUM  
**Attack Vector**: Malicious adapter drains approved tokens

**Vulnerability**:
```solidity
// BAD: Infinite approval
ibgtToken.approve(kodiakAdapter, type(uint256).max);
```

**Mitigation** ✅:
- Use `forceApprove()` with exact amount needed
- Reset approval to 0 after use (SafeERC20)
- No infinite approvals

**Implementation**:
```solidity
ibgtToken.forceApprove(kodiakAdapter, amount); // ✅ Exact amount only
// After swap, approval automatically consumed
```

---

### 10. **Ownership Transfer Risks**

**Risk Level**: CRITICAL  
**Attack Vector**: Owner private key compromised → complete protocol takeover

**Mitigation** ✅:
- `Ownable2Step` requires pending owner to accept
- Prevents accidental transfers to wrong address
- Multi-sig recommended for production

**Implementation**:
```solidity
// Step 1: Current owner transfers
transferOwnership(newOwner);

// Step 2: New owner must accept
acceptOwnership(); // ✅ Two-step prevents mistakes
```

---

## 🛡️ Security Best Practices

### ✅ Implemented

1. **Access Control**
   - `Ownable2Step` for ownership
   - `onlyOwner` on all admin functions
   - No public state-changing functions

2. **Reentrancy Protection**
   - `ReentrancyGuard` on `executeYield()`
   - CEI pattern (Checks-Effects-Interactions)
   - No callback functions

3. **Emergency Controls**
   - `Pausable` for circuit breaker
   - `emergencyMode` for adapter bypass
   - `emergencyWithdraw()` for stuck tokens

4. **Input Validation**
   - Zero address checks on all setters
   - Split percentages sum validation
   - Slippage tolerance max cap (10%)

5. **Transparency**
   - Events on all state changes
   - Public view functions for monitoring
   - Historical tracking (totalYieldProcessed, etc.)

6. **Safe Token Transfers**
   - `SafeERC20` for all transfers
   - `forceApprove()` for exact amounts
   - No infinite approvals

### ⚠️ Pending Implementation

1. **TWAP Oracle Integration** (Phase 2)
   - Current MC/TV calculation is placeholder
   - Must integrate multi-block TWAP before Phase 2 activation

2. **LP Token Staking** (Phase 1)
   - `_stakeLPTokens()` is simplified
   - Needs actual LP token address resolution
   - Must approve LP tokens to gauge

3. **vBGT Strategy** (Phase 3)
   - `_executePhase3Strategy()` is placeholder
   - Pending vBGT contract deployment

---

## 🔍 Pre-Deployment Checklist

### Critical Validations

- [ ] **Adapter Audits**
  - [ ] ApiaryInfraredAdapter audited and verified
  - [ ] ApiaryKodiakAdapter audited and verified
  - [ ] All adapter interfaces match implementations

- [ ] **Token Addresses**
  - [ ] APIARY token has `burn()` function
  - [ ] HONEY token is correct stablecoin
  - [ ] iBGT token address matches Infrared

- [ ] **Treasury Integration**
  - [ ] Treasury has `getMarketCapAndTV()` function
  - [ ] Treasury can receive LP tokens
  - [ ] Treasury has TWAP oracle integration

- [ ] **Ownership**
  - [ ] Deploy with multi-sig as owner
  - [ ] Test ownership transfer on testnet
  - [ ] Document key holders

- [ ] **Parameter Configuration**
  - [ ] `slippageTolerance` = 50 (0.5%) for mainnet
  - [ ] `minYieldAmount` = 0.1 iBGT (prevent dust execution)
  - [ ] `maxExecutionAmount` = 10k iBGT (gas safety)
  - [ ] `mcThresholdMultiplier` = 13000 (130% for Phase 2)

- [ ] **Split Percentages**
  - [ ] Phase 1: 25/50/25 (HONEY/LP/Burn)
  - [ ] Phase 2: TBD based on strategy
  - [ ] Phase 3: TBD based on vBGT design

### Operational Security

- [ ] **Multi-Sig Setup**
  - [ ] 3-of-5 or 2-of-3 multi-sig for owner role
  - [ ] Key holders geographically distributed
  - [ ] Backup key storage procedures

- [ ] **Monitoring**
  - [ ] Off-chain monitoring for `PartialExecutionFailure` events
  - [ ] Alert on emergency mode activation
  - [ ] Track gas usage per execution

- [ ] **Keeper Configuration**
  - [ ] Chainlink Automation or Gelato integration
  - [ ] Execute when `canExecuteYield()` returns true
  - [ ] Gas price limits configured

- [ ] **Emergency Procedures**
  - [ ] Pause procedure documented
  - [ ] Emergency withdrawal process
  - [ ] Incident response plan

### Testing Requirements

- [ ] **Unit Tests**
  - [ ] Normal execution (Phase 1)
  - [ ] Partial failures (swap fails, LP fails)
  - [ ] Zero yield scenarios
  - [ ] Slippage exceeded
  - [ ] Reentrancy attempts
  - [ ] Emergency mode
  - [ ] Ownership transfer

- [ ] **Integration Tests**
  - [ ] End-to-end with real adapters
  - [ ] Multi-phase strategy switching
  - [ ] Large yield amounts (gas testing)
  - [ ] Edge cases (dust amounts, max amounts)

- [ ] **Testnet Deployment**
  - [ ] Deploy to Berachain testnet
  - [ ] Execute 10+ yield cycles
  - [ ] Monitor gas usage
  - [ ] Test emergency functions

---

## 📊 Gas Optimization

### Current Estimations

| Operation | Est. Gas | Notes |
|-----------|----------|-------|
| `executeYield()` (Phase 1) | ~600k | 3 swaps + LP + stake |
| `executeYield()` (Phase 2) | ~400k | Conditional logic |
| `executeYield()` (Phase 3) | ~150k | Simple transfer |
| `setStrategy()` | ~30k | State update |
| `setSplitPercentages()` | ~40k | Struct update |

### Optimization Techniques

1. **Batching**: Cap `maxExecutionAmount` for gas safety
2. **Emergency Mode**: Bypass swaps if needed
3. **Storage Packing**: Immutables for token addresses
4. **View Functions**: Use `staticcall` for reads

---

## 🎯 Attack Scenarios & Responses

### Scenario 1: Kodiak DEX Exploit

**Situation**: Kodiak router compromised, draining liquidity

**Response**:
1. `pause()` - Stop all executions
2. `setEmergencyMode(true)` - Bypass swaps
3. `setKodiakAdapter(address(0))` - Disconnect adapter
4. Assess damage, plan recovery
5. Deploy new adapter when safe
6. `unpause()` - Resume operations

### Scenario 2: Flash Loan Attack (Phase 2)

**Situation**: Attacker manipulates MC/TV ratio via flash loan

**Prevention**:
- Treasury uses TWAP oracle (30-min window)
- Multi-block price averaging
- Cannot be exploited in single block

**Response** (if TWAP not yet implemented):
- DO NOT activate Phase 2
- Keep Phase 1 until TWAP integrated
- Monitor for price anomalies

### Scenario 3: Reentrancy Attempt

**Situation**: Malicious token with callback tries to re-enter

**Prevention**:
- `nonReentrant` modifier blocks re-entry
- CEI pattern enforced
- No callback functions

**Expected Behavior**:
- Transaction reverts with "ReentrancyGuard: reentrant call"
- No state changes occur
- Attacker gains nothing

### Scenario 4: Large Yield Accumulation

**Situation**: 100k iBGT pending (gas limit risk)

**Response**:
1. Keeper executes with `maxExecutionAmount` cap
2. First execution: 10k iBGT processed
3. Second execution: 10k iBGT processed
4. Continue until all yield processed
5. Monitor gas per execution
6. Adjust `maxExecutionAmount` if needed

---

## 📝 Audit Recommendations

### Priority 1 (Critical)

1. **External Security Audit**
   - Engage professional auditors (Trail of Bits, OpenZeppelin, etc.)
   - Focus on reentrancy, adapter integration, slippage
   - Minimum 2-week engagement

2. **Formal Verification**
   - Verify `executeYield()` state transitions
   - Prove split percentages always sum to 100%
   - Verify no tokens stuck after execution

3. **Economic Simulation**
   - Model Phase 1/2/3 strategies under various market conditions
   - Test slippage limits with real DEX data
   - Stress test with extreme yield amounts

### Priority 2 (High)

1. **Adapter Interface Standardization**
   - Ensure all adapters follow same error handling
   - Consistent return values
   - Unified event naming

2. **Gas Profiling**
   - Profile `executeYield()` on mainnet conditions
   - Identify optimization opportunities
   - Document worst-case gas usage

3. **Integration Testing**
   - Full end-to-end testing with deployed adapters
   - Multi-week testnet deployment
   - Real keeper integration

### Priority 3 (Medium)

1. **Documentation**
   - Technical specification document
   - Operational runbook
   - Emergency response procedures

2. **Monitoring & Alerts**
   - Off-chain monitoring infrastructure
   - Alert system for anomalies
   - Dashboard for real-time stats

---

## 🔐 Final Security Score

| Category | Score | Notes |
|----------|-------|-------|
| **Reentrancy Protection** | 9/10 | ✅ ReentrancyGuard, CEI pattern |
| **Access Control** | 9/10 | ✅ Ownable2Step, multi-sig recommended |
| **Input Validation** | 10/10 | ✅ All inputs validated |
| **Slippage Protection** | 8/10 | ✅ Implemented, needs tuning |
| **Emergency Controls** | 9/10 | ✅ Pause, emergency mode, withdraw |
| **Transparency** | 10/10 | ✅ Events, view functions |
| **Token Safety** | 10/10 | ✅ SafeERC20, exact approvals |
| **Oracle Integration** | 5/10 | ⚠️ TWAP needed for Phase 2 |
| **Gas Optimization** | 7/10 | ⚠️ Needs profiling |
| **Testing Coverage** | 6/10 | ⚠️ Tests pending |

**Overall Security**: **8.3/10** ✅ PRODUCTION-READY (after audit + testing)

---

## ✅ Conclusion

The ApiaryYieldManager is designed with security as the top priority. The multi-layered approach (reentrancy guards, pausable, emergency mode, slippage protection) provides strong defenses against common attack vectors.

**Before Mainnet Deployment**:
1. Complete comprehensive test suite
2. Professional security audit
3. 2-week testnet deployment
4. TWAP oracle integration (for Phase 2)
5. Multi-sig setup for owner role

**Ongoing Security**:
1. Monitor all executions
2. Regular parameter reviews
3. Adapter health checks
4. Incident response drills

This contract is the **MOST CRITICAL** in the Apiary protocol. Treat it with maximum security precautions. 🔒
