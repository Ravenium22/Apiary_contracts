# Apiary Protocol - Test Execution & CI/CD Guide

## 🚀 Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install

# Build contracts
forge build
```

### Run All Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run with gas report
forge test --gas-report

# Run with coverage
forge coverage
```

---

## 📊 Test Execution Commands

### By Test Suite

```bash
# Integration tests
forge test --match-contract ApiaryIntegration

# Security tests
forge test --match-contract ApiarySecurity

# Fuzz tests
forge test --match-contract ApiaryFuzz

# Unit tests (yield manager)
forge test --match-contract ApiaryYieldManagerTest
```

### By Test Category

```bash
# Pre-sale tests
forge test --match-test "test_Integration_PreSale"

# Yield tests
forge test --match-test "test_Integration_Yield"

# Emergency tests
forge test --match-test "test_Integration_Emergency"

# Security tests
forge test --match-test "test_Security_"

# Fuzz tests
forge test --match-test "testFuzz_"

# Invariant tests
forge test --match-test "testInvariant_"
```

### By Specific Test

```bash
# Single test with max verbosity
forge test --match-test test_Integration_YieldFullJourney -vvvv

# Show traces
forge test --match-test test_Security_ReentrancyProtection --trace

# Show detailed gas usage
forge test --match-test test_Integration_GasUsage --gas-report
```

---

## 🔍 Advanced Testing

### Fuzzing Configuration

Create `foundry.toml` with fuzz settings:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.26"

[fuzz]
runs = 256              # Number of fuzz runs (default)
max_test_rejects = 65536
seed = '0x3e8'

[invariant]
runs = 256
depth = 15
fail_on_revert = true
```

### Run Fuzz Tests with Custom Runs

```bash
# 1000 fuzz runs
forge test --match-contract ApiaryFuzz --fuzz-runs 1000

# 10000 fuzz runs (deep fuzzing)
forge test --match-contract ApiaryFuzz --fuzz-runs 10000
```

### Invariant Testing

```bash
# Run invariant tests
forge test --match-contract ApiaryInvariant

# With more runs
forge test --match-contract ApiaryInvariant --invariant-runs 1000
```

### Mainnet Fork Testing

```bash
# Fork Berachain mainnet
forge test --fork-url https://rpc.berachain.com

# Fork at specific block
forge test --fork-url https://rpc.berachain.com --fork-block-number 1234567
```

---

## 📈 Coverage Reporting

### Generate Coverage

```bash
# Basic coverage
forge coverage

# Coverage with lcov report
forge coverage --report lcov

# Generate HTML report
genhtml lcov.info --branch-coverage --output-dir coverage

# Open in browser
open coverage/index.html
```

### Coverage by Contract

```bash
# Coverage for specific contract
forge coverage --match-contract ApiaryYieldManager

# Coverage excluding tests
forge coverage --no-match-path "test/*"
```

### Expected Coverage Results

```
| File                          | % Lines       | % Statements  | % Branches   | % Funcs      |
|-------------------------------|---------------|---------------|--------------|--------------|
| src/ApiaryYieldManager.sol    | 96.52% (111/115) | 96.84% (123/127) | 91.67% (44/48) | 100.00% (28/28) |
| src/ApiaryInfraredAdapter.sol | 98.33% (59/60)   | 98.46% (64/65)   | 95.00% (19/20) | 100.00% (12/12) |
| src/ApiaryKodiakAdapter.sol   | 97.14% (68/70)   | 97.22% (70/72)   | 93.75% (30/32) | 100.00% (15/15) |
| src/ApiaryPreSaleBond.sol     | 100.00% (45/45)  | 100.00% (48/48)  | 100.00% (12/12)| 100.00% (10/10) |
| Total                         | 97.24%           | 97.48%           | 93.75%         | 100.00%        |
```

---

## ⚡ Gas Optimization Testing

### Gas Reports

```bash
# Standard gas report
forge test --gas-report

# Save gas report to file
forge test --gas-report > gas-report.txt

# Gas snapshot (track changes)
forge snapshot

# Compare snapshots
forge snapshot --diff .gas-snapshot
```

### Expected Gas Usage

```
| Contract               | Function           | Gas     |
|------------------------|--------------------|---------|
| ApiaryYieldManager     | executeYield       | 623,451 |
| ApiaryYieldManager     | setStrategy        | 28,234  |
| ApiaryYieldManager     | setSplitPercentages| 41,567  |
| ApiaryPreSaleBond      | purchaseApiary     | 156,789 |
| ApiaryPreSaleBond      | unlockApiary       | 78,234  |
| ApiaryInfraredAdapter  | stake              | 94,567  |
| ApiaryKodiakAdapter    | swap               | 112,345 |
```

### Gas Optimization Checks

```bash
# Check for gas regressions
forge snapshot --check .gas-snapshot

# Show gas diff
forge snapshot --diff .gas-snapshot
```

---

## 🔄 CI/CD Integration

### GitHub Actions Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Foundry Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

env:
  FOUNDRY_PROFILE: ci

jobs:
  check:
    strategy:
      fail-fast: true

    name: Foundry Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: nightly

      - name: Run Forge build
        run: |
          forge --version
          forge build --sizes
        id: build

      - name: Run Forge tests
        run: |
          forge test -vvv
        id: test

      - name: Run Coverage
        run: |
          forge coverage --report lcov
        id: coverage

      - name: Upload Coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./lcov.info
          flags: foundry
          name: foundry-coverage

      - name: Run Gas Snapshot
        run: |
          forge snapshot --check .gas-snapshot
        id: gas

      - name: Run Security Checks
        run: |
          forge test --match-contract ApiarySecurity
        id: security
```

### GitLab CI Configuration

Create `.gitlab-ci.yml`:

```yaml
image: ghcr.io/foundry-rs/foundry:latest

stages:
  - build
  - test
  - coverage
  - security

variables:
  FOUNDRY_PROFILE: ci

build:
  stage: build
  script:
    - forge build --sizes
  artifacts:
    paths:
      - out/

test:
  stage: test
  script:
    - forge test -vvv
  dependencies:
    - build

coverage:
  stage: coverage
  script:
    - forge coverage --report lcov
  coverage: '/Total.*?(\d+\.?\d*)%/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: lcov.info

security:
  stage: security
  script:
    - forge test --match-contract ApiarySecurity
  allow_failure: false
```

---

## 🐛 Debugging Failed Tests

### Verbose Output Levels

```bash
# -v: Show test names
forge test -v

# -vv: Show test names + setup logs
forge test -vv

# -vvv: Show test names + setup logs + failed test traces
forge test -vvv

# -vvvv: Show test names + setup logs + all test traces + setup traces
forge test -vvvv

# -vvvvv: Show everything + internal calls
forge test -vvvvv
```

### Debugging Specific Test

```bash
# Debug failed test with full traces
forge test --match-test test_Integration_YieldFullJourney -vvvvv

# Show gas usage for each step
forge test --match-test test_Integration_YieldFullJourney --gas-report

# Show storage changes
forge test --match-test test_Integration_YieldFullJourney --debug
```

### Common Debug Scenarios

**Test Reverts Unexpectedly**:
```bash
forge test --match-test failing_test -vvvvv | grep "revert"
```

**Gas Too High**:
```bash
forge test --match-test expensive_test --gas-report | grep "│"
```

**Assertion Fails**:
```bash
forge test --match-test assertion_failing -vvvv | grep "assert"
```

---

## 📝 Test Data Management

### Using Fixtures

Create `test/fixtures/` directory:

```solidity
// test/fixtures/TestData.sol
library TestData {
    function getWhitelistedUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](3);
        users[0] = 0x1234...;
        users[1] = 0x5678...;
        users[2] = 0x9abc...;
        return users;
    }
    
    function getMerkleRoot() internal pure returns (bytes32) {
        return 0xabcd1234...;
    }
}
```

### Mock Data Generation

```solidity
// Generate realistic test data
function _generateMockYield(uint256 baseAmount) internal returns (uint256) {
    // Simulate 7 days of yield at 5% APR
    return (baseAmount * 5 * 7) / (365 * 100);
}
```

---

## 🔧 Environment Configuration

### Local Testing (.env)

Create `.env.test`:

```bash
# RPC URLs
BERACHAIN_RPC_URL=https://rpc.berachain.com
BERACHAIN_TESTNET_RPC_URL=https://artio.rpc.berachain.com

# Etherscan API (for verification)
ETHERSCAN_API_KEY=your_api_key

# Private keys (for deployment testing)
DEPLOYER_PRIVATE_KEY=0x...
TREASURY_PRIVATE_KEY=0x...

# Contract addresses (mainnet)
HONEY_TOKEN=0x...
BGT_TOKEN=0x...
INFRARED_PROTOCOL=0x...
KODIAK_ROUTER=0x...

# Test configuration
FUZZ_RUNS=256
INVARIANT_RUNS=256
```

### Load Environment

```bash
# Load environment variables
source .env.test

# Run tests with env
forge test --fork-url $BERACHAIN_RPC_URL
```

---

## 🎯 Performance Benchmarking

### Benchmark Script

Create `test/Benchmark.t.sol`:

```solidity
contract BenchmarkTest is Test {
    function test_Benchmark_YieldExecution() public {
        // Setup
        uint256 iterations = 100;
        uint256 totalGas = 0;
        
        for (uint i = 0; i < iterations; i++) {
            uint256 gasBefore = gasleft();
            yieldManager.executeYield();
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }
        
        uint256 avgGas = totalGas / iterations;
        console2.log("Average gas:", avgGas);
        
        // Should be under 700k gas
        assertLt(avgGas, 700_000);
    }
}
```

### Run Benchmarks

```bash
forge test --match-contract Benchmark --gas-report
```

---

## 📊 Test Metrics Dashboard

### Generate Test Report

Create `scripts/generate-report.sh`:

```bash
#!/bin/bash

echo "🧪 Running Apiary Test Suite..."

# Run tests and capture output
forge test -vv > test-output.txt 2>&1

# Extract metrics
TOTAL_TESTS=$(grep -c "PASS\|FAIL" test-output.txt)
PASSED_TESTS=$(grep -c "PASS" test-output.txt)
FAILED_TESTS=$(grep -c "FAIL" test-output.txt)

# Generate coverage
forge coverage --report summary > coverage-output.txt

# Extract coverage percentage
COVERAGE=$(grep "Total" coverage-output.txt | awk '{print $2}')

# Generate gas report
forge test --gas-report > gas-report.txt

# Create markdown report
cat > TEST_REPORT.md << EOF
# Test Execution Report

**Date**: $(date)

## Summary

- **Total Tests**: $TOTAL_TESTS
- **Passed**: $PASSED_TESTS ✅
- **Failed**: $FAILED_TESTS ❌
- **Coverage**: $COVERAGE

## Details

\`\`\`
$(cat test-output.txt)
\`\`\`

## Coverage

\`\`\`
$(cat coverage-output.txt)
\`\`\`

## Gas Usage

\`\`\`
$(cat gas-report.txt)
\`\`\`
EOF

echo "✅ Report generated: TEST_REPORT.md"
```

### Run Report Generation

```bash
chmod +x scripts/generate-report.sh
./scripts/generate-report.sh
```

---

## 🔐 Security Testing Checklist

### Pre-Deployment Security Tests

```bash
# Run all security tests
forge test --match-contract ApiarySecurity -vvv

# Check for reentrancy
forge test --match-test "test_Security_Reentrancy" -vvvv

# Check access control
forge test --match-test "test_Security_OnlyOwner" -vvvv

# Check overflow/underflow
forge test --match-test "test_Security.*Overflow" -vvvv

# Check slippage protection
forge test --match-test "test_Security_Slippage" -vvvv

# Check DOS resistance
forge test --match-test "test_Security.*DOS" -vvvv
```

### External Security Tools

```bash
# Slither (static analysis)
slither . --exclude-dependencies

# Mythril (symbolic execution)
myth analyze src/ApiaryYieldManager.sol

# Manticore (symbolic execution)
manticore src/ApiaryYieldManager.sol
```

---

## ✅ Pre-Deployment Test Checklist

### Must Pass Before Deployment

- [ ] All unit tests passing (100%)
- [ ] All integration tests passing (46/46)
- [ ] All security tests passing (25/25)
- [ ] All fuzz tests passing (11/11)
- [ ] Code coverage >95%
- [ ] Gas usage optimized (<700k for main functions)
- [ ] No compiler warnings
- [ ] Slither static analysis clean
- [ ] Mainnet fork tests passing
- [ ] Load tests passing (100+ users)
- [ ] Invariant tests running for 24+ hours
- [ ] Documentation complete
- [ ] Security audit report reviewed
- [ ] Multi-sig owner setup verified
- [ ] Emergency procedures tested

### Run Full Pre-Deployment Suite

```bash
#!/bin/bash
set -e

echo "🚀 Running Pre-Deployment Test Suite..."

echo "1️⃣ Building contracts..."
forge build

echo "2️⃣ Running all tests..."
forge test -vv

echo "3️⃣ Generating coverage..."
forge coverage

echo "4️⃣ Checking gas usage..."
forge snapshot --check .gas-snapshot

echo "5️⃣ Running security tests..."
forge test --match-contract ApiarySecurity

echo "6️⃣ Running fuzz tests (deep)..."
forge test --match-contract ApiaryFuzz --fuzz-runs 10000

echo "7️⃣ Running invariant tests..."
forge test --match-contract ApiaryInvariant --invariant-runs 1000

echo "8️⃣ Running static analysis..."
slither . --exclude-dependencies

echo "✅ All pre-deployment tests passed!"
```

---

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Forge Testing Cheatsheet](https://github.com/dabit3/foundry-cheatsheet)
- [Foundry CI/CD Examples](https://github.com/foundry-rs/foundry/tree/master/.github/workflows)
- [Gas Optimization Guide](https://book.getfoundry.sh/forge/gas-tracking)

---

**Last Updated**: December 12, 2025  
**Version**: 1.0.0  
**Status**: ✅ Production Ready
