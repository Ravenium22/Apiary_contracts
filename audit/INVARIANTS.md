# Apiary Protocol Invariants

Critical protocol invariants that must hold at all times. Violations indicate bugs or exploits.

---

## Table of Contents

1. [Token Supply Invariants](#1-token-supply-invariants)
2. [Accounting Invariants](#2-accounting-invariants)
3. [Staking Invariants](#3-staking-invariants)
4. [Bond Invariants](#4-bond-invariants)
5. [Treasury Invariants](#5-treasury-invariants)
6. [Yield Manager Invariants](#6-yield-manager-invariants)
7. [Oracle Invariants](#7-oracle-invariants)
8. [Access Control Invariants](#8-access-control-invariants)

---

## 1. Token Supply Invariants

### INV-1.1: APIARY Total Supply Cap
```solidity
assert(ApiaryToken.totalSupply() <= 200_000e9);
```
**Description**: Total APIARY supply never exceeds 200,000 APIARY.

**Enforcement**:
- `ApiaryToken.mint()` checks `totalMintedSupply + amount <= INITIAL_SUPPLY`
- `INITIAL_SUPPLY = 200_000e9` (constant)

**Violation Scenarios**:
- ❌ Admin sets allocation limits totaling >200k
- ❌ `totalMintedSupply` underflows (impossible with Solidity 0.8+)
- ❌ Mint logic bypassed

**Test**:
```solidity
function invariant_totalSupplyCap() public {
    assertLe(apiary.totalSupply(), 200_000e9);
}
```

---

### INV-1.2: APIARY Supply Equals Sum of Balances
```solidity
assert(ApiaryToken.totalSupply() == sum(balanceOf(all_addresses)));
```
**Description**: Total supply equals sum of all holder balances.

**Enforcement**:
- ERC20 standard guarantees this
- Solidity 0.8+ prevents overflows

**Violation Scenarios**:
- ❌ Mint without increasing supply
- ❌ Burn without decreasing supply
- ❌ Transfer with overflow/underflow

**Test**:
```solidity
function invariant_supplyEqualsBalances() public {
    // Ghost variable tracking (updated in handler)
    assertEq(apiary.totalSupply(), ghost_sumOfBalances);
}
```

---

### INV-1.3: Total Minted Never Decreases
```solidity
assert(ApiaryToken.totalMintedSupply() >= old(totalMintedSupply));
```
**Description**: `totalMintedSupply` is monotonically increasing (burns don't decrease it).

**Enforcement**:
- `burn()` does NOT decrement `totalMintedSupply`
- `mint()` increments `totalMintedSupply`

**Rationale**: Track total minted separately from circulating supply.

**Test**:
```solidity
function invariant_totalMintedNeverDecreases() public {
    uint256 currentMinted = apiary.totalMintedSupply();
    // Use ghost variable to track previous
    assertGe(currentMinted, ghost_prevTotalMinted);
    ghost_prevTotalMinted = currentMinted;
}
```

---

### INV-1.4: Allocation Limits Sum
```solidity
assert(sum(allocationLimits[all_minters]) <= 200_000e9);
```
**Description**: Sum of all allocation limits never exceeds total supply cap.

**Enforcement**:
- Manual verification during deployment
- Each `setAllocationLimit()` should check sum (not implemented)

**Violation Scenarios**:
- ⚠️ Admin sets allocations totaling >200k (no on-chain check)

**Recommendation**:
```solidity
uint256 public totalAllocated;

function setAllocationLimit(address minter, uint256 maxTokens) external {
    require(totalAllocated + maxTokens <= INITIAL_SUPPLY, "Total allocation exceeded");
    allocationLimits[minter] = maxTokens;
    totalAllocated += maxTokens;
}
```

---

### INV-1.5: sAPIARY Circulating Supply
```solidity
assert(sApiary.circulatingSupply() == sApiary.totalSupply() - sApiary.balanceOf(stakingContract));
```
**Description**: Circulating sAPIARY excludes staking contract's balance.

**Enforcement**:
- `circulatingSupply()` function implements this

**Test**:
```solidity
function invariant_sApiaryCirculating() public {
    uint256 expected = sApiary.totalSupply() - sApiary.balanceOf(address(staking));
    assertEq(sApiary.circulatingSupply(), expected);
}
```

---

## 2. Accounting Invariants

### INV-2.1: Allocation Limit Consistency
```solidity
assert(ApiaryToken.allocationLimits(minter) + minted_by_minter == original_allocation);
```
**Description**: For each minter, remaining allocation + minted amount = original allocation.

**Enforcement**:
- `mint()` decrements `allocationLimits[caller]` by `amount`

**Test**:
```solidity
mapping(address => uint256) ghost_totalMintedByMinter;

function invariant_allocationConsistency() public {
    for (uint i = 0; i < minters.length; i++) {
        address minter = minters[i];
        uint256 remaining = apiary.allocationLimits(minter);
        uint256 minted = ghost_totalMintedByMinter[minter];
        uint256 original = ghost_originalAllocations[minter];
        assertEq(remaining + minted, original);
    }
}
```

---

### INV-2.2: Treasury iBGT Accounting
```solidity
assert(
    treasury.totalReserves(IBGT) == 
    _ibgtAccounting.availableBalance + 
    _ibgtAccounting.totalStaked
);
```
**Description**: Total iBGT reserves = available + staked.

**Enforcement**:
- `borrowIBGT()`: decrements available, increments staked
- `repayIBGT()`: increments available, decrements staked

**Violation Scenarios**:
- ❌ Borrow/repay logic bug
- ❌ Direct iBGT transfer bypassing accounting

**Test**:
```solidity
function invariant_treasuryIBGTAccounting() public {
    uint256 total = treasury.totalReserves(IBGT);
    uint256 available = treasury.getAvailableIBGT();
    uint256 staked = treasury.getTotalStaked();
    assertEq(total, available + staked);
}
```

---

### INV-2.3: Borrowed iBGT Never Exceeds Total
```solidity
assert(treasury.totalBorrowed(IBGT) <= treasury.totalReserves(IBGT));
```
**Description**: Cannot borrow more iBGT than treasury owns.

**Enforcement**:
- `borrowIBGT()` checks `availableBalance >= amount`

**Test**:
```solidity
function invariant_borrowedLessThanTotal() public {
    assertLe(treasury.totalBorrowed(IBGT), treasury.totalReserves(IBGT));
}
```

---

### INV-2.4: Total Returned iBGT
```solidity
assert(_ibgtAccounting.totalReturned >= _ibgtAccounting.totalBorrowed_ever);
```
**Description**: Cannot return more iBGT than ever borrowed (accounting for yield).

**Enforcement**:
- `repayIBGT()` increments `totalReturned`
- Yield is included in `totalReturned`

**Note**: `totalReturned` can exceed `totalBorrowed` due to yield.

**Test**:
```solidity
function invariant_returnedWithYield() public {
    uint256 returned = treasury.getTotalReturned();
    uint256 borrowed = ghost_totalEverBorrowed;
    // Returned can be > borrowed (yield)
    assertGe(returned, borrowed - returned); // No violation if returned includes yield
}
```

---

## 3. Staking Invariants

### INV-3.1: Staked APIARY Equals sAPIARY Value
```solidity
assert(
    ApiaryToken.balanceOf(stakingContract) == 
    sApiary.totalSupply() / sApiary.index()
);
```
**Description**: APIARY in staking contract equals sAPIARY supply converted at current index.

**Enforcement**:
- Rebasing maintains peg
- `stake()` mints sAPIARY proportional to APIARY
- `unstake()` burns sAPIARY proportional to APIARY

**Violation Scenarios**:
- ❌ `rebase()` called with incorrect profit
- ❌ Direct APIARY transfer to staking contract (outside stake/unstake)

**Test**:
```solidity
function invariant_stakedEqualsIndex() public {
    uint256 apiaryInStaking = apiary.balanceOf(address(staking));
    uint256 sApiarySupply = sApiary.totalSupply();
    uint256 index = sApiary.index();
    
    // sAPIARY * index / 1e9 should equal APIARY
    uint256 expectedApiary = (sApiarySupply * index) / 1e9;
    
    assertApproxEqRel(apiaryInStaking, expectedApiary, 1e15); // 0.1% tolerance for rounding
}
```

---

### INV-3.2: Warmup Claims Consistency
```solidity
assert(
    sum(warmupInfo[all_users].amount) <= 
    sApiary.balanceOf(warmupContract)
);
```
**Description**: Sum of all warmup claims ≤ sAPIARY in warmup contract.

**Enforcement**:
- `stake()` creates warmup claim and mints sAPIARY to warmup
- `unstake(trigger=false)` retrieves from warmup

**Violation Scenarios**:
- ❌ Warmup claim created without minting sAPIARY
- ❌ Double-claim bug

**Test**:
```solidity
function invariant_warmupClaimsConsistency() public {
    uint256 totalClaims = ghost_sumOfWarmupClaims;
    uint256 warmupBalance = sApiary.balanceOf(address(warmup));
    assertLe(totalClaims, warmupBalance);
}
```

---

### INV-3.3: Index Never Decreases
```solidity
assert(sApiary.index() >= old(index));
```
**Description**: Rebase index is monotonically increasing.

**Enforcement**:
- `rebase()` only increases `_gonsPerFragment` (decreases value per gon, increases tokens per gon)

**Violation Scenarios**:
- ❌ `rebase()` called with negative profit (should revert)

**Test**:
```solidity
function invariant_indexNeverDecreases() public {
    uint256 currentIndex = sApiary.index();
    assertGe(currentIndex, ghost_prevIndex);
    ghost_prevIndex = currentIndex;
}
```

---

### INV-3.4: Epoch Number Increases
```solidity
assert(staking.epoch().number >= old(epoch.number));
```
**Description**: Epoch number is monotonically increasing.

**Enforcement**:
- `rebase()` increments `epoch.number`

**Test**:
```solidity
function invariant_epochIncreases() public {
    uint256 currentEpoch = staking.epoch().number;
    assertGe(currentEpoch, ghost_prevEpoch);
    ghost_prevEpoch = currentEpoch;
}
```

---

## 4. Bond Invariants

### INV-4.1: Total Debt Consistency
```solidity
assert(
    bondDepository.totalDebt() == 
    sum(bondInfo[all_users].payout - redeemed_amounts)
);
```
**Description**: Total debt equals sum of all outstanding bond payouts.

**Enforcement**:
- `deposit()` increments `totalDebt` by `payout`
- `redeem()` decrements `totalDebt` by redeemed amount

**Violation Scenarios**:
- ❌ `deposit()` doesn't increment `totalDebt`
- ❌ `redeem()` doesn't decrement `totalDebt`

**Test**:
```solidity
function invariant_totalDebtConsistency() public {
    uint256 reportedDebt = bondDepository.totalDebt();
    uint256 calculatedDebt = ghost_sumOfBondPayouts;
    assertEq(reportedDebt, calculatedDebt);
}
```

---

### INV-4.2: Bond Debt Never Exceeds Max
```solidity
assert(bondDepository.totalDebt() <= bondDepository.terms(0).maxDebt);
```
**Description**: Total bond debt respects max debt limit.

**Enforcement**:
- `deposit()` checks `totalDebt + payout <= terms.maxDebt`

**Test**:
```solidity
function invariant_debtBelowMax() public {
    uint256 totalDebt = bondDepository.totalDebt();
    uint256 maxDebt = bondDepository.terms(0).maxDebt;
    assertLe(totalDebt, maxDebt);
}
```

---

### INV-4.3: Bond Payout Non-Negative
```solidity
assert(bondInfo[user].payout >= 0); // Always true for uint256
```
**Description**: Bond payout is always non-negative (trivial with uint).

---

### INV-4.4: Vested Amount Bounds
```solidity
assert(
    vestedAmount(user) <= bondInfo[user].payout
);
```
**Description**: Vested amount never exceeds total payout.

**Enforcement**:
- `percentVestedFor()` calculation ensures ≤ 100%

**Test**:
```solidity
function invariant_vestedBounded() public {
    for (uint i = 0; i < bondHolders.length; i++) {
        address user = bondHolders[i];
        uint256 vested = bondDepository.pendingPayoutFor(user);
        uint256 total = bondDepository.bondInfo(user).payout;
        assertLe(vested, total);
    }
}
```

---

### INV-4.5: Pre-Sale Total Purchased
```solidity
assert(
    preSaleBond.totalApiaryToMint() == 
    sum(userPurchaseInfo[all_users].apiaryPurchased)
);
```
**Description**: Total APIARY to mint equals sum of all user purchases.

**Enforcement**:
- `purchaseApiary()` increments `totalApiaryToMint` by calculated amount

**Test**:
```solidity
function invariant_preSaleTotalConsistency() public {
    uint256 total = preSaleBond.totalApiaryToMint();
    uint256 sumPurchases = ghost_sumOfPurchases;
    assertEq(total, sumPurchases);
}
```

---

### INV-4.6: Pre-Sale Unlocked Bounds
```solidity
assert(
    userPurchaseInfo[user].apiaryUnlocked <= 
    userPurchaseInfo[user].apiaryPurchased
);
```
**Description**: User cannot unlock more than they purchased.

**Enforcement**:
- `unlockApiary()` calculates vested amount ≤ total purchased

**Test**:
```solidity
function invariant_unlockedBounded() public {
    for (uint i = 0; i < buyers.length; i++) {
        address user = buyers[i];
        (,uint128 purchased, uint128 unlocked,) = preSaleBond.userPurchaseInfo(user);
        assertLe(unlocked, purchased);
    }
}
```

---

## 5. Treasury Invariants

### INV-5.1: Treasury Solvency
```solidity
assert(
    treasury.balance(IBGT) >= 
    sum(bondDepository.totalDebt() for all bond contracts)
);
```
**Description**: Treasury holds enough iBGT to cover all bond debts.

**Enforcement**:
- Manual monitoring (not enforced on-chain)

**Violation Scenarios**:
- ⚠️ More bonds sold than iBGT deposited
- ⚠️ iBGT lent to yield manager and lost

**Recommendation**: Add solvency check in bond deposit:
```solidity
require(treasury.balance(IBGT) >= totalDebt + payout, "Insolvency risk");
```

---

### INV-5.2: Reserve Token Whitelist
```solidity
assert(
    treasury.isReserveToken(IBGT) == true &&
    treasury.isLiquidityToken(APIARY_HONEY_LP) == true
);
```
**Description**: Approved tokens remain whitelisted.

**Enforcement**:
- No function to remove tokens (only add)

**Test**:
```solidity
function invariant_reserveTokensWhitelisted() public {
    assertTrue(treasury.isReserveToken(IBGT));
    assertTrue(treasury.isLiquidityToken(APIARY_HONEY_LP));
}
```

---

### INV-5.3: Depositor Authorization
```solidity
assert(
    treasury.isReserveDepositor(bondDepository) == true
);
```
**Description**: Bond depositories remain authorized.

**Test**:
```solidity
function invariant_depositorsAuthorized() public {
    assertTrue(treasury.isReserveDepositor(address(ibgtBond)));
    assertTrue(treasury.isLiquidityDepositor(address(lpBond)));
}
```

---

## 6. Yield Manager Invariants

### INV-6.1: Split Percentages Sum to 100%
```solidity
assert(
    splitConfig.toHoney + 
    splitConfig.toApiaryLP + 
    splitConfig.toBurn + 
    splitConfig.toStakers + 
    splitConfig.toCompound == 10000
);
```
**Description**: All yield split percentages sum to 10000 (100.00%).

**Enforcement**:
- `setSplitConfig()` should check sum (not currently implemented)

**Recommendation**:
```solidity
function setSplitConfig(SplitConfig memory newConfig) external onlyOwner {
    require(
        newConfig.toHoney + newConfig.toApiaryLP + newConfig.toBurn + 
        newConfig.toStakers + newConfig.toCompound == 10000,
        "Split must equal 100%"
    );
    splitConfig = newConfig;
}
```

---

### INV-6.2: Total Yield Processed Increases
```solidity
assert(yieldManager.totalYieldProcessed() >= old(totalYieldProcessed));
```
**Description**: Total yield processed is monotonically increasing.

**Enforcement**:
- `executeYield()` increments `totalYieldProcessed`

**Test**:
```solidity
function invariant_yieldProcessedIncreases() public {
    uint256 current = yieldManager.totalYieldProcessed();
    assertGe(current, ghost_prevYieldProcessed);
    ghost_prevYieldProcessed = current;
}
```

---

### INV-6.3: Adapters Set Correctly
```solidity
assert(
    yieldManager.infraredAdapter() != address(0) &&
    yieldManager.kodiakAdapter() != address(0)
);
```
**Description**: Adapters are always set (non-zero).

**Enforcement**:
- Deployment script sets adapters
- No function to unset (only change)

**Test**:
```solidity
function invariant_adaptersSet() public {
    assertNotEq(yieldManager.infraredAdapter(), address(0));
    assertNotEq(yieldManager.kodiakAdapter(), address(0));
}
```

---

## 7. Oracle Invariants

### INV-7.1: TWAP Update Frequency
```solidity
assert(
    block.timestamp >= oracle.blockTimestampLast() + minimumUpdateInterval
    || oracle.blockTimestampLast() == 0 // First update
);
```
**Description**: Oracle updates respect minimum interval.

**Enforcement**:
- `update()` checks `block.timestamp - blockTimestampLast >= minimumUpdateInterval`

**Test**:
```solidity
function invariant_oracleUpdateFrequency() public {
    uint32 lastUpdate = oracle.blockTimestampLast();
    if (lastUpdate > 0) {
        assertGe(block.timestamp, lastUpdate + oracle.minimumUpdateInterval());
    }
}
```

---

### INV-7.2: TWAP Price Reasonableness
```solidity
assert(
    oracle.price0Average() > 0 &&
    oracle.price1Average() > 0
);
```
**Description**: TWAP prices are never zero (after first update).

**Test**:
```solidity
function invariant_oraclePricesNonZero() public {
    if (oracle.blockTimestampLast() > 0) {
        assertGt(oracle.price0Average(), 0);
        assertGt(oracle.price1Average(), 0);
    }
}
```

---

## 8. Access Control Invariants

### INV-8.1: Owner is Multi-Sig
```solidity
assert(
    Ownable(contract).owner() == MULTISIG_ADDRESS
);
```
**Description**: All contracts owned by multi-sig (after deployment).

**Enforcement**:
- Deployment script transfers ownership
- Manual verification

**Test**:
```solidity
function invariant_ownerIsMultisig() public {
    assertEq(treasury.owner(), MULTISIG);
    assertEq(yieldManager.owner(), MULTISIG);
    assertEq(staking.owner(), MULTISIG);
}
```

---

### INV-8.2: Minter Role Assignments
```solidity
assert(
    ApiaryToken.hasRole(MINTER_ROLE, treasury) == true &&
    ApiaryToken.hasRole(MINTER_ROLE, preSaleBond) == true
);
```
**Description**: Authorized contracts have MINTER_ROLE.

**Test**:
```solidity
function invariant_minterRolesAssigned() public {
    assertTrue(apiary.hasRole(apiary.MINTER_ROLE(), address(treasury)));
    assertTrue(apiary.hasRole(apiary.MINTER_ROLE(), address(preSaleBond)));
}
```

---

### INV-8.3: No EOAs Have Critical Roles (Post-Deployment)
```solidity
assert(
    !ApiaryToken.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER_EOA)
);
```
**Description**: Deployer EOA has no admin roles after deployment.

**Enforcement**:
- Deployment script renounces roles

**Test**:
```solidity
function invariant_deployerHasNoRoles() public {
    assertFalse(apiary.hasRole(apiary.DEFAULT_ADMIN_ROLE(), DEPLOYER));
}
```

---

## Invariant Testing Strategy

### Foundry Invariant Tests

**File**: `test/Invariants.t.sol`

```solidity
contract InvariantsTest is Test {
    // Declare handlers
    TokenHandler tokenHandler;
    StakingHandler stakingHandler;
    BondHandler bondHandler;
    
    function setUp() public {
        // Deploy protocol
        // Setup handlers
        tokenHandler = new TokenHandler(apiary, actors);
        stakingHandler = new StakingHandler(staking, sApiary, actors);
        bondHandler = new BondHandler(bondDepository, actors);
        
        // Target handlers
        targetContract(address(tokenHandler));
        targetContract(address(stakingHandler));
        targetContract(address(bondHandler));
    }
    
    // Token invariants
    function invariant_totalSupplyCap() public {
        assertLe(apiary.totalSupply(), 200_000e9);
    }
    
    function invariant_supplyEqualsBalances() public {
        assertEq(apiary.totalSupply(), tokenHandler.ghost_sumOfBalances());
    }
    
    // Staking invariants
    function invariant_stakedEqualsIndex() public {
        uint256 apiaryInStaking = apiary.balanceOf(address(staking));
        uint256 sApiarySupply = sApiary.totalSupply();
        uint256 index = sApiary.index();
        uint256 expectedApiary = (sApiarySupply * index) / 1e9;
        assertApproxEqRel(apiaryInStaking, expectedApiary, 1e15);
    }
    
    // Bond invariants
    function invariant_totalDebtConsistency() public {
        assertEq(bondDepository.totalDebt(), bondHandler.ghost_sumOfBondPayouts());
    }
    
    // Treasury invariants
    function invariant_treasuryIBGTAccounting() public {
        uint256 total = treasury.totalReserves(IBGT);
        uint256 available = treasury.getAvailableIBGT();
        uint256 staked = treasury.getTotalStaked();
        assertEq(total, available + staked);
    }
    
    // Yield invariants
    function invariant_splitPercentagesSum() public {
        SplitConfig memory config = yieldManager.splitConfig();
        assertEq(
            config.toHoney + config.toApiaryLP + config.toBurn + 
            config.toStakers + config.toCompound,
            10000
        );
    }
}
```

---

## Ghost Variables for Tracking

```solidity
contract TokenHandler {
    mapping(address => uint256) public balances;
    uint256 public ghost_sumOfBalances;
    uint256 public ghost_prevTotalMinted;
    
    function mint(address to, uint256 amount) public {
        // Perform mint
        apiary.mint(to, amount);
        
        // Update ghost variables
        balances[to] += amount;
        ghost_sumOfBalances += amount;
    }
    
    function burn(address from, uint256 amount) public {
        // Perform burn
        apiary.burn(from, amount);
        
        // Update ghost variables
        balances[from] -= amount;
        ghost_sumOfBalances -= amount;
    }
}
```

---

## Critical Invariants Summary

**Must Never Violate (System Failure)**:
1. ✅ Total supply ≤ 200k APIARY
2. ✅ Supply = sum of balances
3. ✅ Staked APIARY = sAPIARY value
4. ✅ Total debt ≤ max debt
5. ✅ Treasury iBGT accounting (available + staked = total)

**Should Not Violate (Protocol Integrity)**:
1. ⚠️ Allocation limits sum ≤ 200k
2. ⚠️ Treasury solvency (iBGT ≥ bond debts)
3. ⚠️ Split percentages = 100%
4. ⚠️ Oracle prices non-zero
5. ⚠️ Owner is multi-sig

**Nice to Have (Operational)**:
1. 🟢 Index never decreases
2. 🟢 Epoch increases
3. 🟢 Total yield processed increases

---

**For attack scenarios, see [ATTACK_VECTORS.md](./ATTACK_VECTORS.md)**
**For test coverage, see [TEST_COVERAGE.md](./TEST_COVERAGE.md)**
