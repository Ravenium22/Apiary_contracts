# Apiary Protocol - Mainnet Deployment Checklist

**Date:** 2026-02-08
**Status:** Pre-Mainnet — deployment scripts ready, pending external dependencies

---

## 1. Audit Fix Status

### All Critical/High/Medium/Low Findings — FIXED

All findings from the security audit have been applied to source contracts.
Test suite updated and passing (438 pass, 0 fail).

### Unfixed Informational Findings (Low Priority)

| ID | Description | Impact | Action Needed |
|---|---|---|---|
| INFO-02 | ERC20Permit duplicated in `libs/ERC20Permit.sol` and `sApiary.sol` | Maintenance risk if one copy diverges | Low priority - cosmetic |
| ~~INFO-03~~ | ~~Public `DOMAIN_SEPARATOR` variable stale after chain fork~~ | **FIXED** — replaced storage var with dynamic getter delegating to `_domainSeparator()` in both ERC20Permit.sol and sApiary.sol | No action needed |
| INFO-04 | `valueOf()` / `bondPriceInHoney()` naming doesn't indicate state change | Misleading to developers | Largely mitigated — `valueOf()` is now internal, `bondPriceInHoney()` is onlyOwner |

### Gas Optimizations — ALL APPLIED

| Optimization | Location | Status |
|---|---|---|
| Cache `userBonds[msg.sender]` storage pointer in `deposit()` | BondDepository.sol | DONE |
| Use `unchecked` for loop increments in `redeemAll()`, `pendingPayoutFor()`, `getActiveBonds()` | BondDepository.sol | DONE |
| Pack Bond struct (uint128 payout/pricePaid, uint48 timestamps) | BondDepository.sol | DONE — saves 1 SSTORE (~2100 gas) |
| Cache `splitConfig` as memory in `_executePhase1Strategy()` | YieldManager.sol | DONE |

### Partially Fixed

| ID | Description | What Was Done | What Remains |
|---|---|---|---|
| LOW-03 | Custom ERC20 missing safety features | Removed unused SafeMath import | Full migration to OZ ERC20 deferred — sApiary overrides ERC20 heavily with gons-based accounting, making a base class swap risky |

---

## 2. Deployment Script Tasks

### Completed

| ID | Task | Status |
|---|---|---|
| B-2 | Run full test suite, fix regressions from audit fixes | DONE — 14 test failures fixed (test-side), 412 pass |
| B-3 | Remove hardcoded Bepolia addresses from DeployAll.s.sol | DONE — all 5 addresses + epoch + merkle root read from env vars |
| B-4 | Fix YieldManager placeholder adapters (address(1)/address(2)) | DONE — setInfraredAdapter/setKodiakAdapter wired in DeployAll + 06_DeployYieldManager |
| B-5 | Add `initializeBondTerms()` for ibgtBond and lpBond | DONE — Step 12 in DeployAll, env-driven with bounds checks |
| B-6 | Add `preSaleBond.setApiaryToken(apiary)` | DONE — Step 13 in DeployAll |
| B-7 | Add `apiary.setAllocationLimit()` for treasury/presale/bonds | DONE — Step 10 in DeployAll, env-driven defaults |
| B-8 | Fix VerifyDeployment.s.sol self-contradicting checks | DONE — replaced with consistent post-deploy checks |
| H-1 | Treasury config: setReserveToken, setLiquidityToken, setMaxMintRatio, setMaxMintPerDeposit | DONE — Step 11 in DeployAll + depositor roles fixed (LP Bond → liquidityDepositor) |
| H-2 | Ownership transfer to multisig via Ownable2Step | DONE — Step 16 in DeployAll, transfers 9 contracts + grants APIARY admin role |
| H-3 | YieldManager.setupApprovals() after adapters wired | DONE — Step 15 in DeployAll |
| H-6 | Fix .env.example mismatch (BEPOLIA_RPC → BEPOLIA_RPC_URL) | DONE — .env.example fully rewritten with all env vars |
| M-1 | sApiary.setIndex, yieldManager.setStakingContract | DONE — Step 14 in DeployAll |

### DeployAll.s.sol — Full Step Summary

| Step | Action | Env Vars Used |
|---|---|---|
| 1 | Deploy APIARY Token | — |
| 2 | Deploy sAPIARY Token | — |
| 3 | Set LP address (from env or placeholder) | `LP_PAIR_ADDRESS` |
| 4 | Deploy Treasury | `IBGT_ADDRESS`, `HONEY_ADDRESS` |
| 5 | Deploy Staking | `EPOCH_LENGTH`, `FIRST_EPOCH_NUMBER` |
| 6 | Initialize sAPIARY with Staking | — |
| 7 | Deploy TWAP Oracle (if LP exists) | — |
| 8 | Deploy Bond Contracts + PreSale | `MERKLE_ROOT` |
| 9 | Deploy YieldManager + Adapters, wire adapters | `INFRARED_STAKING`, `KODIAK_ROUTER`, `KODIAK_FACTORY` |
| 10 | APIARY minting allocations (B-7) | `ALLOC_TREASURY`, `ALLOC_PRESALE`, `ALLOC_IBGT_BOND`, `ALLOC_LP_BOND` |
| 11 | Treasury configuration (H-1) | `MAX_MINT_RATIO_BPS`, `MAX_MINT_PER_DEPOSIT` |
| 12 | Initialize bond terms (B-5) | `BOND_VESTING_TERM`, `BOND_MAX_PAYOUT`, `BOND_DISCOUNT_RATE`, `BOND_MAX_DEBT` |
| 13 | Set APIARY on PreSale (B-6) | — |
| 14 | sApiary index + YM staking (M-1) | `SAPIARY_INITIAL_INDEX` |
| 15 | YM approvals (H-3) | — |
| 16 | Ownership transfer (H-2) | `MULTISIG_ADDRESS` |

---

## 3. Previously Missing Implementations — NOW COMPLETE

### ApiaryBondingCalculator — IMPLEMENTED

- **File:** `src/ApiaryBondingCalculator.sol`
- **Uses:** Fair LP valuation formula: `2 * sqrt(reserveA * reserveB) * (amount / totalSupply)`
- **Deployed for:** LP bond pricing in `ApiaryBondDepository.sol` and `ApiaryTreasury.sol`
- **Tests:** 13 tests in `test/ApiaryBondingCalculator.t.sol`

### IInfrared — REWRITTEN TO REAL INTERFACE

- **File:** `src/interfaces/IInfrared.sol`
- **Status:** Rewritten to match real InfraredVault MultiRewards interface on Berachain mainnet
- **Features:** Multi-token rewards via `getReward()`, stake/withdraw, `rewardTokens()` enumeration
- **Adapter:** `ApiaryInfraredAdapter.sol` updated for multi-token reward claiming

### iBGT/USD Oracle — ADDED

- **Requirement:** iBGT bonds now require a Chainlink-compatible iBGT/USD price feed (`IAggregatorV3`)
- **Impact:** `valueOf()` and Treasury `getMarketCapAndTreasuryValue()` use oracle instead of 1:1 assumption
- **Config:** `IBGT_PRICE_FEED` env var required for deployment
- **Safety:** Staleness check (BondDepository: 1h default, Treasury: 24h default), reverts on stale/invalid

---

## 4. Pre-Deployment Checklist

### Code

- [x] Run full test suite — 438 tests pass, 0 failures
- [x] Fix all test regressions from audit changes
- [x] Deployment scripts produce ready-to-operate state
- [x] VerifyDeployment.s.sol consistent and comprehensive
- [x] Implement `ApiaryBondingCalculator` for LP bond pricing
- [x] Rewrite `IInfrared` to real InfraredVault MultiRewards interface
- [x] Add iBGT/USD oracle integration (BondDepository + Treasury)
- [x] Apply all gas optimizations from audit
- [ ] Commit all changes
- [ ] Run `forge test --gas-report` — verify gas within bounds
- [ ] Run `forge coverage --report summary --skip script` — critical paths >90%

### Configuration

- [x] All external addresses read from env vars (no hardcoded testnet addresses)
- [x] Bond terms configurable via env with bounds checks
- [x] Treasury safety limits configurable (maxMintRatio, maxMintPerDeposit)
- [x] Mainnet safety: rejects placeholder merkle root + requires multisig on chain 80094
- [ ] Obtain `IBGT_PRICE_FEED` address (Chainlink-compatible iBGT/USD oracle)
- [ ] Obtain Berachain mainnet addresses for iBGT, HONEY, Infrared, Kodiak Router, Kodiak Factory
- [ ] Generate production merkle root from final whitelist
- [ ] Determine production epoch length for mainnet
- [ ] Determine production bond terms (vesting, payout, discount, debt)
- [ ] Prepare `.env` file with mainnet RPC, deployer key, Berascan API key

### Security

- [ ] Verify deployer wallet is a multisig or secure key management
- [ ] Confirm multisig address for `MULTISIG_ADDRESS` env var
- [ ] After deployment: multisig calls `acceptOwnership()` on all 9 contracts
- [ ] After deployment: deployer renounces `DEFAULT_ADMIN_ROLE` on APIARY token
- [ ] Set keeper address for YieldManager (separate from owner for operational security)
- [ ] Review all `onlyOwner` functions and ensure admin key security

---

## 5. Post-Deployment Steps

### Immediate (Handled by DeployAll.s.sol)

These are now automated in the deployment script:

- [x] ~~sApiary.initialize(stakingAddress)~~ — Step 6
- [x] ~~sApiary.setIndex(initialIndex)~~ — Step 14
- [x] ~~Treasury: setReserveToken, setLiquidityToken, depositors, maxMintRatio, maxMintPerDeposit~~ — Step 11
- [x] ~~APIARY: setAllocationLimit for treasury, presale, bonds~~ — Step 10
- [x] ~~BondDepository: initializeBondTerms~~ — Step 12
- [x] ~~PreSaleBond: setApiaryToken~~ — Step 13
- [x] ~~YieldManager: setStakingContract, setupApprovals~~ — Steps 14-15
- [x] ~~Ownership transfer to multisig~~ — Step 16

### Manual Steps After Deployment

1. **Create APIARY/HONEY LP pool** on Kodiak DEX
2. **Deploy TWAP Oracle** with the LP pair address (or re-run DeployAll with `LP_PAIR_ADDRESS` set)
3. **Register Kodiak farm:** run `08_ConfigureKodiakFarm.s.sol` after farm is created
4. **Multisig accepts ownership** on all transferred contracts
5. **Deployer renounces** APIARY `DEFAULT_ADMIN_ROLE`
6. **Set YieldManager keeper** if different from owner

### Pre-Sale Launch

1. Set real merkle root: `preSaleBond.setMerkleRoot(root)` (or deploy with correct `MERKLE_ROOT` env var)
2. Start pre-sale: `preSaleBond.startPreSaleBond()`
3. After pre-sale ends: `preSaleBond.endPreSaleBond()`
4. Mint allocated tokens: `preSaleBond.mintApiary()`
5. Start TGE: `preSaleBond.setTgeStartTime()`

### Bond Launch

1. Ensure TWAP oracle has completed 3+ updates (MIN_UPDATES_REQUIRED = 3, ~3+ hours)
2. Fund treasury with initial reserves
3. Unpause bond depository (if paused)

---

## 6. Monitoring & Operations

### Key Parameters to Monitor

| Parameter | Contract | What to Watch |
|---|---|---|
| `totalDebt` / `maxDebt` | BondDepository | Debt ratio approaching limits |
| `epoch.distribute` | Staking | Non-zero means yield is flowing |
| `totalStaked` | Staking | Track staking participation |
| `currentMode` | YieldManager | Protocol mode transitions (NORMAL/GROWTH/BUYBACK) |
| `updateCount` | TwapOracle | Ensure oracle stays updated |
| `totalBondsSold` | PreSaleBond | Pre-sale progress |

### Keeper Operations

- `YieldManager.executeYield()` — must be called by keeper/owner, min 1 hour intervals
- `ApiaryStaking.rebase()` — restricted to owner/distributor after HIGH-04 fix
- TWAP oracle updates happen automatically via `consult()` in bond deposits

### Emergency Functions

| Function | Contract | Purpose |
|---|---|---|
| `pause()` | All contracts | Emergency stop |
| `setEmergencyMode(true)` | YieldManager | Forward yield directly to treasury |
| `revokeApprovals()` | YieldManager | Revoke all adapter token approvals |
| `retrieve()` | Staking | Recover accidentally sent tokens (not APIARY/sAPIARY) |
| `clawBack()` | BondDepository, PreSaleBond | Emergency token recovery |

---

## 7. Test Results Required Before Mainnet

- [x] `forge test` — 438 tests pass, 0 fail, 5 skipped
- [x] `forge test --gas-report` — gas within acceptable bounds (see below)
- [x] `forge build --sizes` — all contracts within 24KB EIP-170 limit
- [x] `forge script DeployAll.s.sol --chain-id 80094` — dry-run passes through all 16 steps
- [ ] `forge coverage` — critical paths have >90% coverage
- [ ] Fork test against Berachain mainnet RPC (verify real Kodiak/Infrared integration)
- [ ] Manual test on Bepolia with full deployment flow
- [ ] Verify contract verification works on Berascan

### Gas Report — Key Functions (BondDepository)

| Function | Min | Avg | Median | Max |
|---|---|---|---|---|
| deposit | 25,111 | 324,833 | 330,010 | 330,046 |
| redeem | 24,755 | 54,736 | 68,818 | 71,307 |
| redeemAll | 84,594 | 84,594 | 84,594 | 84,594 |
| getActiveBonds | 16,729 | 16,729 | 16,729 | 16,729 |
| pendingPayoutFor | 8,478 | 8,478 | 8,478 | 8,478 |
| quoteValue | 23,317 | 23,317 | 23,317 | 23,317 |

### Contract Sizes

| Contract | Runtime (B) | Margin (B) |
|---|---|---|
| ApiaryBondDepository | 12,389 | 12,187 |
| ApiaryTreasury | 7,405 | 17,171 |
| ApiaryYieldManager | 16,592 | 7,984 |
| ApiaryStaking | 5,067 | 19,509 |
| ApiaryToken | 6,800 | 17,776 |
| sApiary | 7,334 | ~17,242 |
| ApiaryKodiakAdapter | 16,767 | 7,809 |
| ApiaryInfraredAdapter | 7,569 | 17,007 |
| ApiaryBondingCalculator | 1,553 | 23,023 |
| ApiaryPreSaleBond | 6,517 | 18,059 |
| ApiaryUniswapV2TwapOracle | 2,464 | 22,112 |

All contracts comfortably within the 24,576 byte EIP-170 limit.

---

## 8. Risk Summary

| Risk | Severity | Mitigation |
|---|---|---|
| ~~IInfrared interface mismatch~~ | ~~High~~ | **RESOLVED** — IInfrared rewritten to real InfraredVault MultiRewards interface |
| ~~No BondingCalculator implementation~~ | ~~Medium~~ | **RESOLVED** — `ApiaryBondingCalculator.sol` implemented with fair LP valuation |
| iBGT/USD oracle dependency | Medium | Treasury and BondDepository revert if price feed is missing/stale; `IBGT_PRICE_FEED` required at deploy |
| TWAP oracle bootstrap manipulation | Low | Fixed: requires 3 updates (~3 hours) before usable |
| Uncommitted audit fixes | High | Commit, test, and verify all changes before deploy |
| Admin key compromise | High | Transfer to multisig automated in Step 16 |
