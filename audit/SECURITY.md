# Apiary Protocol Security Analysis

Comprehensive security analysis for Apiary protocol audit preparation.

---

## Table of Contents

1. [Known Risks & Mitigations](#known-risks--mitigations)
2. [Centralization Risks](#centralization-risks)
3. [External Dependency Risks](#external-dependency-risks)
4. [Economic Attack Vectors](#economic-attack-vectors)
5. [Oracle Manipulation Risks](#oracle-manipulation-risks)
6. [Access Control Vulnerabilities](#access-control-vulnerabilities)
7. [Reentrancy Attack Surfaces](#reentrancy-attack-surfaces)
8. [Front-running Vulnerabilities](#front-running-vulnerabilities)
9. [Integer Overflow/Underflow](#integer-overflowunderflow)
10. [Emergency Procedures](#emergency-procedures)

---

## 1. Known Risks & Mitigations

### 1.1 Yield Manager Execution Risk

**Risk**: `ApiaryYieldManager.executeYield()` is public and orchestrates complex operations across multiple contracts.

**Attack Scenario**:
- Malicious actor calls `executeYield()` repeatedly
- Drains gas from protocol operations
- Potentially causes DoS

**Mitigations**:
✅ **ReentrancyGuard**: Prevents reentrancy
✅ **Pausable**: Owner can pause in emergency
✅ **minYieldAmount**: Prevents execution with tiny amounts
✅ **maxExecutionAmount**: Limits per-execution risk

**Residual Risk**: ⚠️ MEDIUM
- Keeper should monitor for suspicious execution patterns
- Consider adding time-lock between executions

---

### 1.2 Allocation Limit Bypass

**Risk**: Minting limits in `ApiaryToken` are one-time set but not atomic.

**Attack Scenario**:
- Admin sets allocation limit for Treasury: 40,000 APIARY
- Before Treasury mints, malicious admin grants MINTER_ROLE to attacker
- Attacker mints their allocation first
- Total minted > INITIAL_SUPPLY (200k)

**Mitigations**:
✅ **setAllocationLimit() auto-grants MINTER_ROLE**: Prevents manual role grants
✅ **totalMintedSupply check**: Prevents exceeding 200k total
❌ **No protection against admin front-running**: Admin could set own allocation

**Residual Risk**: ⚠️ HIGH (if admin compromised)
- **Recommendation**: Use multi-sig for admin role
- **Recommendation**: Set all allocations atomically in deployment script

---

### 1.3 sApiary Rebase Manipulation

**Risk**: `sApiary.rebase()` can only be called by staking contract, but incorrect `profit` parameter could inflate balances.

**Attack Scenario**:
- Staking contract has bug in profit calculation
- Calls `rebase(10000000e9, epoch)` instead of `rebase(1000e9, epoch)`
- All stakers suddenly 10,000x richer

**Mitigations**:
✅ **Only stakingContract can call**: Limits attack surface
❌ **No validation of profit amount**: Trusts caller

**Residual Risk**: ⚠️ MEDIUM
- **Recommendation**: Add max rebase per epoch (e.g., 10% max increase)
- **Recommendation**: Audit staking contract's profit calculation thoroughly

---

### 1.4 Treasury iBGT Borrowing

**Risk**: `ApiaryTreasury.borrowIBGT()` lends treasury's reserves to yield manager. If yield manager is compromised, reserves are lost.

**Attack Scenario**:
- Attacker compromises yield manager contract
- Calls `borrowIBGT(1000000e18)`
- Transfers iBGT to attacker EOA
- Treasury cannot recover

**Mitigations**:
✅ **Only yieldManager can call**: Single point of trust
✅ **_ibgtAccounting tracks borrowed amount**: Auditable
❌ **No timelock or borrowing limit**: Instant access to all reserves
❌ **repayIBGT() not enforced**: No automatic repayment

**Residual Risk**: 🔴 CRITICAL
- **Recommendation**: Add borrowing limit (e.g., max 80% of available iBGT)
- **Recommendation**: Add timelock for large borrows
- **Recommendation**: Implement automatic repayment deadline with liquidation

---

### 1.5 Bond Price Manipulation

**Risk**: Bond prices depend on TWAP oracle, which uses Uniswap V2 pair reserves.

**Attack Scenario**:
- Attacker flash-loans large HONEY amount
- Swaps HONEY → APIARY on Kodiak (inflates APIARY price)
- Calls `oracle.update()` to capture inflated price
- Buys bonds at artificially low APIARY price
- Repays flash loan
- Redeems bonds for profit

**Mitigations**:
✅ **TWAP oracle**: Time-weighted average resists single-block manipulation
✅ **minimumUpdateInterval**: Prevents frequent updates
❌ **TWAP window unknown**: If window is short (e.g., 10 minutes), still vulnerable

**Residual Risk**: ⚠️ MEDIUM
- **Recommendation**: Set TWAP window to at least 30 minutes
- **Recommendation**: Monitor oracle updates for anomalies
- **Recommendation**: Add circuit breaker if price changes >20% in single update

---

### 1.6 Pre-Sale Whitelist Bypass

**Risk**: Merkle tree whitelist in `ApiaryPreSaleBond` can be bypassed if merkle root is weak.

**Attack Scenario**:
- Admin generates merkle tree with only 10 addresses
- Attacker brute-forces merkle tree off-chain
- Finds collision or discovers all whitelisted addresses
- Creates fake proof to purchase

**Mitigations**:
✅ **MerkleProof library (OpenZeppelin)**: Secure verification
✅ **isWhitelistEnabled flag**: Can disable whitelist
❌ **No salt in merkle leaves**: Vulnerable to rainbow table attacks

**Residual Risk**: 🟡 LOW (if tree is large)
- **Recommendation**: Include salt in merkle leaves (e.g., keccak256(address, salt))
- **Recommendation**: Use large whitelist (1000+ addresses)

---

## 2. Centralization Risks

### 2.1 Admin Key Compromise

**Single Points of Failure**:

| Contract | Admin Role | Powers |
|----------|-----------|--------|
| ApiaryToken | DEFAULT_ADMIN_ROLE | Set mint allocations, grant roles |
| ApiaryTreasury | owner | Set yield manager, enable depositors |
| ApiaryYieldManager | owner | Change strategy, set adapters, emergency mode |
| ApiaryStaking | owner | Pause, set warmup, set distributor |
| ApiaryBondDepository | owner | Set bond terms, pause |
| ApiaryPreSaleBond | owner | Start/end sale, start TGE |
| ApiaryInfraredAdapter | owner | Emergency withdraw, pause |
| ApiaryKodiakAdapter | owner | Emergency withdraw, pause |

**Attack Impact**: 🔴 CRITICAL
- Admin can:
  - Pause all contracts (DoS)
  - Change yield strategy to malicious one
  - Set malicious adapters to steal funds
  - Emergency withdraw all funds
  - Change bond terms to 100% discount (infinite mint)

**Mitigations**:
✅ **Ownable2Step**: Prevents accidental transfers
❌ **No multi-sig enforcement**: Single EOA can control protocol

**Recommendations**:
1. **Use Gnosis Safe multi-sig (3-of-5 or 5-of-9)**
2. **Time-lock critical functions (24-48h delay)**:
   - `setYieldManager()`
   - `setStrategy()`
   - `setBondTerms()`
3. **Role separation**:
   - Treasury admin (multi-sig)
   - Keeper (automated, limited powers)
   - Emergency pause (multi-sig)

---

### 2.2 Keeper Centralization

**Risk**: In Phase 2+, a keeper role will execute `rebase()` and possibly `executeYield()`.

**Attack Scenario**:
- Keeper is compromised or malicious
- Calls `executeYield()` at unfavorable times (e.g., during high slippage)
- Protocol loses value to MEV or bad swaps

**Mitigations**:
✅ **Public functions**: Anyone can call if keeper fails
❌ **No keeper validation**: Keeper has unrestricted access

**Recommendations**:
1. **Use Chainlink Automation or Gelato Network** (decentralized keepers)
2. **Add keeper role with limited powers**:
   - Can call `rebase()` and `executeYield()`
   - Cannot change parameters
3. **Monitor keeper actions**:
   - Alert if execution causes >5% slippage
   - Alert if execution timing is suspicious

---

## 3. External Dependency Risks

### 3.1 Infrared Protocol Risk

**Dependencies**:
- `ApiaryInfraredAdapter.stake()` → `IInfrared.stake()`
- `ApiaryInfraredAdapter.unstake()` → `IInfrared.withdraw()`
- `ApiaryInfraredAdapter.claimRewards()` → `IInfrared.claimRewards()`

**Risk**: Infrared protocol is external and could:
1. **Pause withdrawals**: Lock all staked iBGT
2. **Change reward distribution**: Reduce/eliminate rewards
3. **Upgrade contract**: Introduce bugs or malicious code
4. **Rug pull**: Transfer all staked assets to attacker

**Attack Impact**: 🔴 CRITICAL
- If Infrared locks funds, Apiary loses all staked iBGT
- Treasury cannot receive repaid iBGT
- Protocol becomes insolvent

**Mitigations**:
✅ **emergencyWithdraw()**: Owner can unstake all in emergency
✅ **Pausable**: Can pause further staking
❌ **No staking limit**: Can stake 100% of treasury

**Recommendations**:
1. **Limit staking to 50% of treasury iBGT**
2. **Monitor Infrared for upgrades/governance changes**
3. **Diversify staking** (Phase 2: add vBGT staking)
4. **Audit Infrared's upgrade mechanism** (timelock, multi-sig?)

---

### 3.2 Kodiak DEX Risk

**Dependencies**:
- `ApiaryKodiakAdapter.swapIBGTForHoney()` → `IKodiakRouter.swap()`
- `ApiaryKodiakAdapter.addLiquidityApiaryHoney()` → `IKodiakRouter.addLiquidity()`
- `ApiaryKodiakAdapter.stakeLPTokens()` → `IKodiakGauge.deposit()`

**Risk**: Kodiak DEX could:
1. **Manipulate swap prices**: Front-run swaps with large trades
2. **Rug pull liquidity**: Drain all LP tokens
3. **Pause trading**: Block swaps and LP operations
4. **Change fees**: Increase swap fees to 100%

**Attack Impact**: ⚠️ MEDIUM
- Yield execution could fail or lose value to slippage
- LP positions could be lost

**Mitigations**:
✅ **slippageTolerance parameter**: Limits bad swaps
✅ **emergencyWithdraw()**: Can withdraw stuck tokens
❌ **No alternative DEX**: Single point of failure

**Recommendations**:
1. **Add multi-DEX support** (e.g., backup to Uniswap V3)
2. **Monitor Kodiak pool liquidity**:
   - Alert if liquidity drops >50%
   - Alert if swap fees spike
3. **Set conservative slippage** (e.g., 0.5% max)

---

### 3.3 Berachain Token Risk

**Dependencies**:
- `IERC20(iBGT)` - Infrared's BGT wrapper
- `IERC20(HONEY)` - Berachain stablecoin
- `IERC20(BGT)` - Native Berachain governance token

**Risk**: If iBGT or HONEY contracts have bugs:
1. **iBGT depegs from BGT**: Treasury reserves lose value
2. **HONEY depegs from USD**: Bond payouts are worth less
3. **Transfer fails**: All operations break

**Attack Impact**: ⚠️ MEDIUM (external trust)

**Mitigations**:
✅ **Standard ERC20 interface**: Reduces attack surface
❌ **No peg checks**: Assumes iBGT == BGT, HONEY == $1

**Recommendations**:
1. **Add oracle checks for iBGT/BGT peg**:
   - Revert if peg deviates >5%
2. **Monitor HONEY peg**:
   - Alert if HONEY < $0.95 or > $1.05

---

## 4. Economic Attack Vectors

### 4.1 Bond Discount Arbitrage

**Attack Scenario**:
- Bond discount is 10% (bondPrice = 0.9 * market price)
- Attacker deposits 1000 iBGT → receives 1111 APIARY (10% discount)
- Immediately sells 1111 APIARY on DEX for 1100 iBGT
- Profits 100 iBGT

**Current Safeguards**:
- Vesting period (e.g., 5 days) prevents immediate sale
- Market arbitrage should close discount gap

**Vulnerability**:
- If vesting is short (1 day), attackers can still profit
- If discount is high (20%+), even with vesting, profitable

**Recommendations**:
1. **Set vesting to 5-7 days minimum**
2. **Limit discount to 5-10%**
3. **Add bond capacity limits** (max bonds per epoch)
4. **Implement bond decay** (discount decreases as bonds sold)

---

### 4.2 Yield Extraction via Flash Loans

**Attack Scenario**:
1. Attacker flash-loans 10,000 APIARY
2. Stakes all 10,000 → receives 10,000 sAPIARY
3. Calls `rebase()` → all sAPIARY holders earn yield
4. Unstakes 10,000 sAPIARY → receives 10,050 APIARY (if 0.5% yield)
5. Repays flash loan (10,000 APIARY)
6. Profits 50 APIARY

**Current Safeguards**:
- Warmup period prevents immediate unstaking
- `lastTimeStaked` tracking (in ApiaryToken)

**Vulnerability**:
- If warmup is 0, attack succeeds
- If `lastTimeStaked` is not checked in unstake, attack succeeds

**Recommendations**:
1. **Enforce warmup period** (at least 1 epoch)
2. **Check `lastTimeStaked` in unstake**:
   ```solidity
   require(block.timestamp >= lastTimeStaked[msg.sender] + warmupPeriod);
   ```
3. **Add staking fee** (e.g., 0.1% entry/exit fee)

---

### 4.3 LP Manipulation for Yield Boost

**Attack Scenario**:
1. Attacker creates APIARY/HONEY LP with 1000 APIARY + 1000 HONEY
2. Deposits LP to bond depository
3. Receives APIARY bonds (with LP valuation from `bondCalculator`)
4. `bondCalculator` uses current LP reserves → overvalues LP
5. Attacker removes liquidity after bond, keeps APIARY

**Current Safeguards**:
- TWAP oracle for price (not reserves)
- Bond calculator should use fair LP valuation

**Vulnerability**:
- If bond calculator uses spot reserves, can be manipulated
- If LP pool is small, easy to manipulate

**Recommendations**:
1. **Use time-weighted LP reserves in bondCalculator**
2. **Require minimum LP pool size** (e.g., $100k TVL)
3. **Add LP deposit cooldown** (e.g., 1 hour after adding liquidity)

---

### 4.4 Pre-Sale Sybil Attack

**Attack Scenario**:
- Whitelist has 1000 addresses
- Purchase limit is 100 APIARY per address
- Attacker controls 100 addresses → buys 10,000 APIARY
- Gets 110% bonus → 11,000 APIARY vested
- Dumps after TGE

**Current Safeguards**:
- Merkle whitelist limits participants
- 30-day vesting reduces dump impact

**Vulnerability**:
- If KYC is not enforced, Sybil attack succeeds
- If vesting is linear, 1/30 can be dumped daily

**Recommendations**:
1. **Implement KYC for large purchases** (e.g., >50 APIARY)
2. **Add cliff vesting** (e.g., 0% for 7 days, then linear 23 days)
3. **Add purchase limit per IP/device** (off-chain monitoring)

---

## 5. Oracle Manipulation Risks

### 5.1 TWAP Oracle Short-Term Manipulation

**Risk**: `ApiaryUniswapV2TwapOracle` uses cumulative price from Uniswap V2 pair.

**Attack Scenario**:
1. Attacker identifies TWAP window (e.g., 30 minutes)
2. At minute 0: Swaps 10,000 HONEY → APIARY (pumps price)
3. At minute 29: Calls `oracle.update()` (captures inflated price)
4. At minute 30: Buys bonds at discounted price
5. At minute 31: Dumps APIARY back to HONEY (profits from bond discount)

**Current Safeguards**:
- TWAP averages price over time
- `minimumUpdateInterval` prevents frequent updates

**Vulnerability**:
- If TWAP window < 1 hour, vulnerable to sustained manipulation
- If Kodiak liquidity is low, cheap to manipulate

**Recommendations**:
1. **Set TWAP window to 1-2 hours minimum**
2. **Set minimumUpdateInterval to 30 minutes**
3. **Add price change limit**:
   ```solidity
   require(newPrice <= oldPrice * 1.1, "Price jumped >10%");
   ```
4. **Monitor oracle for anomalies**:
   - Alert if price changes >15% in single update
   - Alert if update frequency spikes

---

### 5.2 Oracle Staleness

**Risk**: If oracle is not updated regularly, bond prices become stale.

**Attack Scenario**:
- Oracle shows APIARY price = $1 (from 24 hours ago)
- Real market price = $2 (APIARY pumped)
- Attacker buys bonds at $1 price (50% discount!)
- Redeems and sells at $2 (100% profit)

**Current Safeguards**:
- Anyone can call `oracle.update()`
- No explicit staleness check

**Vulnerability**:
- If no one calls `update()` for days, prices are wrong
- Bond depository trusts oracle blindly

**Recommendations**:
1. **Add staleness check in bond depository**:
   ```solidity
   require(block.timestamp - oracle.blockTimestampLast < 1 hours, "Oracle stale");
   ```
2. **Incentivize oracle updates** (small APIARY reward for calling `update()`)
3. **Add keeper to update oracle every 30 minutes**

---

### 5.3 Oracle Dependency on Single DEX

**Risk**: Oracle only uses Kodiak APIARY/HONEY pair. If that pair fails, entire protocol breaks.

**Attack Scenario**:
- Kodiak APIARY/HONEY pair is exploited (e.g., reentrancy)
- Pair is paused or drained
- Oracle cannot update
- All bond operations halt

**Current Safeguards**:
- None (single oracle source)

**Recommendations**:
1. **Add multi-oracle support**:
   - Primary: Kodiak TWAP
   - Fallback: Uniswap V3 TWAP
   - Emergency: Chainlink price feed (if available)
2. **Add oracle circuit breaker**:
   - If oracle fails, use last known good price
   - Alert multi-sig to investigate

---

## 6. Access Control Vulnerabilities

### 6.1 Role Escalation in ApiaryToken

**Risk**: `setAllocationLimit()` auto-grants `MINTER_ROLE` to the minter address.

**Attack Scenario**:
- Admin sets allocation for Treasury: 40,000 APIARY
- Treasury contract has bug allowing anyone to call `mint()`
- Attacker calls `Treasury.mint()` → mints APIARY to themselves
- Drains allocation

**Current Safeguards**:
- `MINTER_ROLE` is required for minting
- Allocation limits prevent over-minting

**Vulnerability**:
- If minter contract is vulnerable, allocation is lost
- No way to revoke `MINTER_ROLE` after setting

**Recommendations**:
1. **Add `revokeMinterRole()` function**:
   ```solidity
   function revokeMinterRole(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
       _revokeRole(MINTER_ROLE, minter);
   }
   ```
2. **Audit all minter contracts thoroughly**
3. **Consider two-step minting**:
   - Minter requests mint → creates pending mint
   - Admin approves mint after review

---

### 6.2 Unauthorized Adapter Changes

**Risk**: `ApiaryYieldManager` allows owner to change adapters anytime.

**Attack Scenario**:
- Owner (compromised or malicious) sets malicious adapter
- Calls `executeYield()`
- Malicious adapter steals all iBGT and HONEY
- Transfers to attacker

**Current Safeguards**:
- Only owner can set adapters
- Ownable2Step prevents accidental transfers

**Vulnerability**:
- No timelock on adapter changes
- Immediate effect

**Recommendations**:
1. **Add timelock for adapter changes** (48 hours):
   ```solidity
   mapping(address => uint256) public pendingAdapters;
   
   function proposeAdapter(address newAdapter) external onlyOwner {
       pendingAdapters[newAdapter] = block.timestamp + 48 hours;
   }
   
   function setAdapter(address newAdapter) external onlyOwner {
       require(block.timestamp >= pendingAdapters[newAdapter], "Timelock active");
       infraredAdapter = newAdapter;
   }
   ```
2. **Add adapter whitelist** (multi-sig can whitelist adapters)
3. **Require adapter to implement specific interface** (`IApiaryAdapter`)

---

### 6.3 Staking Contract Replacement

**Risk**: `sApiary.stakingContract` can only be set once by `initializer`, but no validation.

**Attack Scenario**:
- Initializer (deployer) sets wrong staking contract
- Wrong contract can call `rebase()` and mint unlimited sAPIARY
- Protocol is ruined

**Current Safeguards**:
- One-time initialization
- Deployer should be trusted

**Vulnerability**:
- No validation of staking contract
- Cannot be changed after deployment

**Recommendations**:
1. **Add staking contract validation**:
   ```solidity
   require(IStaking(stakingContract_).sAPIARY() == address(this), "Invalid staking");
   ```
2. **Add emergency staking contract replacement** (multi-sig + timelock)

---

## 7. Reentrancy Attack Surfaces

### 7.1 YieldManager Reentrancy

**Attack Surface**: `executeYield()` makes external calls to adapters.

**Attack Scenario**:
1. Malicious adapter is set
2. `executeYield()` calls `adapter.claimRewards()`
3. Malicious adapter re-enters `executeYield()`
4. Could drain funds or manipulate state

**Current Safeguards**:
✅ **ReentrancyGuard**: Prevents reentrancy

**Residual Risk**: 🟢 LOW (mitigated)

---

### 7.2 Treasury Deposit/Borrow Reentrancy

**Attack Surface**: `deposit()` and `borrowIBGT()` transfer tokens.

**Attack Scenario**:
1. Malicious ERC20 token is set as reserve
2. User calls `deposit(maliciousToken, ...)`
3. `maliciousToken.transferFrom()` re-enters `deposit()`
4. Could mint APIARY multiple times

**Current Safeguards**:
✅ **ReentrancyGuard**: Prevents reentrancy
✅ **Only approved tokens**: `isReserveToken` check

**Residual Risk**: 🟢 LOW (mitigated)

---

### 7.3 Bond Redeem Reentrancy

**Attack Surface**: `redeem()` transfers APIARY to user.

**Attack Scenario**:
1. Attacker creates malicious contract with `onERC20Received` hook
2. Calls `redeem()`
3. APIARY transfer triggers hook → re-enters `redeem()`
4. Could claim vested tokens multiple times

**Current Safeguards**:
✅ **ReentrancyGuard**: Prevents reentrancy
✅ **APIARY is standard ERC20**: No hooks

**Residual Risk**: 🟢 LOW (mitigated)

---

## 8. Front-running Vulnerabilities

### 8.1 Bond Purchase Front-running

**Attack Scenario**:
1. User submits `deposit(1000 iBGT, maxPrice=1.05)`
2. Attacker sees transaction in mempool
3. Attacker front-runs with `deposit(10000 iBGT, maxPrice=1.10)`
4. Attacker's bond fills first, increases debt
5. User's transaction reverts (debt limit exceeded) or gets worse price

**Current Safeguards**:
- `maxPrice` parameter allows slippage control
- Users can set tight limits

**Vulnerability**:
- Public mempool exposes transactions
- No private transactions on Berachain (yet)

**Recommendations**:
1. **Use Flashbots-style private mempool** (if available on Berachain)
2. **Add bond queue system**:
   - Users submit bond requests
   - Bonds filled in order (FIFO)
   - Prevents front-running
3. **Add per-block bond limit**:
   ```solidity
   mapping(uint256 => uint256) public bondsPerBlock;
   require(bondsPerBlock[block.number] < MAX_PER_BLOCK);
   ```

---

### 8.2 Yield Execution Front-running

**Attack Scenario**:
1. Keeper submits `executeYield()`
2. Attacker sees transaction
3. Attacker front-runs with large swap on Kodiak (manipulates price)
4. Yield execution gets bad price
5. Attacker back-runs to profit from arbitrage

**Current Safeguards**:
- `slippageTolerance` limits bad swaps
- TWAP oracle resists single-block manipulation

**Vulnerability**:
- If slippage tolerance is high (5%+), profitable to attack
- Sandwich attacks can steal value

**Recommendations**:
1. **Use private mempool for `executeYield()`**
2. **Set tight slippage** (0.5% max)
3. **Add MEV protection**:
   - Use Flashbots-style builder
   - Add time-delay for execution (block.timestamp + 1 minute)

---

### 8.3 Oracle Update Front-running

**Attack Scenario**:
1. Attacker monitors oracle
2. Detects large price movement on DEX
3. Calls `oracle.update()` before bond buyers
4. Bond prices update
5. Attacker front-runs bond purchases at old price

**Current Safeguards**:
- `minimumUpdateInterval` prevents rapid updates
- Anyone can call `update()`

**Vulnerability**:
- First updater has information advantage
- Can be automated with bots

**Recommendations**:
1. **Add update incentive** (small APIARY reward)
2. **Add update delay**:
   - `update()` creates pending update
   - Actual update happens 1 block later (prevents same-block front-run)

---

## 9. Integer Overflow/Underflow

### 9.1 Solidity 0.8+ Built-in Protection

✅ **All contracts use Solidity ^0.8.26**
✅ **Built-in overflow/underflow checks**

**Residual Risks**:
- `unchecked` blocks bypass protection (if used)
- `uint256 -> uint128` casting can overflow

---

### 9.2 Potential Downcasting Issues

**Location**: `ApiaryPreSaleBond.sol`

```solidity
struct UserPurchaseInfo {
    uint128 honeyPaid;          // Could overflow if user pays >2^128 HONEY
    uint128 apiaryPurchased;    // Could overflow if >2^128 APIARY
    uint128 apiaryUnlocked;
    uint48 lastUnlockTime;      // Could overflow in year 8,921,556,000 (safe)
}
```

**Risk**: If `honeyPaid` or `apiaryPurchased` exceed `type(uint128).max`, overflow.

**Realistic?**: 🟢 NO
- `type(uint128).max` = 340 undecillion
- With 9 decimals, = 340 trillion APIARY
- Supply cap is 200,000 APIARY

**Residual Risk**: 🟢 NONE (practically impossible)

---

### 9.3 Multiplication/Division Order

**Risk**: `a * b / c` could overflow even if result fits in uint256.

**Example** (hypothetical):
```solidity
uint256 result = (largeNumber * anotherLargeNumber) / divisor;
// If largeNumber * anotherLargeNumber > 2^256, overflows
```

**Mitigation**:
- Use OpenZeppelin's `Math.mulDiv()` for safe computation
- Re-order: `a / c * b` (if `a` is divisible by `c`)

**Recommendations**:
1. **Audit all multiplication/division operations**
2. **Use `Math.mulDiv()` for complex calculations**
3. **Add bounds checks for large numbers**

---

## 10. Emergency Procedures

### 10.1 Pause Mechanisms

**Pausable Contracts**:
- ✅ `ApiaryYieldManager`
- ✅ `ApiaryStaking`
- ✅ `ApiaryBondDepository` (all bond contracts)
- ✅ `ApiaryPreSaleBond`
- ✅ `ApiaryInfraredAdapter`
- ✅ `ApiaryKodiakAdapter`

**Not Pausable**:
- ❌ `ApiaryToken` - Transfers cannot be paused (ERC20 standard)
- ❌ `sApiary` - Transfers cannot be paused
- ❌ `ApiaryTreasury` - Deposits/borrows cannot be paused

**Emergency Pause Checklist**:
1. **Pause all yield operations**:
   - `ApiaryYieldManager.pause()`
   - `ApiaryInfraredAdapter.pause()`
   - `ApiaryKodiakAdapter.pause()`

2. **Pause staking**:
   - `ApiaryStaking.pause()`

3. **Pause bonding**:
   - `ApiaryBondDepository.pause()` (all instances)
   - `ApiaryPreSaleBond.pause()`

4. **Investigate incident**

5. **Execute emergency withdrawals if needed**:
   - `ApiaryInfraredAdapter.emergencyWithdraw()`
   - `ApiaryKodiakAdapter.emergencyWithdraw()`
   - `ApiaryYieldManager.emergencyWithdraw()`

6. **Unpause after fix**

---

### 10.2 Emergency Withdrawal Procedures

**Available Emergency Withdrawals**:

#### YieldManager
```solidity
function emergencyWithdraw(address token) external onlyOwner
```
- Withdraws `token` balance to treasury
- Use if: Adapter is stuck or malicious

#### InfraredAdapter
```solidity
function emergencyWithdraw() external onlyOwner
```
- Unstakes all iBGT from Infrared
- Transfers to treasury
- Use if: Infrared is compromised or paused

#### KodiakAdapter
```solidity
function emergencyWithdraw(address token) external onlyOwner
```
- Withdraws `token` balance to treasury
- Use if: Kodiak is compromised

**Emergency Withdrawal Checklist**:
1. **Pause affected contracts**
2. **Call `emergencyWithdraw()` on all adapters**
3. **Verify funds arrive at treasury**
4. **Investigate root cause**
5. **Deploy fix or new adapters**
6. **Resume operations**

---

### 10.3 Emergency Mode

**YieldManager Emergency Mode**:
```solidity
function setEmergencyMode(bool enabled) external onlyOwner
```

**When Enabled**:
- `executeYield()` skips adapters
- Sends all yield directly to treasury
- No swaps, no LP creation, no staking

**Use Cases**:
- Adapter is compromised
- DEX liquidity dried up
- Need to pause complex operations but keep simple transfers

**Procedure**:
1. `yieldManager.setEmergencyMode(true)`
2. `executeYield()` → sends all yield to treasury
3. Multi-sig manually manages yield off-chain
4. Fix issues
5. `setEmergencyMode(false)`

---

### 10.4 Disaster Recovery

**Scenario**: All adapters compromised, treasury drained.

**Recovery Steps**:
1. **Pause everything**
2. **Snapshot state** (balances, bonds, stakes)
3. **Deploy new contracts**:
   - New treasury
   - New yield manager
   - New adapters
4. **Migrate state**:
   - Airdrop APIARY to holders (based on snapshot)
   - Recreate bonds (extend vesting by downtime)
   - Recreate stakes (preserve index)
5. **Resume operations**

**Prevention**:
- Regular state backups (off-chain)
- Multi-sig controls
- Timelocks on critical changes
- Insurance fund (5-10% of treasury)

---

## Security Checklist

### Pre-Audit Checklist

- [ ] All contracts use Solidity 0.8.26 (overflow protection)
- [ ] All external calls use ReentrancyGuard
- [ ] All admin functions use Ownable2Step
- [ ] All contracts have NatSpec comments
- [ ] All functions have input validation
- [ ] All state changes emit events
- [ ] All errors use custom error types
- [ ] No floating pragma versions
- [ ] No compiler warnings

### Access Control Checklist

- [ ] Multi-sig is owner of all contracts
- [ ] Deployer has transferred ownership
- [ ] No EOAs have admin roles
- [ ] MINTER_ROLE only granted to authorized contracts
- [ ] Timelocks on critical functions (48h)
- [ ] Emergency pause roles separated from admin

### Economic Security Checklist

- [ ] Bond discounts ≤ 10%
- [ ] Vesting periods ≥ 5 days
- [ ] TWAP window ≥ 1 hour
- [ ] Slippage tolerance ≤ 1%
- [ ] Allocation limits set correctly
- [ ] Total supply cap enforced
- [ ] Pre-sale purchase limits enforced

### External Dependency Checklist

- [ ] Infrared contracts audited
- [ ] Kodiak contracts audited
- [ ] iBGT contract verified
- [ ] HONEY contract verified
- [ ] Oracle price feed verified
- [ ] Multi-oracle fallback configured
- [ ] Adapter contracts follow interface

### Emergency Preparedness Checklist

- [ ] Pause mechanisms tested
- [ ] Emergency withdrawal tested
- [ ] Emergency mode tested
- [ ] Disaster recovery plan documented
- [ ] Multi-sig signers trained
- [ ] Monitoring alerts configured
- [ ] Incident response runbook ready

---

**For detailed attack scenarios, see [ATTACK_VECTORS.md](./ATTACK_VECTORS.md)**
**For protocol invariants, see [INVARIANTS.md](./INVARIANTS.md)**
