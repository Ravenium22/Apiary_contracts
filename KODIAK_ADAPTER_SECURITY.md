# ApiaryKodiakAdapter - Security Analysis & Guidelines

## **Overview**

The ApiaryKodiakAdapter interfaces with Kodiak DEX (Uniswap V2 style) to execute swaps, manage liquidity, and stake LP tokens for the Apiary protocol's 25/25/50 yield strategy.

---

## **🔒 Security Architecture**

### **Access Control Layers**

| Role | Permissions | Purpose |
|------|-------------|---------|
| **Yield Manager** | swap(), addLiquidity(), removeLiquidity(), stakeLP(), unstakeLP(), claimLPRewards() | Treasury operations |
| **Owner** | registerGauge(), setYieldManager(), pause(), admin functions | Protocol management |
| **Public** | View functions (getExpectedSwapOutput, poolExists, etc.) | Monitoring |

### **Security Mechanisms**

✅ **ReentrancyGuard** - All state-changing functions  
✅ **Pausable** - Circuit breaker for emergencies  
✅ **Ownable2Step** - Safe ownership transfer  
✅ **Slippage Protection** - All swaps and liquidity operations  
✅ **Deadline Protection** - Prevents stale transactions  
✅ **Pool Validation** - Verify pools exist before operations  
✅ **No Token Accumulation** - Flow-through design (no balance held)  
✅ **SafeERC20** - Safe token transfers  
✅ **Minimum Amount Checks** - Prevent dust attacks  

---

## **🚨 Critical Attack Vectors**

### **1. Sandwich Attacks**

**Attack:** MEV bot frontrunns swap, manipulates price, backruns for profit

```
Attack Flow:
1. Adapter submits swap: 100 APIARY → HONEY
2. MEV bot sees pending transaction
3. Bot frontrunns: buys HONEY (price increases)
4. Adapter's swap executes at worse price
5. Bot backruns: sells HONEY (takes profit)
```

**Mitigation:**

✅ **minAmountOut parameter**
```solidity
function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,  // ← Slippage protection
    address recipient
) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 amountOut) {
    // Reverts if amountOut < minAmountOut
    if (amountOut < minAmountOut) {
        revert APIARY__SWAP_FAILED();
    }
}
```

✅ **Deadline protection**
```solidity
uint256 deadline = block.timestamp + defaultDeadlineOffset; // 5 minutes
```

✅ **Default slippage: 0.5%** (adjustable by owner)

**Recommended Slippage Calculation:**

```typescript
// Frontend/YieldManager should calculate:
const expectedOutput = await adapter.getExpectedSwapOutput(tokenIn, tokenOut, amountIn);
const slippageBps = 50; // 0.5%
const minAmountOut = expectedOutput * (10000 - slippageBps) / 10000;

await adapter.swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient);
```

---

### **2. Price Manipulation**

**Attack:** Attacker manipulates pool reserves to extract value

**Scenario 1: Flash Loan Attack**
```
1. Attacker takes flash loan
2. Buys massive amount of APIARY (pumps price)
3. Adapter swaps at inflated price
4. Attacker sells APIARY (dumps price)
5. Adapter receives less HONEY than expected
```

**Mitigation:**

✅ **Slippage protection** (minAmountOut)  
✅ **Pool reserve validation** (implicit in router swap)  
✅ **Minimum swap amounts** (prevents dust manipulation)  

⚠️ **Additional Protection Needed:**

Consider TWAP oracle for large swaps:

```solidity
// If swap amount > threshold, verify price against TWAP
if (amountIn > largeSwapThreshold) {
    uint256 twapPrice = twapOracle.consult(tokenIn, amountIn, tokenOut);
    uint256 poolPrice = router.getAmountsOut(amountIn, path)[1];
    
    // Require pool price within X% of TWAP
    require(
        poolPrice >= (twapPrice * 95) / 100,
        "Price deviation too high"
    );
}
```

---

### **3. Reentrancy Attacks**

**Attack:** Malicious token calls back into adapter during transfer

```
Attack Flow:
1. Adapter calls swap()
2. Router transfers malicious token to adapter
3. Malicious token's transfer() calls back: adapter.swap()
4. Second swap executes before first completes
5. State corruption or double spending
```

**Mitigation:**

✅ **ReentrancyGuard on all functions**
```solidity
function swap(...) external onlyYieldManager whenNotPaused nonReentrant {
    // nonReentrant prevents recursive calls
}
```

✅ **Checks-Effects-Interactions pattern**
```solidity
// 1. Checks
if (amountIn == 0) revert APIARY__INVALID_AMOUNT();
if (!poolExists) revert APIARY__POOL_DOES_NOT_EXIST();

// 2. Effects (state changes)
totalSwapsExecuted++;

// 3. Interactions (external calls)
kodiakRouter.swapExactTokensForTokens(...);
```

---

### **4. Pool Existence Validation**

**Attack:** Swap to non-existent pool drains gas or locks funds

**Scenario:**
```
1. Attacker calls swap(APIARY, FakeToken, 100e18, ...)
2. Pool doesn't exist
3. Router reverts, but gas wasted
4. Or worse: Router creates empty pool, tokens stuck
```

**Mitigation:**

✅ **Pool validation before swap**
```solidity
address pair = kodiakFactory.getPair(tokenIn, tokenOut);
if (pair == address(0)) {
    revert APIARY__POOL_DOES_NOT_EXIST();
}
```

✅ **Multi-hop validation**
```solidity
// Validate all intermediate pools exist
for (uint256 i = 0; i < path.length - 1; i++) {
    address pair = kodiakFactory.getPair(path[i], path[i + 1]);
    if (pair == address(0)) {
        revert APIARY__POOL_DOES_NOT_EXIST();
    }
}
```

---

### **5. LP Staking Risks**

**Attack:** Gauge manipulation or fake gauge contract

**Scenario 1: Fake Gauge**
```
1. Owner accidentally registers fake gauge
2. YieldManager stakes LP tokens
3. Fake gauge steals LP tokens
4. Treasury loses liquidity
```

**Mitigation:**

✅ **Gauge registration only by owner**
```solidity
function registerGauge(address lpToken, address gauge) external onlyOwner {
    lpToGauge[lpToken] = gauge;
}
```

⚠️ **Owner must verify gauge is legitimate Kodiak contract**

**Recommended Validation:**

```solidity
// Add gauge validation in registerGauge()
function registerGauge(address lpToken, address gauge) external onlyOwner {
    // Verify gauge accepts this LP token
    require(
        IKodiakGauge(gauge).stakingToken() == lpToken,
        "Gauge doesn't accept this LP token"
    );
    
    // Verify gauge has reward tokens
    require(
        IKodiakGauge(gauge).rewardTokensLength() > 0,
        "Gauge has no rewards"
    );
    
    lpToGauge[lpToken] = gauge;
    emit GaugeRegistered(lpToken, gauge);
}
```

---

### **6. Liquidity Addition Risks**

**Attack:** Unbalanced liquidity provision loses value

**Scenario:**
```
1. Adapter adds liquidity: 1000 APIARY + 500 HONEY
2. Pool ratio is 1:1 (should be 1000 APIARY + 1000 HONEY)
3. Router only uses 500 APIARY + 500 HONEY
4. Remaining 500 APIARY returned but at worse price
```

**Mitigation:**

✅ **Return unused tokens**
```solidity
uint256 unusedA = amountA - actualAmountA;
uint256 unusedB = amountB - actualAmountB;

if (unusedA > 0) {
    IERC20(tokenA).safeTransfer(msg.sender, unusedA);
}

if (unusedB > 0) {
    IERC20(tokenB).safeTransfer(msg.sender, unusedB);
}
```

✅ **Slippage protection on amounts**
```solidity
uint256 minAmountA = (amountA * (10000 - defaultSlippageBps)) / 10000;
uint256 minAmountB = (amountB * (10000 - defaultSlippageBps)) / 10000;
```

✅ **Minimum LP token requirement**
```solidity
if (liquidity < minLP) {
    revert APIARY__LIQUIDITY_FAILED();
}
```

---

### **7. Deadline Expiration**

**Attack:** Transaction pending too long, executes at stale price

**Scenario:**
```
1. YieldManager submits swap with 5 minute deadline
2. Network congestion delays transaction 10 minutes
3. Deadline expires, transaction reverts
4. Gas wasted, operation fails
```

**Mitigation:**

✅ **Automatic deadline calculation**
```solidity
uint256 deadline = block.timestamp + defaultDeadlineOffset; // 300 seconds
```

✅ **Custom deadline option**
```solidity
function swapWithDeadline(..., uint256 deadline) external {
    if (deadline < block.timestamp) {
        revert APIARY__DEADLINE_EXPIRED();
    }
}
```

**Recommended Deadline Settings:**

| Operation | Recommended Deadline | Reason |
|-----------|---------------------|--------|
| Small swaps | 2 minutes | Quick execution expected |
| Large swaps | 5 minutes | More time for inclusion |
| Liquidity ops | 10 minutes | Complex, multi-step |
| During congestion | 15 minutes | Network delays |

---

### **8. Stuck Tokens**

**Attack:** Tokens accumulate in adapter, become inaccessible

**Scenario:**
```
1. User accidentally sends APIARY to adapter
2. Tokens stuck (no withdrawal function)
3. Value lost permanently
```

**Mitigation:**

✅ **Emergency withdraw function**
```solidity
function emergencyWithdrawToken(address token, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(treasury, amount);
}
```

✅ **Flow-through design** (adapter never holds balance)
- Swap: transfer in → swap → transfer out (same tx)
- Liquidity: transfer in → add liquidity → LP to recipient (same tx)
- Staking: transfer in → stake → gauge holds (same tx)

✅ **Return unused tokens immediately**

---

### **9. Slippage Front-Running**

**Attack:** Attacker sees pending tx, adjusts minAmountOut to steal slippage

**Scenario:**
```
1. YieldManager submits swap with minAmountOut = 950 HONEY
2. Attacker sees tx in mempool
3. Attacker submits tx with higher gas: transfers 60 HONEY to pool
4. Adapter's swap executes, receives 951 HONEY (just above minimum)
5. Adapter loses 49 HONEY to slippage
```

**Mitigation:**

✅ **Tight slippage tolerance** (0.5% default)  
✅ **Private mempool** (Flashbots, MEV protection services)  
✅ **TWAP validation** for large swaps  

**Recommended: Use Flashbots RPC**

```javascript
// YieldManager should submit via Flashbots to hide from public mempool
const flashbotsProvider = await FlashbotsBundleProvider.create(
    provider,
    flashbotsSigner
);

const signedTx = await adapter.swap(...);
const bundleSubmission = await flashbotsProvider.sendBundle([signedTx], targetBlock);
```

---

### **10. Gauge Reward Token Changes**

**Attack:** Gauge changes reward tokens, adapter claims wrong tokens

**Scenario:**
```
1. Adapter stakes LP in gauge
2. Gauge initially rewards: [xKDK, BGT]
3. Gauge admin changes rewards to: [xKDK, SCAM_TOKEN]
4. Adapter claims rewards, receives SCAM_TOKEN
5. SCAM_TOKEN rug pulls
```

**Mitigation:**

⚠️ **No validation currently** - Adapter blindly claims all reward tokens

**Recommended Addition:**

```solidity
// Whitelist allowed reward tokens
mapping(address => bool) public allowedRewardTokens;

function setAllowedRewardToken(address token, bool allowed) external onlyOwner {
    allowedRewardTokens[token] = allowed;
}

function claimLPRewards(...) external {
    // ... existing claim logic ...
    
    // Only transfer whitelisted rewards
    for (uint256 i = 0; i < rewardCount; i++) {
        if (rewardAmounts[i] > 0 && allowedRewardTokens[rewardTokens[i]]) {
            IERC20(rewardTokens[i]).safeTransfer(recipient, rewardAmounts[i]);
        }
    }
}
```

---

## **📋 Security Checklist**

### **Pre-Deployment**

| Item | Status | Notes |
|------|--------|-------|
| Verify Kodiak router address | ⬜ | Must match official Kodiak deployment |
| Verify Kodiak factory address | ⬜ | Must match official Kodiak deployment |
| Set HONEY token address | ⬜ | Berachain HONEY stablecoin |
| Set APIARY token address | ⬜ | Deployed Apiary governance token |
| Set treasury address | ⬜ | Official Apiary treasury |
| Set yield manager address | ⬜ | Authorized yield manager contract |
| Configure slippage tolerance | ⬜ | Default: 50 bps (0.5%) |
| Configure deadline offset | ⬜ | Default: 300 seconds (5 minutes) |
| Set minimum swap amount | ⬜ | Default: 0.01 tokens |
| Set minimum liquidity amount | ⬜ | Default: 0.01 LP tokens |
| Audit all dependencies | ⬜ | OpenZeppelin v5, interfaces |
| Test on testnet | ⬜ | Berachain testnet |

### **Post-Deployment**

| Item | Status | Notes |
|------|--------|-------|
| Register APIARY/HONEY gauge | ⬜ | Verify gauge contract legitimacy |
| Register other LP gauges | ⬜ | As needed for strategy |
| Verify ownership transferred | ⬜ | 2-step transfer to multisig |
| Test swap operations | ⬜ | Small amounts first |
| Test liquidity operations | ⬜ | Small amounts first |
| Test staking operations | ⬜ | Verify rewards accrue |
| Monitor for anomalies | ⬜ | Set up alerts |
| Establish pause procedures | ⬜ | Emergency response plan |

### **Ongoing Monitoring**

| Metric | Alert Threshold | Action |
|--------|----------------|--------|
| Slippage > default | > 0.5% | Investigate price impact |
| Failed swaps | > 5% of total | Check pool liquidity |
| Stuck tokens | Any balance held | Emergency withdraw |
| Unauthorized access attempts | Any | Pause contract |
| Abnormal reward claims | Sudden spike | Verify gauge integrity |
| LP unstake without claim | Any occurrence | Check for exploit |

---

## **🔧 Slippage Calculation Recommendations**

### **Dynamic Slippage Based on Trade Size**

```solidity
function calculateOptimalSlippage(
    uint256 amountIn,
    uint256 poolReserve
) public pure returns (uint256 slippageBps) {
    uint256 tradeImpact = (amountIn * 10000) / poolReserve;
    
    if (tradeImpact < 10) {
        // < 0.1% of pool: 0.3% slippage
        slippageBps = 30;
    } else if (tradeImpact < 50) {
        // 0.1-0.5% of pool: 0.5% slippage
        slippageBps = 50;
    } else if (tradeImpact < 100) {
        // 0.5-1% of pool: 1% slippage
        slippageBps = 100;
    } else {
        // > 1% of pool: 2% slippage
        slippageBps = 200;
    }
}
```

### **Example Calculations**

```javascript
// Swap 100 APIARY for HONEY
// Pool reserves: APIARY = 50,000, HONEY = 50,000

const amountIn = ethers.parseEther("100"); // 100 APIARY
const path = [APIARY_ADDRESS, HONEY_ADDRESS];

// 1. Get expected output
const expectedOutput = await adapter.getExpectedSwapOutput(
    APIARY_ADDRESS,
    HONEY_ADDRESS,
    amountIn
);
// expectedOutput = ~99.8 HONEY (accounting for 0.3% fee)

// 2. Calculate slippage (0.5%)
const slippageBps = 50;
const minAmountOut = (expectedOutput * (10000n - slippageBps)) / 10000n;
// minAmountOut = ~99.3 HONEY

// 3. Execute swap
const tx = await adapter.swap(
    APIARY_ADDRESS,
    HONEY_ADDRESS,
    amountIn,
    minAmountOut,
    TREASURY_ADDRESS
);
```

---

## **⚡ Gas Optimization Tips**

1. **Batch Operations** - Combine multiple swaps/stakes in one transaction (external)
2. **Approve Once** - Adapter uses `forceApprove(type(uint256).max)` to avoid repeated approvals
3. **Multi-Hop Swaps** - Use `swapMultiHop()` for routes through multiple pools (more efficient than separate swaps)
4. **Claim Before Unstake** - Always claim rewards before unstaking to save gas

---

## **🛡️ Emergency Procedures**

### **Scenario 1: Exploit Detected**

```solidity
// 1. Owner pauses contract immediately
adapter.pause();

// 2. Emergency unstake all LP
adapter.emergencyUnstakeAll(); // (would need to add this function)

// 3. Withdraw stuck tokens
adapter.emergencyWithdrawToken(APIARY_ADDRESS, balance);
adapter.emergencyWithdrawToken(HONEY_ADDRESS, balance);

// 4. Investigate and patch
// 5. Deploy new adapter
// 6. Migrate liquidity
```

### **Scenario 2: Kodiak Router Upgrade**

```solidity
// Kodiak cannot upgrade router (immutable)
// Must deploy new adapter with new router address
// Migration required
```

### **Scenario 3: Gauge Compromised**

```solidity
// 1. Unstake all LP from affected gauge
adapter.unstakeLP(LP_TOKEN, totalStaked, TREASURY);

// 2. Remove gauge registration
// (would need removeGauge() function)

// 3. Register new gauge
adapter.registerGauge(LP_TOKEN, NEW_GAUGE);

// 4. Re-stake LP
adapter.stakeLP(LP_TOKEN, amount);
```

---

## **✅ Best Practices**

1. **Always Use Slippage Protection** - Never set minAmountOut to 0
2. **Validate Pool Existence** - Check pool before operations
3. **Monitor Price Impact** - Large swaps should verify against TWAP
4. **Claim Rewards Regularly** - Prevents reward accumulation exploits
5. **Use Private Mempool** - Protect against MEV for large trades
6. **Test on Testnet First** - Especially for new gauges
7. **Gradual Rollout** - Start with small amounts, increase over time
8. **Monitor Continuously** - Set up alerts for anomalies
9. **Document All Operations** - Audit trail for troubleshooting
10. **Emergency Preparedness** - Have pause/recovery procedures ready

---

## **🔗 Integration Example**

```solidity
// YieldManager executes 25/25/50 strategy

// 1. Swap 25% of iBGT to APIARY
uint256 ibgtAmount = 1000e18;
uint256 apiaryExpected = adapter.getExpectedSwapOutput(IBGT, APIARY, ibgtAmount);
uint256 minApiary = adapter.calculateMinOutput(apiaryExpected, 50);

adapter.swap(IBGT, APIARY, ibgtAmount, minApiary, address(this));

// 2. Swap 25% of iBGT to HONEY
uint256 honeyExpected = adapter.getExpectedSwapOutput(IBGT, HONEY, ibgtAmount);
uint256 minHoney = adapter.calculateMinOutput(honeyExpected, 50);

adapter.swap(IBGT, HONEY, ibgtAmount, minHoney, address(this));

// 3. Add liquidity (50% equivalent)
uint256 apiaryForLP = apiaryReceived;
uint256 honeyForLP = honeyReceived;
uint256 minLP = calculateMinLP(apiaryForLP, honeyForLP);

adapter.addLiquidity(
    APIARY,
    HONEY,
    apiaryForLP,
    honeyForLP,
    minLP,
    address(this)
);

// 4. Stake LP tokens
adapter.stakeLP(APIARY_HONEY_LP, lpReceived);

// 5. Periodically claim rewards
adapter.claimLPRewards(APIARY_HONEY_LP, TREASURY);
```

---

## **📊 Recommended Security Audits**

1. **Static Analysis** - Slither, Mythril, Securify
2. **Formal Verification** - Certora (critical functions)
3. **Manual Audit** - Professional security firm
4. **Economic Audit** - Game theory analysis of incentives
5. **Integration Testing** - End-to-end with treasury/yield manager
6. **Mainnet Monitoring** - Real-time anomaly detection

---

**Last Updated:** December 2025  
**Version:** 1.0  
**Author:** Apiary Security Team
