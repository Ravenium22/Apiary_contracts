# Kodiak Farm Integration Tests

This directory contains integration tests that fork Berachain mainnet to verify our `IKodiakFarm` interface matches the real Kodiak Farm implementation.

## Prerequisites

1. **Foundry** - Make sure you have Foundry installed
2. **RPC Access** - You need access to a Berachain mainnet RPC endpoint

## Quick Start

### 1. Find Active Farms

First, discover active farms on mainnet:

```bash
forge script script/utils/FindActiveFarms.s.sol:FindActiveFarms \
  --fork-url https://rpc.berachain.com -vvv
```

This will:
- Query the KodiakFarmFactory for known farms
- Check common pairs like WBERA/HONEY
- Output farm addresses and their configuration

### 2. Run Fork Tests

Run all fork tests against mainnet:

```bash
forge test --match-contract KodiakFarmFork \
  --fork-url https://rpc.berachain.com -vvv
```

Run a specific test:

```bash
forge test --match-test test_realFarmInterface \
  --fork-url https://rpc.berachain.com -vvv
```

### 3. Using Environment Variables

You can also set the RPC URL via environment:

```bash
export BERACHAIN_RPC="https://rpc.berachain.com"
forge test --match-contract KodiakFarmFork --fork-url $BERACHAIN_RPC -vvv
```

## Test Overview

### KodiakFarmFork.t.sol

| Test | Description |
|------|-------------|
| `test_realFarmInterface` | Verifies all view functions in our `IKodiakFarm` interface work with real farms |
| `test_userViewFunctions` | Tests user-specific view functions |
| `test_stakeAndWithdraw` | Full flow: get LP → stake → wait → withdraw |
| `test_claimRewards` | Stakes, accrues rewards, claims them |
| `test_withdrawLockedAll` | Tests batch withdrawal function |
| `test_printFarmInfo` | Diagnostic: prints detailed farm configuration |

## Mainnet Addresses

| Contract | Address |
|----------|---------|
| KodiakFarmFactory | `0xAeAa563d9110f833FA3fb1FF9a35DFBa11B0c9cF` |
| Kodiak V2 Router | `0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022` |
| Kodiak V2 Factory | `0x5e705e184d233ff2a7cb1553793464a9d0c3028f` |
| HONEY | `0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce` |
| WBERA | `0x6969696969696969696969696969696969696969` |

## Troubleshooting

### "No active farm discovered"

The test tries to automatically find an active farm. If this fails:

1. Run `FindActiveFarms.s.sol` to discover farms
2. Hardcode a known farm address in the test
3. Check if farms have been paused or migrated

### "Could not get LP tokens"

The test needs to add liquidity to get LP tokens. If this fails:

1. Check if the router is accessible
2. Verify token balances
3. Check if the LP pair exists

### RPC Errors

If you get RPC errors:

1. Try a different RPC endpoint
2. Check rate limits
3. Use a local fork with `anvil`:
   ```bash
   anvil --fork-url https://rpc.berachain.com
   # Then in another terminal:
   forge test --match-contract KodiakFarmFork --rpc-url http://localhost:8545 -vvv
   ```

## Updating for New Farms

When a new farm is deployed:

1. Add the farm address to `_getKnownFarms()` in `FindActiveFarms.s.sol`
2. Or hardcode it in `KodiakFarmFork.t.sol` as `testFarm`

## Interface Compatibility

These tests verify our `IKodiakFarm` interface (in `src/interfaces/IKodiakFarm.sol`) is compatible with the real implementation. If a test fails:

1. Check the function signature matches
2. Verify the return types
3. Check for renamed/removed functions
4. Update our interface accordingly

## Gas Reports

To get gas usage on fork:

```bash
forge test --match-contract KodiakFarmFork \
  --fork-url https://rpc.berachain.com \
  --gas-report -vvv
```
