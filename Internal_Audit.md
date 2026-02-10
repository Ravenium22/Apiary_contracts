# Apiary Contracts Security Review

Date: Feb 10, 2026
Repo: https://github.com/Ravenium22/Apiary_contracts
Chain: Berachain
Type: OHM-fork — bonding, rebasing staking (sAPIARY), treasury, yield management

## Executive Summary

Protocol features bonding (iBGT + LP), rebasing sAPIARY, treasury with iBGT yield via Infrared, and multi-phase yield strategies. Codebase shows prior audit fixes (AUDIT-*, H-*, M-* tags throughout). Several residual vulnerabilities identified.

## Critical / High

### 1. Oracle Bootstrap Manipulation (TWAP Oracle)
File: ApiaryUniswapV2TwapOracle.sol:54-77

First price0Average is set from spot reserves, not TWAP. An attacker can manipulate the pool before first update(). Even with MIN_UPDATES_REQUIRED = 6, initial spot price influences early TWAP.

Impact: Bond pricing manipulation at launch.

### 2. Treasury Deposit Value Trust Issue
File: ApiaryTreasury.sol:194-256

deposit() accepts caller-provided value parameter for APIARY minting. maxMintRatioBps (120%) check compares against raw _amount, but iBGT→APIARY decimal conversion (18→9) isn't handled in the ratio check — a compromised depositor could exploit the tolerance.

### 3. YieldManager Lacks Independent Price Validation
File: ApiaryYieldManager.sol:768-799

_swapToApiary() relies on kodiakAdapter.getAmountOut() for slippage. If adapter's price quote is manipulated (flash loan same block), swap proceeds with bad parameters.

## Medium

### 4. Debt Decay vs Unredeemed Mismatch
File: ApiaryBondDepository.sol:736-751

If no deposits for extended period, totalDebt decays to ~0 while totalUnredeemedPayout stays high. Creates disconnect between reported debt ratio and actual obligations. Dynamic discount tiers use totalDebt, so bonds could re-open at maximum discount despite real outstanding obligations.

### 5. Block-Based Daily Issuance Drift
File: ApiaryBondDepository.sol:763-783

Daily issuance cap resets based on blocksPerDay (17,280 blocks = 5s/block). If Berachain block times deviate, actual issuance per 24h period fluctuates. Time-based tracking would be more accurate.

### 6. TWAP Single Point of Failure
Both bond pricing and treasury valuation depend on the same TWAP oracle. If oracle becomes stale or manipulated, both subsystems fail simultaneously.

### 7. LP Calculator Assumes Constant-Product AMM
File: ApiaryBondingCalculator.sol:53-100

Fair LP valuation formula 2 * sqrt(k) only valid for Uniswap V2 constant-product pairs. If Kodiak uses concentrated liquidity, valuation is incorrect.

## Low / Informational

### 8. Missing Event in setMaxMintRatio()
File: ApiaryTreasury.sol:472-474 — No event emitted on parameter change.

### 9. Semantic Error Reuse
File: ApiaryTreasury.sol:511 — APIARY__ZERO_ADDRESS() used for zero staleness check.

### 10. No ETH Recovery in PreSale
File: ApiaryPreSaleBond.sol — No receive() function, accidentally sent ETH is stuck.

### 11. Permit Replay on Fork (Known EIP-2612 Limitation)
File: sApiary.sol:60-73 — Fork protection recalculates DOMAIN_SEPARATOR, but pre-fork permits can replay on original chain.

## Centralization Risks

1. Owner can mint unlimited APIARY via setAllocationLimit() / increaseAllocationLimit()
2. Owner can drain excess tokens from treasury/staking/bonds via clawBack
3. Owner can swap adapters in YieldManager, redirecting yield to malicious contracts
4. Owner can pause all contracts indefinitely
5. Keeper role has privileged yield execution access

## Recommendations

1. Add multi-sig or timelock on owner functions that touch funds or critical params
2. Add Chainlink oracle fallback for TWAP (defense-in-depth)
3. Use time-based daily issuance instead of block-based
4. Add decimal-aware ratio check in treasury deposit validation
5. Add explicit event for setMaxMintRatio()
6. Add sanity bounds on maxMintRatioBps (e.g., min 10000, max 15000)
7. Add view-only TWAP consult to prevent oracle state changes during reads

#- ReentrancyGuard on all critical functions
- Ownable2Step prevents accidental ownership transfers
- SafeERC20 used consistently
- Pausable emergency stops
- Custom errors for gas efficiency
- Many prior audit fixes applied
- Price deviation checks in bond depository
- Ring buffer for rebase history
- Slippage protection on swaps
- Two-step pattern for VaultOwned address changes