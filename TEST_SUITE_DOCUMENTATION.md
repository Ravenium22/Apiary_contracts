# Apiary Protocol - Comprehensive Test Suite Documentation

## 📋 Overview

This document outlines the comprehensive test suite for the Apiary protocol, covering integration tests, security tests, fuzz tests, and invariant tests.

**Test Framework**: Foundry  
**Solidity Version**: 0.8.26  
**Test Coverage Goal**: >95%

---

## 🗂️ Test Suite Structure

```
test/
├── integration/
│   ├── TestSetup.sol              # Base test setup with mocks
│   ├── ApiaryIntegration.t.sol    # Full protocol integration tests
│   ├── ApiarySecurity.t.sol       # Security-focused tests
│   └── ApiaryFuzz.t.sol            # Fuzz and invariant tests
│
├── ApiaryYieldManager.t.sol        # Unit tests for yield manager
├── ApiaryPreSaleBond.t.sol         # Pre-sale bond tests
├── ApiaryInfraredAdapter.t.sol     # Infrared adapter tests
└── ApiaryKodiakAdapter.t.sol       # Kodiak adapter tests
```

---

## 🧪 Test Categories

### 1. Integration Tests (`ApiaryIntegration.t.sol`)

**Purpose**: Test complete user journeys and protocol interactions

#### Test 1: Full Pre-Sale Journey
```solidity
test_Integration_PreSaleFullJourney()
```
- ✅ User is whitelisted (merkle proof)
- ✅ User purchases APIARY with HONEY
- ✅ 110% bonus applied correctly
- ✅ Vesting works over 30 days
- ✅ Partial claims at 50% vesting
- ✅ Full claim after 30 days

**Expected Results**:
- User receives 110% APIARY for HONEY spent
- Vesting is linear over 30 days
- Claims work at any point during vesting

#### Test 2: Multiple Users Pre-Sale
```solidity
test_Integration_PreSaleMultipleUsers()
```
- ✅ Multiple users can purchase
- ✅ Individual limits enforced
- ✅ Total allocation tracked
- ✅ Cannot exceed limits

#### Test 3: Full Yield Journey
```solidity
test_Integration_YieldFullJourney()
```
**Flow**:
1. Treasury stakes iBGT on Infrared
2. Wait 7 days, yield accumulates
3. Keeper executes yield strategy
4. 25% → HONEY swap
5. 25% → APIARY burn
6. 50% → APIARY + HONEY LP → stake

**Validations**:
- `totalYield` matches pending yield
- `honeySwapped` > 0
- `apiaryBurned` > 0
- `lpCreated` > 0
- Phase 1: `compounded` = 0

#### Test 4: Yield Slippage Protection
```solidity
test_Integration_YieldSlippageProtection()
```
- ✅ High slippage tolerance (1%) succeeds
- ✅ Low slippage tolerance (0.01%) may fail
- ✅ Slippage protection prevents value loss

#### Test 5: Yield Strategy Switching
```solidity
test_Integration_YieldStrategySwitch()
```
- ✅ Switch from Phase 1 → Phase 2
- ✅ Update split percentages
- ✅ Execute Phase 2 strategy
- ✅ Conditional logic based on MC/TV

#### Test 6: LP Rewards Journey
```solidity
test_Integration_LPRewardsJourney()
```
- ✅ Add liquidity to APIARY/HONEY pool
- ✅ Stake LP tokens on Kodiak gauge
- ✅ Accumulate rewards over time
- ✅ Claim xKDK/BGT rewards

#### Test 7: Multi-User Scenarios
```solidity
test_Integration_MultiUserScenarios()
```
- ✅ User1 buys pre-sale
- ✅ User2 buys pre-sale
- ✅ Treasury executes yield
- ✅ Users claim vested APIARY
- ✅ All operations work concurrently

#### Test 8: Emergency Scenarios

**Emergency Pause**:
```solidity
test_Integration_EmergencyPauseAndRecovery()
```
- ✅ Owner can pause
- ✅ Execution reverts when paused
- ✅ Owner can unpause
- ✅ Execution resumes after unpause

**Emergency Mode**:
```solidity
test_Integration_EmergencyMode()
```
- ✅ Owner enables emergency mode
- ✅ Swaps bypassed
- ✅ Raw iBGT forwarded to treasury
- ✅ No burns, no LP creation
- ✅ Owner can disable emergency mode

**Emergency Withdraw**:
```solidity
test_Integration_EmergencyWithdraw()
```
- ✅ Tokens accidentally sent to contract
- ✅ Owner can recover stuck tokens
- ✅ Non-owner cannot withdraw

#### Test 9: Edge Cases

**Zero Yield**:
```solidity
test_Integration_ZeroYield()
```
- ✅ Reverts with `APIARY__NO_PENDING_YIELD`

**Dust Amount**:
```solidity
test_Integration_DustAmount()
```
- ✅ Below minimum (0.1 iBGT)
- ✅ Reverts with `APIARY__INSUFFICIENT_YIELD`

**Max Execution Cap**:
```solidity
test_Integration_MaxExecutionCap()
```
- ✅ Large yield (15k iBGT)
- ✅ Caps at maxExecutionAmount (10k)
- ✅ Remaining yield still pending

#### Test 10: Gas Optimization
```solidity
test_Integration_GasUsage()
```
- ✅ Measure gas for `executeYield()`
- ✅ Gas < 1M for Phase 1
- ✅ Optimize multi-step operations

**Expected Gas**:
- Phase 1: ~600k gas
- Phase 2: ~400k gas
- Phase 3: ~150k gas

---

### 2. Security Tests (`ApiarySecurity.t.sol`)

**Purpose**: Test attack vectors and security measures

#### Reentrancy Protection

**Test 1: Direct Reentrancy**:
```solidity
test_Security_ReentrancyProtection()
```
- ✅ Deploy malicious contract
- ✅ Attempt reentrancy attack
- ✅ Should revert with `ReentrancyGuard` error

**Test 2: Callback Reentrancy**:
```solidity
testFail_Security_ReentrancyViaCallback()
```
- ✅ Malicious token with callback
- ✅ Attempt reentrancy during transfer
- ✅ Should fail (test expected to fail)

#### Access Control

**All Admin Functions**:
```solidity
test_Security_OnlyOwnerCanChangeStrategy()
test_Security_OnlyOwnerCanSetSplits()
test_Security_OnlyOwnerCanSetAdapters()
test_Security_OnlyOwnerCanPause()
test_Security_OnlyOwnerCanEmergencyWithdraw()
test_Security_AdapterAccessControl()
```
- ✅ Non-owner cannot call admin functions
- ✅ All revert with `Ownable` error

#### Malicious Adapter Tests

**Drain Attack**:
```solidity
test_Security_MaliciousAdapterDrain()
```
- ✅ Malicious adapter set
- ✅ Cannot drain yield manager
- ✅ No token approvals to adapter

**Zero Address**:
```solidity
test_Security_ZeroAddressAdapter()
```
- ✅ Reverts with `APIARY__ZERO_ADDRESS`

#### Overflow/Underflow Tests

**Split Overflow**:
```solidity
test_Security_SplitPercentagesOverflow()
```
- ✅ `type(uint256).max` input
- ✅ Reverts with `APIARY__INVALID_SPLIT_CONFIG`

**Large Yield**:
```solidity
test_Security_LargeYieldNoOverflow()
```
- ✅ 1M iBGT yield
- ✅ Caps at maxExecutionAmount
- ✅ No overflow

#### Slippage Attack Tests

**Sandwich Attack Protection**:
```solidity
test_Security_SlippageProtection()
```
- ✅ Set tight slippage tolerance
- ✅ Execution protected
- ✅ Reverts if slippage exceeded

**Max Slippage**:
```solidity
test_Security_SlippageToleranceMax()
```
- ✅ Cannot exceed 10% (1000 BPS)
- ✅ Reverts with `APIARY__SLIPPAGE_TOO_HIGH`

#### Front-Running Tests

**TWAP Protection**:
```solidity
test_Security_TWAPProtection()
```
- ✅ Attacker flash loans to manipulate price
- ✅ TWAP averages over multiple blocks
- ✅ Single-block manipulation ineffective

#### DOS Attack Tests

**Gas Limit DOS**:
```solidity
test_Security_GasLimitProtection()
```
- ✅ Massive yield (50k iBGT)
- ✅ `maxExecutionAmount` batches execution
- ✅ No gas limit DOS

**Paused State DOS**:
```solidity
test_Security_PausedStatePreventsExecution()
```
- ✅ Paused state blocks execution
- ✅ Prevents DOS via repeated calls

#### Ownership Attack Tests

**Two-Step Transfer**:
```solidity
test_Security_TwoStepOwnershipTransfer()
```
- ✅ Owner initiates transfer
- ✅ Pending owner must accept
- ✅ Prevents accidental transfers

**Ownership Theft**:
```solidity
test_Security_CannotStealOwnership()
```
- ✅ Attacker cannot transfer ownership
- ✅ Reverts with `Ownable` error

#### Emergency Tests

**Emergency Mode Protection**:
```solidity
test_Security_EmergencyModeProtection()
```
- ✅ Detects adapter compromise
- ✅ Enables emergency mode
- ✅ Bypasses swaps
- ✅ Forwards iBGT to treasury safely

**Emergency Withdraw Access**:
```solidity
test_Security_EmergencyWithdrawOnlyOwner()
```
- ✅ Only owner can withdraw
- ✅ Attacker cannot steal stuck tokens

#### Invariant Tests

**Invariant 1: Splits Always Sum to 100%**:
```solidity
testInvariant_SplitPercentagesSum()
```
- ✅ After any split update
- ✅ Sum = 10000 BPS (100%)

**Invariant 2: No Tokens Stuck**:
```solidity
testInvariant_NoTokensStuck()
```
- ✅ After yield execution
- ✅ iBGT balance = 0
- ✅ APIARY balance ≈ 0 (dust allowed)
- ✅ HONEY balance ≈ 0 (dust allowed)

**Invariant 3: Total Yield Monotonic**:
```solidity
testInvariant_TotalYieldIncreasing()
```
- ✅ `totalYieldProcessed` never decreases
- ✅ Monotonically increasing

---

### 3. Fuzz Tests (`ApiaryFuzz.t.sol`)

**Purpose**: Test protocol with random inputs

#### Split Percentages Fuzzing

**Fuzz 1: Invalid Splits**:
```solidity
testFuzz_SplitPercentagesValidation(...)
```
- **Inputs**: 5 random uint256 values
- **Validation**: Sum must equal 10000
- **Result**: Reverts if sum ≠ 10000

**Fuzz 2: Valid Splits**:
```solidity
testFuzz_ValidSplitsAlwaysSum10000(...)
```
- **Inputs**: 4 random uint16 values
- **Generation**: Ensure sum = 10000
- **Result**: Always succeeds, sum = 10000

#### Slippage Fuzzing

**Fuzz 3: Slippage Validation**:
```solidity
testFuzz_SlippageToleranceValidation(uint256)
```
- **Input**: Random slippage value
- **Validation**: Must be ≤ 1000 (10%)
- **Result**: Reverts if > 1000

**Fuzz 4: Slippage Calculation**:
```solidity
testFuzz_SlippageCalculation(uint256, uint16)
```
- **Inputs**: Amount (1 - 1M iBGT), Tolerance (0 - 10%)
- **Validation**: `minOutput ≤ amount`
- **Result**: Math always correct

#### Amount Fuzzing

**Fuzz 5-7: Parameter Fuzzing**:
```solidity
testFuzz_MinimumYieldAmount(uint256)
testFuzz_MaximumExecutionAmount(uint256)
testFuzz_MCThresholdMultiplier(uint256)
```
- **Inputs**: Random amounts
- **Bounds**: Reasonable ranges
- **Result**: Parameters set correctly

#### Time Fuzzing

**Fuzz 8: Time Advancement**:
```solidity
testFuzz_TimeAdvancement(uint32)
```
- **Input**: 1 second to 1 year
- **Result**: State remains valid

#### Strategy Fuzzing

**Fuzz 9: Strategy Changes**:
```solidity
testFuzz_StrategyChanges(uint8)
```
- **Input**: 0-2 (valid strategies)
- **Result**: Strategy changes successfully

#### Edge Case Fuzzing

**Fuzz 10: Zero Values**:
```solidity
testFuzz_ZeroValues(bool, bool, bool)
```
- **Inputs**: Zero flags for each split
- **Validation**: Still sum to 10000
- **Result**: Always valid

**Fuzz 11: Maximum Values**:
```solidity
testFuzz_MaximumValues()
```
- **Inputs**: `type(uint256).max` values
- **Result**: Handles max values gracefully

---

## 🎯 Test Coverage Goals

### Coverage by Category

| Category | Target Coverage | Current Status |
|----------|----------------|----------------|
| **Unit Tests** | 100% | ⏳ Pending |
| **Integration Tests** | 95% | ✅ Complete |
| **Security Tests** | 100% | ✅ Complete |
| **Fuzz Tests** | N/A | ✅ Complete |
| **Invariant Tests** | 100% | ✅ Complete |

### Coverage by Contract

| Contract | Lines | Branches | Functions | Statements |
|----------|-------|----------|-----------|------------|
| ApiaryYieldManager | >95% | >90% | 100% | >95% |
| ApiaryInfraredAdapter | >95% | >90% | 100% | >95% |
| ApiaryKodiakAdapter | >95% | >90% | 100% | >95% |
| ApiaryPreSaleBond | >95% | >90% | 100% | >95% |

---

## 🚀 Running Tests

### All Tests
```bash
forge test
```

### Integration Tests Only
```bash
forge test --match-contract ApiaryIntegration
```

### Security Tests Only
```bash
forge test --match-contract ApiarySecurity
```

### Fuzz Tests Only
```bash
forge test --match-contract ApiaryFuzz
```

### Specific Test
```bash
forge test --match-test test_Integration_YieldFullJourney -vvv
```

### With Gas Report
```bash
forge test --gas-report
```

### With Coverage
```bash
forge coverage
```

### With Coverage Report (lcov)
```bash
forge coverage --report lcov
genhtml lcov.info -o coverage/
```

---

## 📊 Test Results Summary

### Expected Test Counts

| Test Suite | Test Count | Expected Duration |
|------------|-----------|-------------------|
| ApiaryIntegration.t.sol | 10 tests | ~30 seconds |
| ApiarySecurity.t.sol | 25 tests | ~45 seconds |
| ApiaryFuzz.t.sol | 11 tests | ~60 seconds (fuzzing) |
| **Total** | **46 tests** | **~2 minutes** |

### Test Execution Example

```
Running 46 tests for test/integration/ApiaryIntegration.t.sol
[PASS] test_Integration_PreSaleFullJourney() (gas: 234567)
[PASS] test_Integration_PreSaleMultipleUsers() (gas: 345678)
[PASS] test_Integration_YieldFullJourney() (gas: 567890)
...
Test result: ok. 46 passed; 0 failed; finished in 2.13s
```

---

## 🔍 Edge Cases Covered

### 1. Zero Values
- ✅ Zero yield pending
- ✅ Zero slippage tolerance
- ✅ Zero splits (where allowed)

### 2. Dust Amounts
- ✅ Below minimum yield (0.1 iBGT)
- ✅ Dust remaining after swaps
- ✅ Rounding errors

### 3. Maximum Values
- ✅ Maximum execution cap (10k iBGT)
- ✅ Massive yield accumulation
- ✅ `type(uint256).max` inputs

### 4. Time-Based
- ✅ No time passed (0 yield)
- ✅ Partial vesting
- ✅ Full vesting
- ✅ Beyond vesting period

### 5. State Transitions
- ✅ Normal → Paused → Normal
- ✅ Normal → Emergency → Normal
- ✅ Phase 1 → Phase 2 → Phase 3

### 6. Multi-User
- ✅ Concurrent purchases
- ✅ Concurrent claims
- ✅ Race conditions

### 7. Failure Scenarios
- ✅ Swap failure (slippage)
- ✅ LP creation failure
- ✅ Burn failure
- ✅ Partial execution failure

---

## 🐛 Invariant Testing Suggestions

### Stateful Fuzzing (Foundry Invariants)

```solidity
contract ApiaryInvariantTest is Test {
    ApiaryYieldManager yieldManager;
    
    function setUp() public {
        // Deploy contracts
        // Setup handlers for stateful fuzzing
    }
    
    // Invariant 1: Splits always sum to 10000
    function invariant_splitsSum() public {
        SplitConfig memory config = yieldManager.getSplitPercentages();
        uint256 total = config.toHoney + config.toApiaryLP + 
                       config.toBurn + config.toStakers + config.toCompound;
        assertEq(total, 10000);
    }
    
    // Invariant 2: Total yield never decreases
    function invariant_totalYieldMonotonic() public {
        uint256 current = yieldManager.totalYieldProcessed();
        // Track previous value
        assertGe(current, previousTotal);
    }
    
    // Invariant 3: No reentrancy possible
    function invariant_noReentrancy() public {
        // Check reentrancy guard state
    }
    
    // Invariant 4: Owner is never zero address
    function invariant_validOwner() public {
        assertTrue(yieldManager.owner() != address(0));
    }
}
```

### Run Invariant Tests
```bash
forge test --match-contract ApiaryInvariant
```

---

## 📝 Additional Testing Recommendations

### 1. **Mainnet Fork Testing**

Test against actual Berachain contracts:

```solidity
contract ApiaryMainnetForkTest is Test {
    function setUp() public {
        // Fork Berachain mainnet
        vm.createSelectFork("https://rpc.berachain.com");
        
        // Use real contracts
        address realInfrared = 0x...;
        address realKodiak = 0x...;
    }
}
```

### 2. **Load Testing**

Test protocol under heavy load:

```solidity
function test_LoadTesting_100Users() public {
    for (uint i = 0; i < 100; i++) {
        address user = makeAddr(string(abi.encodePacked("user", i)));
        // Execute operations
    }
}
```

### 3. **Upgrade Testing**

Test contract upgradeability (if using proxy pattern):

```solidity
function test_Upgrade_YieldManagerV2() public {
    // Deploy V1
    // Upgrade to V2
    // Verify state migration
}
```

### 4. **Economic Simulation**

Simulate various market conditions:

```solidity
function test_Economics_BullMarket() public {
    // Price increases 10x
    // Verify protocol behavior
}

function test_Economics_BearMarket() public {
    // Price decreases 90%
    // Verify protocol stability
}
```

---

## ✅ Pre-Deployment Test Checklist

- [ ] All unit tests passing (100%)
- [ ] All integration tests passing (46/46)
- [ ] All security tests passing (25/25)
- [ ] All fuzz tests passing (11/11)
- [ ] Code coverage >95%
- [ ] Gas optimization verified
- [ ] Mainnet fork tests passing
- [ ] Load tests passing (100+ users)
- [ ] Economic simulations passing
- [ ] Invariant tests running continuously
- [ ] Security audit completed
- [ ] Test documentation complete

---

## 🎓 Testing Best Practices

### 1. **Arrange-Act-Assert Pattern**

```solidity
function test_Example() public {
    // Arrange: Setup state
    vm.prank(user1);
    honeyToken.approve(address(contract), 1000e18);
    
    // Act: Execute function
    uint256 result = contract.doSomething(1000e18);
    
    // Assert: Verify outcome
    assertEq(result, expectedValue);
}
```

### 2. **Test Naming Convention**

```
test_{Category}_{Scenario}
testFuzz_{Category}_{Scenario}
testInvariant_{Property}
testFail_{Scenario} // Expected to fail
```

### 3. **Use Events for Verification**

```solidity
vm.expectEmit(true, true, false, true);
emit YieldExecuted(...);
yieldManager.executeYield();
```

### 4. **Bound Fuzz Inputs**

```solidity
function testFuzz_Example(uint256 input) public {
    input = bound(input, 1e18, 1000e18); // Bound to reasonable range
    // Test logic
}
```

### 5. **Test Gas Usage**

```solidity
uint256 gasBefore = gasleft();
contract.expensiveFunction();
uint256 gasUsed = gasBefore - gasleft();
assertLt(gasUsed, 500_000); // Assert reasonable gas
```

---

## 📚 Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Foundry Testing Guide](https://book.getfoundry.sh/forge/tests)
- [Fuzz Testing](https://book.getfoundry.sh/forge/fuzz-testing)
- [Invariant Testing](https://book.getfoundry.sh/forge/invariant-testing)
- [Gas Reporting](https://book.getfoundry.sh/forge/gas-reports)

---

**Last Updated**: December 12, 2025  
**Test Suite Version**: 1.0.0  
**Status**: ✅ Ready for Deployment Testing
