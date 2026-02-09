# Apiary Protocol - Implementation TODO

## 1. Replace iBGT Bond Pricing with Mandatory iBGT/USD Oracle

**Problem:** `valueOf()` (line 862) and `quoteValue()` (line 978) assume 1 iBGT = 1 HONEY
by doing a bare decimal conversion (`amount * 1e9 / 1e18`). This is incorrect — iBGT
is pegged to BGT, not HONEY. HONEY is the $1 stablecoin.

**Current (wrong):**
```solidity
// valueOf(), line 860-866
value_ = _amount.mulDiv(
    10 ** IERC20Metadata(APIARY).decimals(),   // 1e9
    10 ** IERC20Metadata(_token).decimals()     // 1e18
);
// Implicitly: 1 iBGT = 1 HONEY = $1
```

**Required changes:**

### 1a. Add iBGT/USD price feed to BondDepository (iBGT bonds only)
- Add `AggregatorV3Interface public ibgtPriceFeed` state variable
- Add `ibgtPriceFeed` as a constructor parameter (required for iBGT bonds, zero for LP bonds)
- Add `setIbgtPriceFeed(address)` owner setter with zero-address check
- Add staleness check (e.g. revert if price is older than a configurable threshold)
- Add `error APIARY__STALE_PRICE_FEED()` and `error APIARY__INVALID_IBGT_PRICE()`

### 1b. Fix `valueOf()` iBGT pricing (line 856-866)
- Query `ibgtPriceFeed.latestRoundData()` to get iBGT price in USD
- Since HONEY = $1 USD, iBGT/USD price = iBGT value in HONEY terms
- New formula: `value_ = _amount * ibgtPrice / 10^(ibgtFeedDecimals) * 10^9 / 10^18`
- Normalize for feed decimals (likely 8-decimal Chainlink format)

### 1c. Fix `quoteValue()` iBGT pricing (line 975-982)
- Same oracle-based calculation as valueOf, but using cached/view-safe price
- Store `lastCachedIbgtPrice` alongside `lastCachedApiaryPrice` (updated in valueOf)
- quoteValue uses the cached iBGT price for gas-free UI quotes

### 1d. Fix Treasury `getMarketCapAndTreasuryValue()` (line 540-543)
- Replace `ibgtValue = ibgtBalance` (1:1 assumption) with oracle lookup
- Treasury needs its own `ibgtPriceFeed` reference or a view helper
- Convert iBGT balance to HONEY value using the oracle price

### 1e. Update deployment scripts
- `DeployAll.s.sol`: pass `ibgtPriceFeed` address to iBGT BondDepository constructor
- Add `IBGT_PRICE_FEED` env var to `.env.example`
- `VerifyDeployment.s.sol`: verify price feed is set and returning valid data

### 1f. Update tests
- Add mock Chainlink aggregator to test harness
- Update all iBGT bond pricing tests to account for oracle price
- Add test: deposit reverts if price feed is stale
- Add test: deposit reverts if price feed returns zero/negative
- Add test: payout scales correctly with iBGT price (e.g. iBGT at $3 gives 3x payout vs $1)
- Update quoteValue tests for oracle-based pricing

---

## 2. Update Default Vesting Term to 7 Days

**Current:** `DEFAULT_VESTING_TERM = 86_400` (5 days at 5s blocks)
**Required:** 7 days = 7 * 24 * 60 * 60 / 5 = **120,960 blocks**

### 2a. Update constant in BondDepository
- Change `DEFAULT_VESTING_TERM` from `86_400` to `120_960`
- Update comment from "5 days" to "7 days"

### 2b. Update NatSpec on Terms struct
- Line 49: change `(5 days default)` to `(7 days default)`

### 2c. Update deployment script default
- `DeployAll.s.sol`: update the default/fallback value for `BOND_VESTING_TERM` env var

### 2d. Update tests
- Update any hardcoded `86_400` vesting term values in test files to `120_960`
- Verify vesting math tests still pass with new term

---

## 3. Apply Remaining Audit Safety Fixes

### 3a. INFO-03: Remove stale public DOMAIN_SEPARATOR variable
- In `libs/ERC20Permit.sol`: remove or override the public `DOMAIN_SEPARATOR` storage var
  so external callers always get the live computed value from `_domainSeparator()`
- In `sApiary.sol`: same treatment if applicable
- **Note:** Internal `_domainSeparator()` already handles fork detection correctly

### 3b. Remaining gas optimizations (from audit)
- Cache `userBonds[msg.sender]` storage pointer in `deposit()` (already partially done at line 340)
- Use `unchecked` for loop increment in `redeemAll()` and `pendingPayoutFor()`
- Cache `splitConfig` as memory in YieldManager `_executePhase1Strategy()`

### 3c. LOW-03: Custom ERC20 safety (deferred — document rationale)
- Full migration to OZ ERC20 is deferred (sApiary overrides ERC20 heavily with gons)
- No code change — confirm this is intentional and document in MAINNET_CHECKLIST

---

## 4. Explicitly Out of Scope

### 4a. Daily issuance cap (3% rolling)
- **Decision:** Not implemented on-chain
- Controlled via `maxDebt` and `maxPayout` parameters
- Higher-level limits managed off-chain
- No code changes needed

### 4b. BCV auto-adjustment
- **Decision:** Not implemented on-chain
- BCV (discount rate) managed manually via `setBondTerms(PARAMETER.DISCOUNT_RATE, value)`
- Called by multisig or keeper as needed
- No code changes needed

---

## 5. Verify Tests and Deployment

### 5a. Run full test suite
- `forge test` — all tests must pass with zero failures
- Pay special attention to bond pricing tests with new oracle integration

### 5b. Run gas report
- `forge test --gas-report` — verify gas within acceptable bounds
- Confirm gas optimizations from section 3b show improvement

### 5c. Update MAINNET_CHECKLIST.md
- Mark INFO-03 as fixed
- Mark gas optimizations as fixed
- Update test count
- Add iBGT oracle requirement to pre-deployment checklist
- Add `IBGT_PRICE_FEED` to configuration section

### 5d. Verify deployment scripts
- Dry-run `DeployAll.s.sol` compiles with updated constructor args
- Verify `VerifyDeployment.s.sol` checks for valid iBGT price feed
