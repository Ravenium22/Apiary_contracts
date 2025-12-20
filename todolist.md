# Apiary Protocol - Full Codebase Review TODO List

Generated: December 12, 2025
Reviewer: AI Assistant (GitHub Copilot - Claude Opus 4.5)
Status: Pending Human Review

---

## Summary

| Contract | Critical | Medium | Low | Questions |
|----------|----------|--------|-----|-----------|
| ApiaryToken.sol | 1 | 3 | 3 | 2 |
| sApiary.sol | 2 | 3 | 3 | 2 |
| ApiaryStaking.sol | 2 | 4 | 3 | 3 |
| ApiaryTreasury.sol | 1 | 3 | 2 | 2 |
| ApiaryBondDepository.sol | 2 | 4 | 3 | 4 |
| ApiaryPreSaleBond.sol | 1 | 3 | 3 | 3 |
| ApiaryYieldManager.sol | 3 | 5 | 3 | 4 |
| ApiaryInfraredAdapter.sol | 1 | 3 | 2 | 2 |
| ApiaryKodiakAdapter.sol | 1 | 3 | 2 | 2 |
| Cross-Contract | 2 | 3 | - | 3 |
| **TOTAL** | **16** | **34** | **24** | **27** |

---

## ApiaryToken.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[AT-C01]** Missing BURNER_ROLE usage - role defined but never granted or checked
  - Location: `BURNER_ROLE` constant at line 33
  - Description: The `BURNER_ROLE` is defined but never used anywhere. The `burn()` and `burnFrom()` functions are public and don't check for any role. This means anyone can burn their own tokens, and anyone with allowance can burn from another account.
  - Risk: If the design intended to restrict burning to certain contracts (e.g., yield manager for buyback-and-burn), this is missing. However, if public burning is intended, this is just dead code.
  - Recommendation: Either:
    A) Remove BURNER_ROLE if public burning is intended
    B) Add `onlyRole(BURNER_ROLE)` to burn functions if restricted burning is intended

### 🟡 Medium Issues (Should Fix)

- [ ] **[AT-M01]** Allocation limit can never be increased - only set once
  - Location: `setAllocationLimit()` function, line 87-97
  - Description: The check `if (allocationLimits[minter] != 0)` prevents any modification once set. If the allocation is exhausted or set incorrectly, it cannot be changed.
  - Risk: Admin cannot fix mistakes or add additional allocation to minters.
  - Recommendation: Either remove the check to allow updates, or add a separate function to increase allocation with appropriate safeguards.

- [ ] **[AT-M02]** No mechanism to revoke MINTER_ROLE after allocation is exhausted
  - Location: `setAllocationLimit()` function, line 87-97
  - Description: Once granted, `MINTER_ROLE` cannot be revoked through this contract's logic even when allocation reaches 0. The minter would still have the role but no tokens to mint.
  - Risk: Stale permissions, confusing access control state.
  - Recommendation: Add a function to revoke minter role when allocation is 0, or auto-revoke when allocation hits 0.

- [ ] **[AT-M03]** `totalMintedSupply` can become inconsistent if tokens are burned
  - Location: `totalMintedSupply` variable and `mint()` function
  - Description: `totalMintedSupply` only tracks mints, not burns. If tokens are burned, `totalMintedSupply` stays the same but actual circulating supply is lower. This prevents minting even if tokens were burned.
  - Risk: Cannot mint to replace burned tokens even if below 200k cap.
  - Recommendation: Clarify intent - if burn should NOT allow re-minting, document this. If it should, add burn accounting.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[AT-L01]** `BPS` constant defined but unused
  - Description: Line 36 defines `BPS = 10_000` but it's never used in this contract.
  - Recommendation: Remove unused constant.

- [ ] **[AT-L02]** `lastTimeStaked` mapping not used effectively
  - Description: The `lastTimeStaked` mapping is updated but never queried in this contract. Its purpose is unclear.
  - Recommendation: Document the purpose (anti-sybil? cooldown?) or remove if not needed.

- [ ] **[AT-L03]** Missing event for `burn` and `burnFrom`
  - Description: While `Transfer` to address(0) is emitted via `_burn`, there's no explicit Burn event for better indexing.
  - Recommendation: Consider adding a `Burn` event for better tracking.

### 🔵 Code Quality / Cleanup

- [ ] **[AT-Q01]** Consider using OpenZeppelin's ERC20 instead of custom ERC20 library
- [ ] **[AT-Q02]** `Math` import is unused - remove it
- [ ] **[AT-Q03]** Add natspec for `MINTER_ROLE` and `BURNER_ROLE` constants

### ❓ Questions Needing Answers

- [ ] **[AT-?01]** Is public burning intentional, or should it be restricted to BURNER_ROLE?
  - Context: Currently anyone can burn their own tokens. The yield manager burns APIARY as part of the strategy.
  - Options: 
    A) Public burning is fine (Olympus-style)
    B) Only BURNER_ROLE should burn (yield manager, treasury)
  - **ANSWER:** [pending]

- [ ] **[AT-?02]** Should burned tokens allow re-minting up to the 200k cap?
  - Context: `totalMintedSupply` never decreases. Burned tokens cannot be replaced.
  - Options:
    A) Burned tokens are gone forever (deflationary)
    B) Burned tokens should allow new minting
  - **ANSWER:** [pending]

### ✅ Verified Correct

- Transfer function correctly handles zero address checks
- Proper use of unchecked block for balance arithmetic (safe after require)
- AccessControl properly inherited and DEFAULT_ADMIN_ROLE granted

---

## sApiary.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[SA-C01]** Division by zero possible in rebase if `_totalSupply` becomes 0
  - Location: `rebase()` function, line 253: `_gonsPerFragment = TOTAL_GONS.div(_totalSupply)`
  - Description: If through some extreme edge case `_totalSupply` becomes 0, this will cause a division by zero. While unlikely, it's not explicitly prevented.
  - Risk: Contract becomes unusable if this state is reached.
  - Recommendation: Add check: `require(_totalSupply > 0, "sApiary: total supply is zero")`

- [ ] **[SA-C02]** Two-step ownership not implemented - single-step transfer with instant effect
  - Location: `Ownable` contract, lines 84-108
  - Description: Uses custom `Ownable` with `pushManagement/pullManagement` pattern, but this is incompatible with the rest of the protocol which uses OZ's `Ownable2Step`.
  - Risk: Inconsistent ownership patterns across contracts. The push/pull is safer but implementation differs from other contracts.
  - Recommendation: Standardize on OZ's Ownable2Step across all contracts.

### 🟡 Medium Issues (Should Fix)

- [ ] **[SA-M01]** `initializer` address can permanently block initialization if compromised
  - Location: `initialize()` function, lines 211-225
  - Description: If the deployer (initializer) address is compromised or loses access before calling `initialize()`, the contract is stuck.
  - Risk: Permanent contract failure if initialization doesn't happen immediately after deployment.
  - Recommendation: Add a time-based fallback or use OZ's Initializable with re-init protection.

- [ ] **[SA-M02]** Precision loss in gons-to-balance conversions
  - Location: `balanceOf()`, `balanceForGons()`, `gonsForBalance()` functions
  - Description: Repeated conversions between gons and balance can accumulate precision loss over many rebases.
  - Risk: Small balance discrepancies over time (dust amounts).
  - Recommendation: Acceptable for OHM-style rebasing, but document expected precision loss.

- [ ] **[SA-M03]** `setIndex` can only be called once, no recovery if set incorrectly
  - Location: `setIndex()` function, lines 230-234
  - Description: Once INDEX is set (even to wrong value), it cannot be changed.
  - Risk: Incorrect initial index would require contract redeployment.
  - Recommendation: Add a time window for correction or require confirmation.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[SA-L01]** `DOMAIN_SEPARATOR` is not immutable - could be manipulated
  - Location: `ERC20Permit` contract in sApiary.sol, lines 32-45
  - Description: DOMAIN_SEPARATOR is set in constructor but stored as regular storage. On a chain fork, the chainId would be wrong.
  - Risk: Permit signatures valid on one chain could be replayed on a fork.
  - Recommendation: Use EIP-712 pattern that recalculates DOMAIN_SEPARATOR if chainId changes.

- [ ] **[SA-L02]** Duplicate `Ownable` and `ERC20Permit` implementations
  - Description: Both are defined inline in sApiary.sol instead of importing shared versions.
  - Recommendation: Use shared imports for consistency and gas savings.

- [ ] **[SA-L03]** `INITIAL_FRAGMENTS_SUPPLY` (5M) doesn't match token's max supply (200k)
  - Location: Line 143: `INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10 ** 9`
  - Description: Initial supply is 5M tokens but APIARY max is 200k. This is fine for rebasing math but confusing.
  - Recommendation: Add comment explaining this is for rebasing headroom, not actual supply.

### 🔵 Code Quality / Cleanup

- [ ] **[SA-Q01]** Use SafeMath consistently or remove it entirely (Solidity 0.8+ has built-in overflow checks)
- [ ] **[SA-Q02]** Add events for `setIndex()` call
- [ ] **[SA-Q03]** Consider merging duplicate code with OpenZeppelin contracts

### ❓ Questions Needing Answers

- [ ] **[SA-?01]** What is the intended initial INDEX value?
  - Context: `setIndex` is called once to set the starting index for staking rewards calculation.
  - Options: Typically 1e9 for 9-decimal tokens (OHM uses 1e9)
  - **ANSWER:** [pending]

- [ ] **[SA-?02]** Is the 5M initial fragment supply intentional?
  - Context: This allows significant rebasing headroom but creates mismatch with APIARY's 200k cap.
  - Options:
    A) Yes, intentional for rebasing math
    B) Should match APIARY supply
  - **ANSWER:** [pending]

### ✅ Verified Correct

- Gons-based accounting correctly implements OHM-style rebasing
- Proper tracking of rebases with history
- Correct separation of staking contract for rebase authority

---

## ApiaryStaking.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[AS-C01]** Warmup contract can steal all staked tokens
  - Location: `stake()`, `claim()`, `forfeit()` functions
  - Description: The warmup contract receives all sAPIARY during staking. If `warmupContract` is set to a malicious address, all user stakes are lost.
  - Risk: Total loss of user funds if warmup contract is compromised or malicious.
  - Recommendation: 
    1. Add immutability after initial set (done via `APIARY__WARMUP_ALREADY_SET`)
    2. Add timelock for warmup contract changes
    3. Verify warmup contract implements `IWarmup` correctly before setting

- [ ] **[AS-C02]** `forfeit()` returns APIARY but sAPIARY balance may have changed
  - Location: `forfeit()` function, lines 246-256
  - Description: When user forfeits, they get back `info.deposit` (original APIARY), but the sAPIARY in warmup may have rebased to a different value. The difference between `balanceForGons(info.gons)` and `info.deposit` is left in the staking contract.
  - Risk: If sAPIARY value increased during warmup, user loses the gains. If it decreased (unlikely in Phase 1), staking contract may not have enough APIARY.
  - Recommendation: Either return sAPIARY value or ensure accounting is correct.

### 🟡 Medium Issues (Should Fix)

- [ ] **[AS-M01]** `unstake()` does 1:1 sAPIARY→APIARY but this breaks after rebases
  - Location: `unstake()` function, lines 264-278
  - Description: User sends `_amount` sAPIARY and receives `_amount` APIARY. After rebases, 1 sAPIARY > 1 APIARY, but this function returns equal amounts.
  - Risk: Users lose value when unstaking after rebases (they should get more APIARY than sAPIARY burned).
  - Recommendation: Verify this is the intended OHM behavior or add conversion using index.

- [ ] **[AS-M02]** Missing sAPIARY balance check in `unstake()`
  - Location: `unstake()` function
  - Description: `safeTransferFrom` will revert if user doesn't have enough sAPIARY, but there's no explicit check or helpful error message.
  - Risk: Poor UX - generic ERC20 error instead of helpful message.
  - Recommendation: Add balance check with custom error.

- [ ] **[AS-M03]** `rebase()` is public and can be called multiple times
  - Location: `rebase()` function, lines 290-318
  - Description: Anyone can call `rebase()`. While it only advances epoch if `endBlock <= block.number`, repeated calls within a block waste gas.
  - Risk: Gas griefing, minor.
  - Recommendation: This is intentional for OHM pattern, but consider rate limiting.

- [ ] **[AS-M04]** `retrieve()` emergency function can pull any token including APIARY
  - Location: `retrieve()` function, lines 473-479
  - Description: Manager can pull APIARY tokens from the staking contract, which would break unstaking for users.
  - Risk: If manager is compromised, user funds could be stolen.
  - Recommendation: Add exclusion for APIARY and sAPIARY tokens, or add timelock.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[AS-L01]** `totalStaked` can become inaccurate
  - Description: `totalStaked` is updated in stake/unstake but not in forfeit. Also doesn't account for rebases.
  - Recommendation: Consider removing or making it purely informational.

- [ ] **[AS-L02]** No event for `toggleDepositLock()`
  - Description: Lock state changes are not logged.
  - Recommendation: Add `DepositLockToggled(address user, bool locked)` event.

- [ ] **[AS-L03]** Uses custom `Ownable` instead of OZ's `Ownable2Step`
  - Description: Inconsistent with Treasury/Bond/YieldManager which use Ownable2Step.
  - Recommendation: Standardize on Ownable2Step.

### 🔵 Code Quality / Cleanup

- [ ] **[AS-Q01]** Duplicate `Ownable` implementation (same issue as sApiary)
- [ ] **[AS-Q02]** SafeMath usage unnecessary in Solidity 0.8.26
- [ ] **[AS-Q03]** Consider making `epoch` struct elements individual public variables for gas savings on reads

### ❓ Questions Needing Answers

- [ ] **[AS-?01]** Is 1:1 sAPIARY→APIARY unstaking intentional even after rebases?
  - Context: OHM's staking returns different amounts based on index. Current implementation may be incorrect.
  - Options:
    A) Yes, intentional (different from OHM)
    B) Should use index to calculate APIARY return
  - **ANSWER:** [pending]

- [ ] **[AS-?02]** Should `forfeit()` return APIARY or sAPIARY value?
  - Context: Currently returns original deposit, user may lose rebase gains.
  - Options:
    A) Return original deposit (current behavior)
    B) Return sAPIARY value converted to APIARY
  - **ANSWER:** [pending]

- [ ] **[AS-?03]** What is the intended warmup period?
  - Context: `warmupPeriod` is settable but no default is documented.
  - Options: 0 epochs (instant claim), 1-3 epochs typical
  - **ANSWER:** [pending]

### ✅ Verified Correct

- ReentrancyGuard properly applied
- Pausable correctly implemented
- Epoch tracking logic matches OHM pattern

---

## ApiaryTreasury.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[TR-C01]** `deposit()` trusts caller-provided `value` parameter for minting
  - Location: `deposit()` function, lines 137-172
  - Description: The caller (bond depository) specifies how much APIARY to mint via the `value` parameter. The treasury doesn't verify this matches the actual deposit value. A malicious depositor could request unlimited minting.
  - Risk: Reserve depositor could mint unlimited APIARY if compromised.
  - Recommendation: Add valuation logic in treasury to verify `value` is correct for `_amount` of `_token`, or document that bond contracts are trusted.

### 🟡 Medium Issues (Should Fix)

- [ ] **[TR-M01]** iBGT accounting can become inconsistent with actual balance
  - Location: `_ibgtAccounting` struct
  - Description: If iBGT is transferred directly to treasury (not through deposit), accounting is off. Similarly, if yield manager doesn't return exact amounts.
  - Risk: Accounting says more/less iBGT than actually held.
  - Recommendation: Add `syncIBGTAccounting()` function that reconciles with actual balance.

- [ ] **[TR-M02]** No mechanism to remove reserve/liquidity token approval
  - Location: Constructor sets iBGT and APIARY_HONEY_LP as approved
  - Description: Once set in constructor, these cannot be changed to false except via `setReserveToken`/`setLiquidityToken`.
  - Risk: If a token becomes compromised, it cannot be de-authorized quickly.
  - Recommendation: Current implementation allows this via setter functions - verified acceptable.

- [ ] **[TR-M03]** Missing `getMarketCapAndTreasuryValue()` function referenced by YieldManager
  - Location: YieldManager calls this function but it doesn't exist in Treasury
  - Description: Phase 2 strategy depends on `_getMarketCapAndTV()` which calls `getMarketCapAndTreasuryValue()` on treasury. This function doesn't exist.
  - Risk: Phase 2 strategy will fail.
  - Recommendation: Implement this function in Treasury or YieldManager.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[TR-L01]** No view function for total reserves across all tokens
  - Description: Can only query reserves per token, not total value.
  - Recommendation: Add aggregate view function.

- [ ] **[TR-L02]** HONEY balance tracked but not as reserve token
  - Description: `getHONEYBalance()` exists but HONEY isn't marked as reserve/liquidity token.
  - Recommendation: Document whether HONEY should be a reserve token.

### 🔵 Code Quality / Cleanup

- [ ] **[TR-Q01]** Add natspec for IBGTAccounting struct
- [ ] **[TR-Q02]** Consider using a struct for return value of getIBGTBalance/getHONEYBalance/getLPBalance

### ❓ Questions Needing Answers

- [ ] **[TR-?01]** Should the treasury validate deposit value against a price oracle?
  - Context: Currently trusts bond depository to send correct value parameter.
  - Options:
    A) Trust depositors (current - simpler)
    B) Validate against oracle (more secure)
  - **ANSWER:** [pending]

- [ ] **[TR-?02]** Should HONEY be added as a reserve token?
  - Context: It's referenced for LP but not as a reserve token itself.
  - Options:
    A) No, only iBGT is reserve
    B) Yes, add HONEY as reserve for yield strategy
  - **ANSWER:** [pending]

### ✅ Verified Correct

- Ownable2Step correctly implemented
- ReentrancyGuard on all state-changing functions
- Proper separation of reserve manager and yield manager roles

---

## ApiaryBondDepository.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[BD-C01]** `valueOf()` is not `view` - calls `twap.consult()` which may modify state
  - Location: `valueOf()` function, lines 397-430
  - Description: Function modifies state or makes external calls that can modify state. This is called in `deposit()` and `bondPriceInHoney()`.
  - Risk: Unexpected state changes, potential reentrancy vector.
  - Recommendation: If TWAP needs to update, make this explicit. Consider separate update and view functions.

- [ ] **[BD-C02]** Bond stacking - user's previous bond is overwritten
  - Location: `deposit()` function, lines 264-274
  - Description: If a user deposits again before redeeming, their existing bond is partially overwritten. `payout` accumulates but `vesting` is reset to `terms.vestingTerm`. This extends the vesting period for the old deposit.
  - Risk: User's first deposit may have been almost vested, but second deposit resets vesting entirely.
  - Recommendation: Either prevent stacking (one active bond per user) or properly calculate weighted average vesting.

### 🟡 Medium Issues (Should Fix)

- [ ] **[BD-M01]** `valueOf()` for non-LP bonds ignores actual iBGT price
  - Location: `valueOf()` function, lines 410-420
  - Description: For iBGT bonds, the function just does decimal conversion without considering iBGT's actual value. It divides by `discountedPriceInHoney` which is APIARY price, not iBGT price.
  - Risk: Bond pricing may be incorrect if iBGT ≠ HONEY in value.
  - Recommendation: Add iBGT/HONEY price oracle for accurate valuation.

- [ ] **[BD-M02]** `totalDebt` never decreases
  - Location: `totalDebt` variable, `deposit()` and `redeem()` functions
  - Description: `totalDebt` increases on deposit but never decreases on redeem. This means once `maxDebt` is hit, no more bonds can be sold ever.
  - Risk: Bond sales permanently stop after reaching maxDebt, even though bonds have been redeemed.
  - Recommendation: Add debt decay or subtract from totalDebt on redeem.

- [ ] **[BD-M03]** `maxPayout()` depends on treasury's allocation which may be 0
  - Location: `maxPayout()` function, lines 526-529
  - Description: Uses `IApiaryToken(APIARY).allocationLimits(treasury)`. If treasury's allocation is 0 (exhausted or not set), maxPayout is 0 and all bonds fail.
  - Risk: Bonds silently fail if treasury allocation not maintained.
  - Recommendation: Add explicit check with meaningful error, or use different mechanism.

- [ ] **[BD-M04]** Fee sent to DAO in APIARY but treasury receives principle
  - Location: `deposit()` function, lines 246-252
  - Description: Treasury deposits principle and mints `payout` APIARY. Fee is then transferred from...where? The APIARY just minted went to the treasury.
  - Risk: The `IERC20(APIARY).safeTransfer(dao, fee)` will fail because BondDepository doesn't have APIARY.
  - Recommendation: Fix the flow - treasury should mint to BondDepository first, which then sends fee and rest to user.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[BD-L01]** `clawBackTokens` can withdraw principle tokens, breaking bonds
  - Description: Owner can withdraw any tokens including bonded principle before it's sent to treasury.
  - Recommendation: Add timelock or prevent clawing principle tokens.

- [ ] **[BD-L02]** No check that `bondCalculator` is valid for LP bonds
  - Description: If `bondCalculator != address(0)`, it's assumed to be LP bond but calculator validity isn't verified.
  - Recommendation: Add interface check or require callable.

- [ ] **[BD-L03]** Missing event for `updateTwap()`
  - Description: TWAP update doesn't emit event (wait, it does - TwapUpdated. Verified.)
  - Actually verified correct.

### 🔵 Code Quality / Cleanup

- [ ] **[BD-Q01]** Consider making MINIMUM_PAYOUT configurable
- [ ] **[BD-Q02]** Add getter for available debt (`terms.maxDebt - totalDebt`)
- [ ] **[BD-Q03]** Document the expected TWAP oracle interface

### ❓ Questions Needing Answers

- [ ] **[BD-?01]** Should users be able to stack multiple bonds?
  - Context: Current implementation resets vesting on new deposit.
  - Options:
    A) No stacking - require redeem before new deposit
    B) Stack with weighted average vesting
    C) Current behavior is fine (user accepts reset)
  - **ANSWER:** [pending]

- [ ] **[BD-?02]** How is iBGT valued for bonds?
  - Context: Current implementation assumes 1 iBGT = 1 HONEY which may not be accurate.
  - Options:
    A) 1:1 with HONEY (current)
    B) Use iBGT/HONEY price oracle
  - **ANSWER:** [pending]

- [ ] **[BD-?03]** Should totalDebt decay over time?
  - Context: Without decay, bond capacity is permanently consumed.
  - Options:
    A) Yes, add debt decay (OHM style)
    B) No, manual reset by admin
    C) Subtract on redeem
  - **ANSWER:** [pending]

- [ ] **[BD-?04]** How are DAO fees actually paid?
  - Context: Current flow has fee transfer from BondDepository but it doesn't receive APIARY.
  - Options:
    A) Treasury mints to BondDepository first
    B) Treasury mints fee directly to DAO
    C) Remove fees
  - **ANSWER:** [pending]

### ✅ Verified Correct

- ReentrancyGuard on deposit/redeem
- Pausable correctly implemented
- Ownable2Step for admin safety
- Slippage protection via maxPriceInHoney

---

## ApiaryPreSaleBond.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[PS-C01]** `apiaryToken` can be set after TGE starts, changing vesting token
  - Location: `setApiaryToken()` function, lines 400-406
  - Description: No check preventing token address change after TGE or even after sales started. Changing token address after sales would break vesting.
  - Risk: Users' purchased tokens become unclaimable if address changes.
  - Recommendation: Add `require(!tgeStarted && currentPreSaleBondState == PreSaleBondState.NotStarted)`

### 🟡 Medium Issues (Should Fix)

- [ ] **[PS-M01]** `unlockApiary()` has incorrect modifier order
  - Location: `unlockApiary()` function, line 278
  - Description: Function has `whenNotPaused nonReentrant` but also calls itself recursively from `purchaseApiary()` (line 239). If paused, recursive call fails.
  - Risk: `purchaseApiary` would fail if contract is paused even for first purchase.
  - Recommendation: Move unlock logic to internal function without modifiers.

- [ ] **[PS-M02]** Double refund calculation in `purchaseApiary()`
  - Location: `purchaseApiary()` function, lines 241-258
  - Description: Two separate blocks calculate `honeyToRefund` - once for available limit and once for user limit. The second calculation overwrites the first.
  - Risk: If user hits both limits, only one refund is calculated.
  - Recommendation: Fix logic to calculate minimum purchase amount first, then single refund.

- [ ] **[PS-M03]** `mintApiary()` can be called before pre-sale ends
  - Location: `mintApiary()` function, lines 296-300
  - Description: No check that pre-sale has ended. Can mint while still selling.
  - Risk: Minor - minting early is fine, but tokens could be claimed before pre-sale ends if TGE starts.
  - Recommendation: Add state check: `require(currentPreSaleBondState == PreSaleBondState.Ended)`

### 🟢 Low Issues (Nice to Fix)

- [ ] **[PS-L01]** Vesting starts from TGE, not from purchase
  - Description: All buyers vest from same TGE timestamp, not from their purchase time. Early buyers wait longer.
  - Recommendation: Document this is intentional (fair launch style) or consider per-user vesting start.

- [ ] **[PS-L02]** No check that `mintApiary()` is called before TGE
  - Description: If TGE starts before minting, users can call `unlockApiary()` but contract has no tokens.
  - Recommendation: Add check in `setTgeStartTime()` that tokens are minted.

- [ ] **[PS-L03]** `clawBack()` can withdraw sold APIARY tokens
  - Description: After minting, owner can claw back the APIARY meant for vesting.
  - Recommendation: Prevent clawing APIARY after mint, or add timelock.

### 🔵 Code Quality / Cleanup

- [ ] **[PS-Q01]** `_investorAllocations` uses `start` and `duration` fields but only `duration` is used
- [ ] **[PS-Q02]** Consider adding `getTotalSaleValue()` view function
- [ ] **[PS-Q03]** Missing event for `setApiaryToken()`

### ❓ Questions Needing Answers

- [ ] **[PS-?01]** Is per-purchase or per-wallet limit intended?
  - Context: Current limit is per-wallet cumulative. User cannot exceed 500 APIARY total.
  - Options:
    A) Per-wallet cumulative (current)
    B) Per-purchase limit
  - **ANSWER:** [pending]

- [ ] **[PS-?02]** Should vesting start from TGE or purchase time?
  - Context: Current TGE-based means early buyers wait longer than late buyers.
  - Options:
    A) TGE-based (current - fair launch)
    B) Purchase-time based (each user has 5-day vest from purchase)
  - **ANSWER:** [pending]

- [ ] **[PS-?03]** Can whitelist be disabled mid-sale?
  - Context: `setWhitelistEnabled(false)` can be called anytime, opening to public.
  - Options:
    A) Yes, intentional feature
    B) No, should lock after sale starts
  - **ANSWER:** [pending]

### ✅ Verified Correct

- Merkle proof verification correctly implemented
- State transitions are one-way (NotStarted → Live → Ended)
- Slippage protection on purchase
- ReentrancyGuard on all user functions

---

## ApiaryYieldManager.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[YM-C01]** `_claimYieldFromInfrared()` doesn't actually claim - relies on external call with hardcoded signature
  - Location: `_claimYieldFromInfrared()` function, lines 364-376
  - Description: Uses `call` with hardcoded signature `"claimRewards()"`. If Infrared adapter's function signature differs, this fails silently or reverts.
  - Risk: Yield execution fails completely if signature mismatch.
  - Recommendation: Use interface-based call: `IInfraredAdapter(infraredAdapter).claimRewards()`

- [ ] **[YM-C02]** `_swapToHoney()` and `_swapToApiary()` use raw `call` with signature strings
  - Location: Lines 389-412, 428-458
  - Description: Using `call` with string signatures is fragile and doesn't verify interface. Also, return value decoding may fail if adapter returns different structure.
  - Risk: Silent failures, wrong amounts decoded, stuck funds.
  - Recommendation: Create proper `IKodiakAdapter` interface and use it.

- [ ] **[YM-C03]** `_burnApiary()` fallback sends to dead address but doesn't confirm
  - Location: `_burnApiary()` function, lines 530-543
  - Description: If `burn()` call fails, it sends to 0xdead. But this doesn't actually burn - it just removes from circulation. Also, no check that transfer succeeded.
  - Risk: Tokens not actually burned, just in limbo at 0xdead.
  - Recommendation: Use proper `IApiaryToken.burn()` call or revert if burn fails.

### 🟡 Medium Issues (Should Fix)

- [ ] **[YM-M01]** `executeYield()` can be called by anyone
  - Location: `executeYield()` function, line 251
  - Description: No access control - anyone can trigger yield execution.
  - Risk: Could be griefed by calling with minimal yield, wasting gas. Or front-run to manipulate execution timing.
  - Recommendation: Add keeper role or minimum time between executions.

- [ ] **[YM-M02]** Split percentages don't validate Phase 1 vs Phase 2/3 usage
  - Location: `setSplitPercentages()` function
  - Description: Phase 1 uses toHoney/toApiaryLP/toBurn. Phase 2 adds toStakers/toCompound. No validation that Phase 1 config uses only Phase 1 fields.
  - Risk: Misconfiguration could leave funds unallocated.
  - Recommendation: Add per-strategy validation.

- [ ] **[YM-M03]** `_calculateHoneyForLP()` assumes 1:1 ratio
  - Location: `_calculateHoneyForLP()` function, lines 623-628
  - Description: Comment says "assume 1:1 ratio (simplified)" but actual pool ratio will differ.
  - Risk: Suboptimal LP creation, leftover tokens not properly handled.
  - Recommendation: Query actual pool reserves for optimal ratio.

- [ ] **[YM-M04]** `_stakeLPTokens()` is incomplete - doesn't actually stake
  - Location: `_stakeLPTokens()` function, lines 599-615
  - Description: Function has TODO-like logic with `staticcall` and empty implementation.
  - Risk: LP tokens created but never staked, losing gauge rewards.
  - Recommendation: Complete implementation or remove from Phase 1.

- [ ] **[YM-M05]** No mechanism to recover failed partial executions
  - Location: Throughout execution functions
  - Description: If swap fails, `PartialExecutionFailure` is emitted but no recovery mechanism. Tokens may be stuck.
  - Risk: Partial execution leaves protocol in inconsistent state.
  - Recommendation: Add state recovery mechanism or make execution atomic.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[YM-L01]** `emergencyMode` forwards to treasury but treasury doesn't expect random iBGT
  - Description: Emergency mode sends all iBGT to treasury without updating accounting.
  - Recommendation: Document emergency mode side effects.

- [ ] **[YM-L02]** No way to manually trigger distributor
  - Description: Distributor only triggered during rebase through staking.
  - Recommendation: Add manual trigger for Phase 2 testing.

- [ ] **[YM-L03]** `pendingYield()` may not work if adapter interface differs
  - Description: Uses `staticcall` with signature, may fail silently.
  - Recommendation: Use proper interface.

### 🔵 Code Quality / Cleanup

- [ ] **[YM-Q01]** Many functions use raw `call` - refactor to use interfaces
- [ ] **[YM-Q02]** Add comprehensive natspec for strategy logic
- [ ] **[YM-Q03]** Consider splitting strategies into separate internal contracts

### ❓ Questions Needing Answers

- [ ] **[YM-?01]** Should `executeYield()` be permissionless?
  - Context: Currently anyone can call, which could be feature (MEV searchers help) or bug (griefing).
  - Options:
    A) Yes, permissionless (current)
    B) Keeper/bot role only
    C) DAO multisig only
  - **ANSWER:** [pending]

- [ ] **[YM-?02]** What happens to dust/leftover amounts?
  - Context: After splits and swaps, small amounts may remain.
  - Options:
    A) Stay in YieldManager (accumulate)
    B) Forward to treasury
    C) Include in next execution
  - **ANSWER:** [pending]

- [ ] **[YM-?03]** Is Phase 1 LP staking implemented?
  - Context: `_stakeLPTokens()` appears incomplete.
  - Options:
    A) Yes, needs to be completed
    B) No, LP just held in treasury for Phase 1
  - **ANSWER:** [pending]

- [ ] **[YM-?04]** Should failed swaps revert the entire execution or allow partial success?
  - Context: Current behavior emits event and returns 0, continuing.
  - Options:
    A) Partial success is fine (current)
    B) All-or-nothing (atomic)
  - **ANSWER:** [pending]

### ✅ Verified Correct

- Ownable2Step for ownership safety
- Pausable for emergency stops
- ReentrancyGuard on main execution
- Slippage tolerance configurable and enforced

---

## ApiaryInfraredAdapter.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [x] **[IA-C01]** `stake()` doesn't transfer tokens from caller before staking
  - Location: `stake()` function, lines 183-211
  - Description: ~~Function calls `infrared.stake(amount)` but tokens need to be in the adapter first. No `safeTransferFrom` at start.~~
  - **FIXED:** Now uses pull pattern - adapter calls `safeTransferFrom(msg.sender, ...)` to pull iBGT from YieldManager. YieldManager must approve adapter first.
  - Risk: ~~Stake fails because adapter has no tokens to stake.~~ Resolved.

### 🟡 Medium Issues (Should Fix)

- [x] **[IA-M01]** Constructor grants max approval to Infrared
  - Location: ~~Constructor, line 160: `ibgt.approve(_infrared, type(uint256).max)`~~
  - Description: ~~Unlimited approval to Infrared contract.~~
  - **FIXED:** Removed unlimited approval from constructor. Added `setupApprovals()` admin function that owner calls after deployment.
  - Risk: ~~If Infrared has vulnerability, all iBGT could be drained.~~ Mitigated via explicit approval setup.

- [x] **[IA-M02]** `totalStaked` can differ from actual staked amount
  - Location: `stake()` and `unstake()` functions
  - Description: ~~`totalStaked` is updated by requested amount, but actual stake/unstake may differ (fees, slashing).~~
  - **FIXED:** Added `syncAccounting()` admin function to reconcile `totalStaked` with actual Infrared balance. Also added `getStakedBalance()` view to query actual balance.
  - Risk: ~~Accounting mismatch with reality.~~ Can now be corrected via sync function.

- [x] **[IA-M03]** `autoCompound` only works if reward token is iBGT
  - Location: ~~`claimRewards()` function, lines 248-268~~
  - Description: ~~Auto-compound restakes only if `rewardToken == ibgt`. But Infrared might pay in HONEY or other tokens.~~
  - **FIXED:** Removed autoCompound feature entirely. `claimRewards()` now simply returns rewards to caller (YieldManager). YieldManager decides what to do with rewards.
  - Risk: ~~Auto-compound silently fails for non-iBGT rewards.~~ Resolved by removing complexity.

### 🟢 Low Issues (Nice to Fix)

- [x] **[IA-L01]** `rewardToken` is set in constructor but Infrared might have multiple reward tokens
  - Description: ~~Only tracks one reward token via `infrared.rewardToken()`.~~
  - **FIXED:** Removed `rewardToken` immutable. Rewards are simply claimed and returned to caller, regardless of token type.

- [x] **[IA-L02]** `balancesBefore` calculated but not used in `stake()`
  - Location: ~~`stake()` function, line 193~~
  - Description: ~~`balanceBefore` is set but never used.~~
  - **FIXED:** Now uses balance before/after for verification of actual staked amount.

### 🔵 Code Quality / Cleanup

- [x] **[IA-Q01]** Add more detailed natspec for Infrared integration assumptions
  - **DONE:** Updated contract header with flow documentation
- [x] **[IA-Q02]** Consider adding stake/unstake return value validation
  - **DONE:** Added balance verification after each operation

### ❓ Questions Needing Answers

- [x] **[IA-?01]** Does the adapter receive tokens before staking, or pull from treasury?
  - Context: Current flow unclear - YieldManager or Treasury should transfer tokens first.
  - **ANSWER:** Pull pattern - YieldManager approves adapter, adapter pulls iBGT via `safeTransferFrom`

- [x] **[IA-?02]** What reward tokens does Infrared actually provide?
  - Context: Interface assumes single rewardToken but Infrared may have multiple.
  - **ANSWER:** Simplified - rewards returned to caller regardless of type. YieldManager handles rewards.

### ✅ Verified Correct

- Ownable2Step for ownership
- ReentrancyGuard on all state-changing functions
- Pausable for emergencies
- Emergency withdraw functionality
- **NEW:** onlyYieldManager modifier on core functions
- **NEW:** Pull pattern for token transfers
- **NEW:** Balance verification after operations

---

## ApiaryKodiakAdapter.sol

### 🔴 Critical Issues (Must Fix Before Deployment)

- [ ] **[KA-C01]** `swap()` transfers tokens FROM msg.sender but yieldManager may not have approved
  - Location: `swap()` function, line 236
  - Description: `IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn)` requires msg.sender (yieldManager) to have approved adapter.
  - Risk: All swaps fail if YieldManager hasn't approved adapter.
  - Recommendation: Document approval requirement or use pull pattern from treasury.

### 🟡 Medium Issues (Should Fix)

- [ ] **[KA-M01]** LP tokens returned to recipient but not tracked
  - Location: `addLiquidity()` function
  - Description: LP tokens go to `recipient` but `totalStakedLP` isn't updated (that's only for staked LP).
  - Risk: No issue, but confusing naming - `totalStakedLP` only tracks staked, not received.
  - Recommendation: Add comments clarifying tracking.

- [ ] **[KA-M02]** `registerGauge()` can be overwritten
  - Location: `registerGauge()` function, line 749
  - Description: Owner can change gauge for an LP token at any time, potentially breaking staking.
  - Risk: If gauge changed while LP staked, claims/unstakes would fail.
  - Recommendation: Add check that no LP is staked before allowing gauge change.

- [ ] **[KA-M03]** No validation that gauge matches LP token
  - Location: `registerGauge()` function
  - Description: Owner can register any gauge for any LP token, including mismatched pairs.
  - Risk: Staking to wrong gauge would lose rewards.
  - Recommendation: Add validation that gauge.stakingToken() == lpToken.

### 🟢 Low Issues (Nice to Fix)

- [ ] **[KA-L01]** `totalRewardsClaimed` counts operations, not amounts
  - Description: Variable name suggests amount but increments by 1 per claim operation.
  - Recommendation: Rename to `totalRewardClaimOperations` or track amounts.

- [ ] **[KA-L02]** No check that path tokens all have pools
  - Location: `swapMultiHop()` validates pools exist
  - Actually this is checked - verified correct.

### 🔵 Code Quality / Cleanup

- [ ] **[KA-Q01]** `_approveTokenIfNeeded` could use forceApprove directly instead of checking first
- [ ] **[KA-Q02]** Consider adding batch operations for gas efficiency

### ❓ Questions Needing Answers

- [ ] **[KA-?01]** What is the expected approval flow for YieldManager → Adapter?
  - Context: Adapter does safeTransferFrom but YieldManager must have approved.
  - Options:
    A) YieldManager approves adapter in constructor
    B) YieldManager approves per-operation
    C) Change to pull from treasury directly
  - **ANSWER:** [pending]

- [ ] **[KA-?02]** Should gauges be immutable once set?
  - Context: Currently owner can change gauge, which could break staked positions.
  - Options:
    A) Yes, make immutable
    B) No, but add safety checks
  - **ANSWER:** [pending]

### ✅ Verified Correct

- ReentrancyGuard on all external functions
- Pausable for emergencies
- Ownable2Step for ownership
- Slippage and deadline protection on all swaps
- Pool existence validation before swaps

---

## Cross-Contract Integration Issues

### 🔴 Critical Integration Issues

- [ ] **[INT-C01]** YieldManager ↔ Adapters use raw calls instead of interfaces
  - Location: ApiaryYieldManager.sol various functions
  - Description: YieldManager calls adapters via `call()` with signature strings. If interface changes, calls silently fail.
  - Risk: Yield execution completely broken if any signature mismatches.
  - Recommendation: Create proper interfaces (IApiaryInfraredAdapter, IApiaryKodiakAdapter) and use them.

- [ ] **[INT-C02]** Token approval chain not established
  - Description: The following approval chain is needed but not documented:
    1. Treasury approves YieldManager for iBGT (for pullIBGTForStaking)
    2. YieldManager approves KodiakAdapter for APIARY, HONEY, iBGT
    3. YieldManager approves InfraredAdapter for iBGT
    4. User approves Staking for APIARY
    5. User approves BondDepository for iBGT/LP
  - Risk: Missing approvals cause transaction failures.
  - Recommendation: Add approval setup in deployment scripts and document.

### 🟡 Medium Integration Issues

- [ ] **[INT-M01]** Inconsistent ownership patterns
  - Description: Contracts use mix of:
    - AccessControl (ApiaryToken)
    - Custom Ownable with push/pull (sApiary, ApiaryStaking)
    - OZ Ownable2Step (Treasury, Bonds, YieldManager, Adapters)
  - Risk: Confusing access control, potential for mistakes.
  - Recommendation: Standardize on OZ Ownable2Step or AccessControl.

- [ ] **[INT-M02]** Treasury mint allocation must match bond depository needs
  - Description: Treasury needs MINTER_ROLE and allocation in ApiaryToken. Bond depository calls `treasury.deposit()` which calls `APIARY_TOKEN.mint()`.
  - Risk: If allocation runs out, all bond sales fail.
  - Recommendation: Add monitoring/alerting for allocation levels.

- [ ] **[INT-M03]** Phase transitions not synchronized across contracts
  - Description: YieldManager has strategies (Phase 1/2/3), PreSale has states (NotStarted/Live/Ended), but no central coordination.
  - Risk: Phases could be mismatched (e.g., YieldManager in Phase 2 but staking still Phase 1).
  - Recommendation: Consider central phase controller or document dependency order.

### ❓ Integration Questions

- [ ] **[INT-?01]** What is the deployment order for these contracts?
  - Context: Many contracts reference each other (circular dependencies).
  - **ANSWER:** [pending]

- [ ] **[INT-?02]** What is the initialization sequence after deployment?
  - Context: Many contracts need addresses set, roles granted, approvals made.
  - **ANSWER:** [pending]

- [ ] **[INT-?03]** Is there a central registry for contract addresses?
  - Context: Each contract stores references individually, no single source of truth.
  - Options:
    A) No registry (current)
    B) Add DeploymentRegistry as source of truth
  - **ANSWER:** [pending]

---

## Deployment & Configuration Risks

- [ ] **[DEP-01]** No deployment script validation
  - Risk: Human error in deployment could leave contracts misconfigured.
  - Recommendation: Add post-deployment validation script.

- [ ] **[DEP-02]** Many one-time-set variables
  - Description: warmupContract, locker, INDEX can only be set once. Mistakes are permanent.
  - Recommendation: Add timelock window for changes or allow reset in emergency.

- [ ] **[DEP-03]** Admin key management critical
  - Description: DEFAULT_ADMIN_ROLE in ApiaryToken controls all minting. Owner in other contracts controls funds.
  - Recommendation: Use multisig for all admin addresses from day 1.

- [ ] **[DEP-04]** No pause mechanism for full protocol
  - Description: Each contract has individual pause, but no global emergency stop.
  - Recommendation: Consider adding emergency shutdown role that can pause all contracts.

- [ ] **[DEP-05]** Treasury approval amounts for adapters not set
  - Description: Treasury needs to approve YieldManager for iBGT, but no setter exists.
  - Recommendation: Add approval management in Treasury.

---

## All Questions Summary

Collect all questions here for easy answering:

### ApiaryToken.sol
1. **[AT-?01]** Is public burning intentional, or should it be restricted to BURNER_ROLE? - **ANSWER:** [pending]
2. **[AT-?02]** Should burned tokens allow re-minting up to the 200k cap? - **ANSWER:** [pending]

### sApiary.sol
3. **[SA-?01]** What is the intended initial INDEX value? - **ANSWER:** [pending]
4. **[SA-?02]** Is the 5M initial fragment supply intentional? - **ANSWER:** [pending]

### ApiaryStaking.sol
5. **[AS-?01]** Is 1:1 sAPIARY→APIARY unstaking intentional even after rebases? - **ANSWER:** [pending]
6. **[AS-?02]** Should `forfeit()` return APIARY or sAPIARY value? - **ANSWER:** [pending]
7. **[AS-?03]** What is the intended warmup period? - **ANSWER:** [pending]

### ApiaryTreasury.sol
8. **[TR-?01]** Should the treasury validate deposit value against a price oracle? - **ANSWER:** [pending]
9. **[TR-?02]** Should HONEY be added as a reserve token? - **ANSWER:** [pending]

### ApiaryBondDepository.sol
10. **[BD-?01]** Should users be able to stack multiple bonds? - **ANSWER:** [pending]
11. **[BD-?02]** How is iBGT valued for bonds? - **ANSWER:** [pending]
12. **[BD-?03]** Should totalDebt decay over time? - **ANSWER:** [pending]
13. **[BD-?04]** How are DAO fees actually paid? - **ANSWER:** [pending]

### ApiaryPreSaleBond.sol
14. **[PS-?01]** Is per-purchase or per-wallet limit intended? - **ANSWER:** [pending]
15. **[PS-?02]** Should vesting start from TGE or purchase time? - **ANSWER:** [pending]
16. **[PS-?03]** Can whitelist be disabled mid-sale? - **ANSWER:** [pending]

### ApiaryYieldManager.sol
17. **[YM-?01]** Should `executeYield()` be permissionless? - **ANSWER:** [pending]
18. **[YM-?02]** What happens to dust/leftover amounts? - **ANSWER:** [pending]
19. **[YM-?03]** Is Phase 1 LP staking implemented? - **ANSWER:** [pending]
20. **[YM-?04]** Should failed swaps revert the entire execution or allow partial success? - **ANSWER:** [pending]

### ApiaryInfraredAdapter.sol
21. **[IA-?01]** Does the adapter receive tokens before staking, or pull from treasury? - **ANSWER:** [pending]
22. **[IA-?02]** What reward tokens does Infrared actually provide? - **ANSWER:** [pending]

### ApiaryKodiakAdapter.sol
23. **[KA-?01]** What is the expected approval flow for YieldManager → Adapter? - **ANSWER:** [pending]
24. **[KA-?02]** Should gauges be immutable once set? - **ANSWER:** [pending]

### Cross-Contract
25. **[INT-?01]** What is the deployment order for these contracts? - **ANSWER:** [pending]
26. **[INT-?02]** What is the initialization sequence after deployment? - **ANSWER:** [pending]
27. **[INT-?03]** Is there a central registry for contract addresses? - **ANSWER:** [pending]

---

## Notes & Observations

### Good Patterns Observed
- Consistent use of ReentrancyGuard on state-changing functions
- Pausable pattern implemented correctly across contracts
- Good use of custom errors instead of require strings (gas efficient)
- Events emitted for most state changes
- SafeERC20 used consistently for token transfers
- Slippage protection considered in bonds and swaps

### Concerning Patterns
- **Inconsistent ownership patterns** - Mix of AccessControl, custom Ownable, and OZ Ownable2Step creates confusion
- **Raw `call()` usage in YieldManager** - Fragile, should use typed interfaces
- **Many one-time-set variables** - Creates deployment risk with no recovery
- **Tight coupling without interfaces** - Contracts reference each other directly without abstraction
- **SafeMath usage in Solidity 0.8** - Unnecessary, adds gas overhead

### Technical Debt
- Multiple duplicate implementations of Ownable, ERC20Permit across files
- Incomplete implementations in YieldManager (LP staking, Phase 2/3 strategies)
- Mock interface for Infrared needs to be updated with actual interface

### Recommendations for Future Development
1. **Create comprehensive interface files** for all Apiary contracts
2. **Standardize on OZ Ownable2Step** for all ownership
3. **Add deployment validation tests** that verify all connections are correct
4. **Consider upgradeable proxies** for contracts that may need updates
5. **Add integration tests** that cover full flows across contracts

---

## Next Steps

After answering questions:
1. Review answers and update recommendations
2. Prioritize fixes by severity and effort
3. Implement critical issues first
4. Re-review changed code
5. Add missing tests for fixed issues
6. Conduct integration testing across contracts
7. Proceed to external audit

---

## Severity Definitions

| Severity | Description |
|----------|-------------|
| 🔴 Critical | Could result in loss of funds, protocol failure, or security breach. Must fix before deployment. |
| 🟡 Medium | Could cause protocol malfunction, poor UX, or edge case issues. Should fix before deployment. |
| 🟢 Low | Code quality issues, minor gas inefficiencies, or documentation gaps. Nice to fix. |
| 🔵 Quality | Code cleanup, style improvements, best practices. Fix during refactoring. |
| ❓ Question | Business logic decision needed. Cannot proceed without answer. |
