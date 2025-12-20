# Apiary Protocol Test Coverage Analysis

Comprehensive test coverage report for Apiary protocol audit preparation.

---

## Table of Contents

1. [Test Suite Overview](#test-suite-overview)
2. [Unit Tests](#unit-tests)
3. [Integration Tests](#integration-tests)
4. [Fuzz Tests](#fuzz-tests)
5. [Invariant Tests](#invariant-tests)
6. [Security Tests](#security-tests)
7. [Coverage Gaps](#coverage-gaps)
8. [Coverage Metrics](#coverage-metrics)
9. [Recommendations](#recommendations)

---

## Test Suite Overview

### Test Files Structure

```
test/
├── Unit Tests (13 files)
│   ├── ApiaryInfraredAdapter.t.sol          # Infrared adapter tests
│   ├── ApiaryKodiakAdapter.t.sol            # Kodiak adapter tests
│   ├── ApiaryYieldManager.t.sol             # Yield manager tests
│   ├── BeraReserveBondDepositoryV2.t.sol    # Bond depository tests
│   ├── BeraReserveFeeDistributor.t.sol      # Fee distributor tests
│   ├── BeraReserveLockup.t.sol              # Lockup tests
│   ├── BeraReservePreBondCla imsTest.t.sol   # Pre-bond claims tests
│   ├── BeraReservePreBondSale.t.sol         # Pre-sale tests
│   ├── BeraReserveStaking.t.sol             # Staking tests
│   ├── BeraReserveTreasuryV2.t.sol          # Treasury tests
│   ├── BeraTokenTest.t.sol                  # Token tests
│   ├── TestTransferOwnership.t.sol          # Ownership tests
│   └── Treasury.t.sol                       # Legacy treasury tests
│
├── Integration Tests (3 files)
│   ├── ApiaryIntegration.t.sol              # Full protocol integration
│   ├── ApiarySecurity.t.sol                 # Security scenarios
│   └── ApiaryFuzz.t.sol                     # Property-based fuzzing
│
└── Setup Files (2 files)
    ├── BeraReserveBase.t.sol                # Base setup V1
    └── BeraReserveBaseV2.t.sol              # Base setup V2
```

### Test Framework

**Foundry** (forge test)
- **Solidity version**: 0.8.26
- **Test runner**: forge
- **Fuzzing engine**: Foundry's built-in fuzzer
- **Coverage tool**: forge coverage

---

## Unit Tests

### 1. ApiaryToken Tests

**File**: `test/BeraTokenTest.t.sol`

**Coverage**:
- ✅ Deployment and initialization
- ✅ Minting with allocation limits
- ✅ Burning tokens
- ✅ Role-based access control
- ✅ ERC20 standard compliance

**Key Test Cases**:
```solidity
// Allocation limit tests
testSetAllocationLimit()
testMintWithinAllocation()
testMintExceedingAllocationReverts()
testAllocationCanOnlyBeSetOnce()

// Minting tests
testMintRequiresMinterRole()
testMintRespectsTotalSupplyCap()
testTotalMintedSupplyTracking()

// Burning tests
testBurnByHolder()
testBurnFrom()
testBurnDoesNotDecrementTotalMinted()

// Access control
testOnlyAdminCanSetAllocations()
testMinterRoleAutoGranted()
```

**Coverage**: ~85%
- ❌ Missing: `lastTimeStaked` tracking tests
- ❌ Missing: Edge cases for allocation sum validation

---

### 2. sApiary Tests

**File**: `test/BeraReserveStaking.t.sol` (includes sApiary indirectly)

**Coverage**:
- ✅ Rebasing mechanism
- ✅ Index calculations
- ✅ Balance conversions (gons ↔ fragments)
- ✅ Circulating supply

**Key Test Cases**:
```solidity
// Rebase tests
testRebaseIncreasesIndex()
testRebaseDistributesProfit()
testRebaseOnlyByStakingContract()

// Balance tests
testBalanceOfReflectsIndex()
testTransferWithRebase()
testCirculatingSupplyExcludesStaking()

// Fuzz tests
testFuzzStakeAfterRebaseBlocksPassed(uint256 numOfPurchases, uint256 amount)
testFuzzStakeWithRebasingMultipleOps(uint256 numOfPurchases, uint256 amount)
```

**Coverage**: ~80%
- ❌ Missing: Max rebase amount validation
- ❌ Missing: Index overflow scenarios (edge case)

---

### 3. ApiaryTreasury Tests

**File**: `test/BeraReserveTreasuryV2.t.sol`

**Coverage**:
- ✅ Token deposits (reserve & liquidity)
- ✅ APIARY minting on deposits
- ✅ iBGT borrowing/repaying
- ✅ iBGT accounting (available, staked, returned)
- ✅ Depositor authorization

**Key Test Cases**:
```solidity
// Deposit tests
testDepositReserveToken()
testDepositLiquidityToken()
testDepositUnauthorizedReverts()
testDepositMintsCorrectAPARY()

// iBGT borrowing tests
testBorrowIBGT()
testBorrowExceedingAvailableReverts()
testRepayIBGT()
testRepayWithYield()

// Accounting tests
testIBGTAccountingConsistency()
testAvailablePlusStakedEqualsTotal()

// Fuzz tests
testFuzzDepositReserveToken(uint256 amount)
testFuzzDepositLiquidityToken(uint256 amount)
```

**Coverage**: ~90%
- ❌ Missing: Borrowing limit tests (no on-chain limit)
- ❌ Missing: Repayment deadline enforcement (no deadline)

---

### 4. ApiaryStaking Tests

**File**: `test/BeraReserveStaking.t.sol`

**Coverage**:
- ✅ Staking with warmup
- ✅ Unstaking after warmup
- ✅ Epoch management
- ✅ Rebase triggering
- ✅ Claim from warmup

**Key Test Cases**:
```solidity
// Staking tests
testStake()
testStakeCreatesWarmupClaim()
testStakeDuringPauseReverts()
testStakeUpdatesLastTimeStaked()

// Unstaking tests
testUnstakeAfterWarmup()
testUnstakeBeforeWarmupReverts()
testUnstakePartial()
testUnstakeBurnssApiary()

// Epoch & rebase
testRebaseIncreasesEpoch()
testRebaseDistributesYield()
testRebaseBeforeEpochEndReverts()

// Fuzz tests
testFuzzStake(uint256 numOfPurchases, uint256 amount)
testFuzz_UnstakeAllAfterMultipleRebases_BalanceIncreased(...)
testFuzz_UnstakePartialAfterMultipleRebases_BRRBalanceIncreased(...)
```

**Coverage**: ~85%
- ❌ Missing: Flash loan protection tests (lastTimeStaked enforcement)
- ❌ Missing: Warmup = 0 edge case

---

### 5. ApiaryBondDepository Tests

**File**: `test/BeraReserveBondDepositoryV2.t.sol`

**Coverage**:
- ✅ Bond purchases (iBGT & LP)
- ✅ Bond redemption (full & partial)
- ✅ Bond pricing (TWAP integration)
- ✅ Bond terms configuration
- ✅ Vesting calculations
- ✅ Debt tracking
- ✅ Fee collection

**Key Test Cases**:
```solidity
// Deployment & config
testConstructorParamsSetCorrectlyForUSDC_BondDepository()
testShouldInitializeBondTermsCorrectly()
testShouldSetDAOCorrectly()

// Bond purchase tests
testDepositUSDCBond()
testDepositLPBond()
testDepositExceedingMaxDebtReverts()
testDepositAboveMaxPriceReverts()

// Bond redemption tests
testRedeemPartialVestedBond()
testRedeemFullyVestedBond()
testRedeemMultipleUsersCorrectly()

// Term configuration
testSetBondTermsVestingTerm()
testSetBondTermsDiscountRate()
testSetBondTermsMaxDebt()

// Fuzz tests
testFuzzUSDCDepositShouldWorkCorrectly(uint256 amount, uint256 fee, uint256 discountRate)
testFuzzBRRHoneyDepositShouldWorkCorrectly(uint256 amount, uint256 fee, uint256 discountRate)
testFuzzRedeemShouldWorkCorrectlyForUSDCDepository(...)
testFuzzMultipleUsersRedeemShouldWorkCorrectlyForUSDCDepository(...)
```

**Coverage**: ~95%
- ❌ Missing: Bond capacity griefing tests
- ❌ Missing: Oracle staleness impact tests

---

### 6. ApiaryPreSaleBond Tests

**File**: `test/BeraReservePreBondSale.t.sol`

**Coverage**:
- ✅ Pre-sale state transitions
- ✅ Merkle whitelist verification
- ✅ Purchase limits
- ✅ 110% bonus calculation
- ✅ Linear vesting
- ✅ TGE initialization

**Key Test Cases**:
```solidity
// State transition tests
testStartPreSaleBond()
testEndPreSaleBond()
testStartTGE()
testStateTransitionOrder()

// Purchase tests
testPurchaseApiaryWithWhitelist()
testPurchaseExceedingLimitReverts()
testPurchaseInvalidMerkleProofReverts()
testPurchaseWith110PercentBonus()

// Unlocking tests
testUnlockApiaryAfterTGE()
testUnlockBeforeTGEReverts()
testUnlockLinearVesting()
testUnlockMultipleTimes()

// Fuzz tests
testFuzz__BRRPurchaseAllocationAndUnlocking(uint256 alicePurchaseAmount, uint256 bobPurchaseAmount)
testFuzz__ExcessBRRPurchaseTriggersCappingAndRefund(uint256 initialUsdcAmount, uint256 finalUsdcAmount)
```

**Coverage**: ~90%
- ❌ Missing: Vesting cliff tests (no cliff currently)
- ❌ Missing: Sybil attack resistance tests

---

### 7. ApiaryYieldManager Tests

**File**: `test/ApiaryYieldManager.t.sol`

**Coverage**:
- ✅ Yield execution (Phase 1 strategy)
- ✅ Strategy changes
- ✅ Split configuration
- ✅ Slippage tolerance
- ✅ Emergency mode
- ✅ Adapter management

**Key Test Cases**:
```solidity
// Execution tests
testExecuteYield()
testExecuteYieldPhase1Strategy()
testExecuteYieldInsufficientYieldReverts()
testExecuteYieldDuringPauseReverts()

// Strategy tests
testSetStrategyPhase1()
testSetStrategyPhase2()
testSetStrategyPhase3()
testSetStrategyOnlyOwner()

// Split config tests
testSetSplitConfigValid()
testSetSplitConfigSumNot100Reverts()
testSetSplitConfigIndividualPercents()

// Emergency tests
testSetEmergencyMode()
testExecuteYieldDuringEmergency()
testEmergencyWithdraw()

// Fuzz tests
testFuzz_SetSlippageTolerance(uint256 slippage)
testFuzz_SetSplitPercentages(uint256 toHoney, uint256 toApiaryLP, uint256 toBurn)
```

**Coverage**: ~85%
- ❌ Missing: Sandwich attack simulation
- ❌ Missing: Adapter failure handling tests
- ❌ Missing: Phase 2 & 3 strategy tests (not implemented yet)

---

### 8. ApiaryInfraredAdapter Tests

**File**: `test/ApiaryInfraredAdapter.t.sol`

**Coverage**:
- ✅ Deployment & configuration
- ✅ Staking iBGT
- ✅ Unstaking iBGT
- ✅ Claiming rewards
- ✅ Auto-compounding
- ✅ Emergency withdrawal
- ✅ Access control

**Key Test Cases**:
```solidity
// Deployment tests
testDeployment()
testDeploymentRevertsZeroAddress()

// Staking tests
testStake()
testStakeRevertsNonYieldManager()
testStakeRevertsZeroAmount()
testStakeRevertsBelowMinimum()
testStakeWhenPaused()

// Unstaking tests
testUnstake()
testUnstakeRevertsInsufficientStaked()
testUnstakeRevertsZeroAmount()
testUnstakeWithFee()

// Rewards tests
testClaimRewards()
testClaimRewardsRevertsNoRewards()
testAutoCompound()

// Multi-operation tests
testStakeUnstakeMultipleTimes()
testClaimRewardsMultipleTimes()

// Fuzz tests
testFuzzStake(uint256 amount)
```

**Coverage**: ~90%
- ❌ Missing: Infrared contract upgrade impact tests
- ❌ Missing: Infrared pause/emergency tests

---

### 9. ApiaryKodiakAdapter Tests

**File**: `test/ApiaryKodiakAdapter.t.sol`

**Coverage**:
- ✅ Swapping (iBGT → HONEY, iBGT → APIARY)
- ✅ LP creation (APIARY/HONEY)
- ✅ LP staking
- ✅ LP reward claiming
- ✅ Slippage protection
- ✅ Emergency withdrawal

**Key Test Cases**:
```solidity
// Swap tests
testSwapIBGTForHoney()
testSwapIBGTForApiary()
testSwapRevertsExcessiveSlippage()
testSwapRevertsZeroAmount()

// LP tests
testAddLiquidityApiaryHoney()
testAddLiquidityRevertsBelowMinimum()
testStakeLPTokens()
testUnstakeLPTokens()
testClaimLPRewards()

// Emergency tests
testEmergencyWithdraw()
testEmergencyWithdrawOnlyOwner()

// Fuzz tests
testFuzzSwap(uint256 amountIn)
```

**Coverage**: ~85%
- ❌ Missing: Front-running simulation tests
- ❌ Missing: Kodiak pool manipulation tests
- ❌ Missing: Multi-DEX fallback tests (not implemented)

---

### 10. ApiaryUniswapV2TwapOracle Tests

**File**: `test/BeraReserveUniswapV2TwapOracleTest.sol`

**Coverage**:
- ⚠️ Limited tests (oracle is critical!)
- ✅ Basic update functionality
- ❌ Missing comprehensive TWAP tests

**Needed Test Cases**:
```solidity
// Basic tests
testOracleUpdate()
testOracleConsult()
testMinimumUpdateInterval()

// Manipulation tests (NEEDED)
testTWAPResistsSingleBlockManipulation()
testTWAPShortWindowManipulation()
testOracleStaleness()
testPriceDeviationCircuitBreaker()
```

**Coverage**: ~40% ⚠️ CRITICAL GAP

---

## Integration Tests

### 1. Full Protocol Integration

**File**: `test/integration/ApiaryIntegration.t.sol`

**Coverage**:
- ✅ End-to-end bond purchase → vesting → redemption
- ✅ Stake → rebase → unstake flow
- ✅ Treasury → YieldManager → Adapters flow
- ✅ Pre-sale → TGE → vesting flow

**Key Scenarios**:
```solidity
// Full protocol lifecycle
testFullBondLifecycle()
testFullStakingLifecycle()
testFullYieldDistributionLifecycle()
testFullPreSaleLifecycle()

// Multi-user scenarios
testMultipleUsersBondingAndStaking()
testSimultaneousBondAndStakeOperations()

// Cross-contract interactions
testTreasuryLendsToYieldManager()
testYieldManagerDistributesToStakers()
testBondDepositoryMintsFromTreasury()
```

**Coverage**: ~70%
- ❌ Missing: Failure cascade tests (what if adapter fails during yield?)
- ❌ Missing: State recovery tests

---

### 2. Security-Focused Tests

**File**: `test/integration/ApiarySecurity.t.sol`

**Coverage**:
- ✅ Reentrancy protection
- ✅ Access control enforcement
- ✅ Pausable mechanisms
- ✅ Emergency withdrawals
- ✅ Invariant checks

**Key Test Cases**:
```solidity
// Reentrancy tests
testReentrancyProtectionOnYieldExecution()
testReentrancyProtectionOnTreasuryDeposit()
testReentrancyProtectionOnBondRedeem()

// Access control tests
testOnlyOwnerCanSetAdapters()
testOnlyYieldManagerCanBorrowIBGT()
testOnlyMinterCanMintAPARY()

// Emergency tests
testPauseStopsAllOperations()
testEmergencyWithdrawWorks()
testEmergencyModeBypassesAdapters()

// Invariant tests
testInvariant_SplitPercentagesSum()        // ✅
testInvariant_NoTokensStuck()              // ✅
testInvariant_TotalYieldIncreasing()       // ✅
```

**Coverage**: ~75%
- ❌ Missing: Flash loan attack simulations
- ❌ Missing: Oracle manipulation simulations
- ❌ Missing: Sandwich attack simulations

---

## Fuzz Tests

### Comprehensive Fuzzing

**File**: `test/integration/ApiaryFuzz.t.sol`

**Fuzz Test Coverage**:

#### 1. Split Percentages Validation
```solidity
testFuzz_SplitPercentagesValidation(
    uint16 toHoney,
    uint16 toApiaryLP,
    uint16 toBurn,
    uint16 toStakers,
    uint16 toCompound
)
```
**Fuzzing**: 10,000+ random combinations
**Validates**: Sum = 10000, individual ≤ 10000

#### 2. Valid Splits Always Sum to 100%
```solidity
testFuzz_ValidSplitsAlwaysSum10000(uint16 a, uint16 b, uint16 c, uint16 d)
```
**Fuzzing**: Normalized splits
**Validates**: Always sum to 10000

#### 3. Slippage Tolerance
```solidity
testFuzz_SlippageToleranceValidation(uint256 slippage)
testFuzz_SlippageCalculation(uint256 amount, uint16 tolerance)
```
**Fuzzing**: 0 to max uint256
**Validates**: Slippage ≤ 100%, calculations correct

#### 4. Min/Max Amounts
```solidity
testFuzz_MinimumYieldAmount(uint256 minAmount)
testFuzz_MaximumExecutionAmount(uint256 maxAmount)
testFuzz_MCThresholdMultiplier(uint256 multiplier)
```
**Fuzzing**: Wide range of values
**Validates**: Reasonable bounds

#### 5. Time Manipulation
```solidity
testFuzz_TimeAdvancement(uint32 timeIncrease)
```
**Fuzzing**: Time skips up to 1 year
**Validates**: Epoch handling, vesting calculations

#### 6. Strategy Changes
```solidity
testFuzz_StrategyChanges(uint8 strategyId)
```
**Fuzzing**: All strategy enum values
**Validates**: Strategy transitions

#### 7. Edge Cases
```solidity
testFuzz_ZeroValues(bool useZeroHoney, bool useZeroLP, bool useZeroBurn)
testFuzz_MaximumValues()
```
**Validates**: Zero amounts, max amounts

---

## Invariant Tests

### Foundry Invariant Testing

**File**: `test/integration/ApiaryFuzz.t.sol`

**Invariants Tested**:

#### INV-1: Split Percentages Sum
```solidity
function invariant_SplitPercentagesSum() public view {
    SplitConfig memory config = yieldManager.splitConfig();
    assertEq(
        config.toHoney + config.toApiaryLP + config.toBurn + 
        config.toStakers + config.toCompound,
        10000
    );
}
```
**Status**: ✅ PASSING (100% runs)

#### INV-2: Slippage Tolerance Maximum
```solidity
function invariant_SlippageToleranceMax() public view {
    assertLe(yieldManager.slippageTolerance(), 10000);
}
```
**Status**: ✅ PASSING (100% runs)

#### INV-3: Total Yield Monotonic
```solidity
function invariant_TotalYieldMonotonic() public view {
    uint256 current = yieldManager.totalYieldProcessed();
    assertGe(current, ghost_prevTotalYield);
}
```
**Status**: ✅ PASSING (100% runs)

#### INV-4: Valid Owner
```solidity
function invariant_ValidOwner() public view {
    assertNotEq(yieldManager.owner(), address(0));
    assertNotEq(treasury.owner(), address(0));
}
```
**Status**: ✅ PASSING (100% runs)

---

### Missing Invariants ⚠️

**Critical Invariants NOT Tested**:

1. **Total Supply Cap**:
   ```solidity
   invariant_totalSupplyCap() → assertLe(apiary.totalSupply(), 200_000e9)
   ```

2. **Supply Equals Balances**:
   ```solidity
   invariant_supplyEqualsBalances() → requires ghost variable tracking
   ```

3. **Staked Equals Index**:
   ```solidity
   invariant_stakedEqualsIndex() → APIARY in staking = sAPIARY value
   ```

4. **Total Debt Consistency**:
   ```solidity
   invariant_totalDebtConsistency() → totalDebt = sum(bond payouts)
   ```

5. **Treasury iBGT Accounting**:
   ```solidity
   invariant_treasuryIBGTAccounting() → total = available + staked
   ```

**Recommendation**: Implement comprehensive invariant test suite (see [INVARIANTS.md](./INVARIANTS.md))

---

## Coverage Gaps

### Critical Gaps (Must Fix Before Audit)

1. **Oracle Tests** ⚠️ ~40% coverage
   - ❌ TWAP manipulation resistance
   - ❌ Staleness checks
   - ❌ Price deviation circuit breaker
   - ❌ Multi-oracle fallback

2. **Flash Loan Attack Tests** ⚠️ 0% coverage
   - ❌ Flash loan staking attack
   - ❌ Flash loan LP manipulation
   - ❌ `lastTimeStaked` enforcement

3. **Front-Running Tests** ⚠️ 0% coverage
   - ❌ Bond purchase front-running
   - ❌ Yield execution sandwich
   - ❌ Oracle update front-running

4. **Admin Compromise Tests** ⚠️ 0% coverage
   - ❌ Malicious adapter setting
   - ❌ Bond term manipulation
   - ❌ Treasury drainage

5. **External Protocol Failure Tests** ⚠️ 10% coverage
   - ❌ Infrared upgrade/pause
   - ❌ Kodiak liquidity drain
   - ❌ Adapter failure cascades

---

### Medium Priority Gaps

1. **Invariant Test Suite** ⚠️ 30% coverage
   - Need: Comprehensive handler-based invariants
   - Need: Ghost variable tracking for balances
   - Need: Multi-contract state consistency checks

2. **Edge Case Tests**
   - ❌ Max uint256 values
   - ❌ Zero values in all functions
   - ❌ Rounding errors in calculations

3. **Gas Optimization Tests**
   - ❌ Batch operations gas usage
   - ❌ Large-scale fuzzing for gas spikes

---

## Coverage Metrics

### Estimated Coverage by Contract

| Contract | Unit Tests | Integration | Fuzz | Invariant | Total Est. |
|----------|-----------|-------------|------|-----------|-----------|
| ApiaryToken | 85% | 70% | 60% | 0% | **75%** |
| sApiary | 80% | 70% | 50% | 0% | **70%** |
| ApiaryTreasury | 90% | 75% | 65% | 0% | **80%** |
| ApiaryStaking | 85% | 75% | 70% | 0% | **78%** |
| ApiaryBondDepository | 95% | 80% | 80% | 0% | **88%** |
| ApiaryPreSaleBond | 90% | 70% | 60% | 0% | **76%** |
| ApiaryYieldManager | 85% | 70% | 75% | 25% | **75%** |
| ApiaryInfraredAdapter | 90% | 65% | 50% | 0% | **72%** |
| ApiaryKodiakAdapter | 85% | 60% | 55% | 0% | **70%** |
| ApiaryUniswapV2TwapOracle | **40%** ⚠️ | 30% | 20% | 0% | **32%** ⚠️ |
| **Protocol Average** | **84%** | **68%** | **59%** | **3%** | **72%** |

### Coverage by Test Type

| Test Type | Files | Tests | Coverage |
|-----------|-------|-------|----------|
| Unit Tests | 13 | ~150 | ~84% |
| Integration Tests | 3 | ~30 | ~68% |
| Fuzz Tests | 11 | ~30 | ~59% |
| Invariant Tests | 1 | 4 | ~3% ⚠️ |
| **Total** | **18** | **~214** | **~72%** |

---

## Test Execution

### Running Tests

```bash
# All tests
forge test

# Specific contract
forge test --match-contract ApiaryYieldManagerTest

# Specific test
forge test --match-test testExecuteYield

# With gas report
forge test --gas-report

# With coverage
forge coverage

# With verbosity (see traces)
forge test -vvv

# Fuzz tests (increase runs)
forge test --fuzz-runs 10000
```

### Expected Results

**All Tests Should Pass**:
```
[PASS] testExecuteYield()
[PASS] testStake()
[PASS] testBondDeposit()
...
Test result: ok. 214 passed; 0 failed; finished in 45.32s
```

---

## Recommendations

### Before Security Audit

1. **Implement Oracle Test Suite** (Priority: 🔴 CRITICAL)
   ```solidity
   // Add to test/ApiaryUniswapV2TwapOracle.t.sol
   testTWAPResistsSingleBlockManipulation()
   testTWAPShortWindowManipulation()
   testOracleStalenessPreventsDeposit()
   testPriceDeviationCircuitBreaker()
   testMultiOracleFallback() // If implemented
   ```

2. **Add Flash Loan Attack Tests** (Priority: 🔴 CRITICAL)
   ```solidity
   // Add to test/integration/ApiarySecurity.t.sol
   testFlashLoanStakingAttackFails()
   testFlashLoanLPManipulationFails()
   testLastTimeStakedEnforcement()
   ```

3. **Add Front-Running Simulation Tests** (Priority: 🟠 HIGH)
   ```solidity
   testBondPurchaseFrontRunning()
   testYieldExecutionSandwich()
   testOracleUpdateFrontRunning()
   ```

4. **Implement Comprehensive Invariant Tests** (Priority: 🟠 HIGH)
   ```solidity
   // Use handler-based invariant testing
   invariant_totalSupplyCap()
   invariant_supplyEqualsBalances()
   invariant_stakedEqualsIndex()
   invariant_totalDebtConsistency()
   invariant_treasuryIBGTAccounting()
   ```

5. **Add Admin Compromise Tests** (Priority: 🟡 MEDIUM)
   ```solidity
   testMaliciousAdminCannotDrainTreasury()
   testTimelockPreventsInstantAdapterChange()
   testMultiSigRequiredForCriticalFunctions()
   ```

6. **External Protocol Failure Tests** (Priority: 🟡 MEDIUM)
   ```solidity
   testInfraredPauseTriggersEmergencyWithdraw()
   testKodiakLiquidityDrainHandled()
   testAdapterFailureDoesNotBrickProtocol()
   ```

---

### Test Coverage Goals

**Target Coverage** (Before Mainnet):
- **Unit Tests**: 95%+
- **Integration Tests**: 85%+
- **Fuzz Tests**: 75%+
- **Invariant Tests**: 50%+ (comprehensive suite)
- **Overall**: 85%+

**Current vs Target**:
| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Unit | 84% | 95% | -11% |
| Integration | 68% | 85% | -17% |
| Fuzz | 59% | 75% | -16% |
| Invariant | 3% | 50% | -47% ⚠️ |
| Overall | 72% | 85% | -13% |

---

### Example Invariant Test Implementation

```solidity
// test/invariants/ApiaryInvariants.t.sol
contract ApiaryInvariantsTest is Test {
    // Declare handlers
    TokenHandler tokenHandler;
    StakingHandler stakingHandler;
    BondHandler bondHandler;
    
    function setUp() public {
        // Deploy protocol
        deployProtocol();
        
        // Setup handlers
        tokenHandler = new TokenHandler(apiary, actors);
        stakingHandler = new StakingHandler(staking, sApiary, actors);
        bondHandler = new BondHandler(bondDepository, actors);
        
        // Target handlers for fuzzing
        targetContract(address(tokenHandler));
        targetContract(address(stakingHandler));
        targetContract(address(bondHandler));
    }
    
    // Critical invariants
    function invariant_totalSupplyCap() public {
        assertLe(apiary.totalSupply(), 200_000e9);
    }
    
    function invariant_supplyEqualsBalances() public {
        assertEq(apiary.totalSupply(), tokenHandler.ghost_sumOfBalances());
    }
    
    function invariant_stakedEqualsIndex() public {
        uint256 apiaryInStaking = apiary.balanceOf(address(staking));
        uint256 sApiarySupply = sApiary.totalSupply();
        uint256 index = sApiary.index();
        uint256 expectedApiary = (sApiarySupply * index) / 1e9;
        assertApproxEqRel(apiaryInStaking, expectedApiary, 1e15); // 0.1% tolerance
    }
    
    function invariant_totalDebtConsistency() public {
        assertEq(bondDepository.totalDebt(), bondHandler.ghost_sumOfBondPayouts());
    }
    
    function invariant_treasuryIBGTAccounting() public {
        uint256 total = treasury.totalReserves(IBGT);
        uint256 available = treasury.getAvailableIBGT();
        uint256 staked = treasury.getTotalStaked();
        assertEq(total, available + staked);
    }
}
```

---

### Example Handler Implementation

```solidity
// test/invariants/handlers/TokenHandler.sol
contract TokenHandler is Test {
    ApiaryToken public apiary;
    address[] public actors;
    
    // Ghost variables for tracking
    mapping(address => uint256) public balances;
    uint256 public ghost_sumOfBalances;
    
    function mint(uint256 actorIndex, uint256 amount) public {
        address actor = actors[actorIndex % actors.length];
        amount = bound(amount, 0, apiary.allocationLimits(actor));
        
        vm.prank(actor);
        apiary.mint(actor, amount);
        
        // Update ghost variables
        balances[actor] += amount;
        ghost_sumOfBalances += amount;
    }
    
    function burn(uint256 actorIndex, uint256 amount) public {
        address actor = actors[actorIndex % actors.length];
        amount = bound(amount, 0, balances[actor]);
        
        vm.prank(actor);
        apiary.burn(amount);
        
        // Update ghost variables
        balances[actor] -= amount;
        ghost_sumOfBalances -= amount;
    }
    
    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) public {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        amount = bound(amount, 0, balances[from]);
        
        vm.prank(from);
        apiary.transfer(to, amount);
        
        // Update ghost variables
        balances[from] -= amount;
        balances[to] += amount;
        // ghost_sumOfBalances unchanged (transfer doesn't change total)
    }
}
```

---

**For security testing focus, see [ATTACK_VECTORS.md](./ATTACK_VECTORS.md)**
**For expected invariants, see [INVARIANTS.md](./INVARIANTS.md)**
**For architecture overview, see [ARCHITECTURE.md](./ARCHITECTURE.md)**
