# Apiary Protocol - Mainnet Deployment Checklist

**Date:** 2026-02-06
**Status:** Pre-Mainnet

---

## 1. Remaining Audit Items

### Unfixed Informational Findings

| ID | Description | Impact | Action Needed |
|---|---|---|---|
| INFO-02 | ERC20Permit duplicated in `libs/ERC20Permit.sol` and `sApiary.sol` | Maintenance risk if one copy diverges | Low priority - cosmetic |
| INFO-03 | Public `DOMAIN_SEPARATOR` variable stale after chain fork | External callers reading the public var get stale value (internal `_domainSeparator()` is correct) | Consider removing the public variable or overriding the getter |
| INFO-04 | `valueOf()` / `bondPriceInHoney()` naming doesn't indicate state change | Misleading to developers | Largely mitigated — `valueOf()` is now internal, `bondPriceInHoney()` is onlyOwner |

### Unfixed Gas Optimizations

| Optimization | Location | Estimated Savings |
|---|---|---|
| Cache `userBonds[msg.sender]` storage pointer in `deposit()` | BondDepository.sol:337-348 | ~200 gas per deposit |
| Use `unchecked` for loop increments in `redeemAll()` | BondDepository.sol:411 | ~30 gas per iteration |
| Pack Bond struct more efficiently | BondDepository.sol:69-75 | ~2100 gas (1 SSTORE saved) |
| Cache `splitConfig` as memory in `_executePhase1Strategy()` | YieldManager.sol:483-485 | ~300 gas |

### Partially Fixed

| ID | Description | What Was Done | What Remains |
|---|---|---|---|
| LOW-03 | Custom ERC20 missing safety features | Removed unused SafeMath import | Full migration to OZ ERC20 deferred — sApiary overrides ERC20 heavily with gons-based accounting, making a base class swap risky |

---

## 2. Missing Implementations

### ApiaryBondingCalculator — NO CONTRACT EXISTS

- **Interface:** `src/interfaces/IApiaryBondingCalculator.sol` (1 function: `valuation()`)
- **Used by:** `ApiaryBondDepository.sol` (LP bond pricing) and `ApiaryTreasury.sol` (LP valuation in deposit)
- **Impact:** LP bonds WILL NOT WORK without this contract deployed
- **Action:** Must implement and deploy a bonding calculator before enabling LP bonds. For iBGT-only bonds, this is not needed (`bondCalculator = address(0)`)

### IInfrared — MOCK INTERFACE

- **File:** `src/interfaces/IInfrared.sol`
- **Status:** Explicitly marked as `MOCK interface based on common LST patterns`
- **TODO in code:** `"Update with actual Infrared protocol interface once available"`
- **Impact:** `ApiaryInfraredAdapter.sol` depends on this interface. If the real Infrared protocol has a different interface, the adapter will need to be updated
- **Action:** Verify against actual Infrared protocol on Berachain mainnet and update interface + adapter if needed

---

## 3. Deployment Script Gaps

### Hardcoded Testnet Addresses in `DeployAll.s.sol`

The deployment script uses **Bepolia testnet addresses**. These MUST be updated for mainnet:

```
IBGT_ADDRESS    = 0x46eFC86F0D7455F135CC9df501673739d513E982  // Testnet iBGT
HONEY_ADDRESS   = 0x7EeCA4205fF31f947EdBd49195a7A88E6A91161B  // Testnet HONEY
INFRARED_STAKING = 0x75F3Be06b02E235E93Aa599F2fA6e44ed67B6C47  // Testnet Infrared
KODIAK_ROUTER   = 0x496e305C03909ae382974cAcA4c580E1BF32afBE  // Testnet Router
KODIAK_FACTORY  = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da  // Testnet Factory
```

### Placeholder Merkle Root

```solidity
bytes32 constant DEFAULT_MERKLE_ROOT = keccak256("APIARY_PRESALE_PLACEHOLDER");
```

This MUST be replaced with the real whitelist merkle root before starting the pre-sale.

### Epoch Configuration

Current testnet value: `EPOCH_LENGTH = 600` (10 minutes with ~1s blocks). Adjust for mainnet block times.

### Missing Farm Addresses

`script/utils/FindActiveFarms.s.sol` has a TODO: `"Add known farm addresses here after discovering them"`. Kodiak farm addresses must be registered after deployment.

---

## 4. Pre-Deployment Checklist

### Code

- [ ] Commit all audit fix changes (10 modified files currently uncommitted)
- [ ] Run full test suite: `forge test --gas-report`
- [ ] Run coverage report: `forge coverage --report summary --skip script`
- [ ] Verify all tests pass after audit modifications
- [ ] Review that `ApiaryInfraredAdapter` works with real Infrared protocol
- [ ] Implement or source `ApiaryBondingCalculator` if LP bonds are needed at launch

### Configuration

- [ ] Replace all Bepolia addresses with Berachain mainnet addresses (chain ID: 80094)
- [ ] Generate production merkle root from final whitelist
- [ ] Set appropriate epoch length for mainnet
- [ ] Determine initial bond terms (vesting, max payout, discount, max debt)
- [ ] Set `maxMintRatioBps` on Treasury (HIGH-01 fix parameter)
- [ ] Set `maxMintPerDeposit` on Treasury
- [ ] Prepare `.env` file with mainnet RPC, deployer key, Berascan API key

### Security

- [ ] Verify deployer wallet is a multisig or secure key management
- [ ] Plan ownership transfer to multisig after deployment (Ownable2Step)
- [ ] Set keeper address for YieldManager (separate from owner for operational security)
- [ ] Review all `onlyOwner` functions and ensure admin key security

---

## 5. Post-Deployment Steps

### Immediate (Before Operations Begin)

1. **Create APIARY/HONEY LP pool** on Kodiak DEX
2. **Deploy TWAP Oracle** with the LP pair address
3. **Initialize sApiary:**
   - Call `sApiary.initialize(stakingAddress)`
   - Call `sApiary.setIndex(initialIndex)`
4. **Configure Treasury:**
   - Add reserve tokens: `toggleReserveToken(iBGT)`
   - Add LP token: `toggleLiquidityToken(lpToken)`
   - Set depositors: `toggleDepositor(bondDepository)`
   - Set `maxMintPerDeposit` and `maxMintRatioBps`
   - Set LP calculator if using LP bonds
5. **Configure APIARY Token:**
   - Set allocation limits for treasury, pre-sale
   - Set vault, staking, lockUp addresses
6. **Configure Bond Depository:**
   - Call `initializeBondTerms(vestingTerm, maxPayout, discountRate, maxDebt)`
   - Enable dynamic discounts if desired: `setDynamicDiscounts(true)`
   - Set reference price for deviation protection
7. **Configure YieldManager:**
   - Register Kodiak farm: adapter `registerFarm(lpToken, farmAddress)`
   - Set up approvals: `setupApprovals()`
   - Set reward token: `setRewardToken(address)`
   - Set staking contract: `setStakingContract(address)`
8. **Configure Staking:**
   - Set distributor: `setContract(DISTRIBUTOR, address)`

### Pre-Sale Launch

1. Set real merkle root: `preSaleBond.setMerkleRoot(root)`
2. Set APIARY token: `preSaleBond.setApiaryToken(address)`
3. Start pre-sale: `preSaleBond.startPreSaleBond()`
4. After pre-sale ends: `preSaleBond.endPreSaleBond()`
5. Mint allocated tokens: `preSaleBond.mintApiary()`
6. Start TGE: `preSaleBond.setTgeStartTime()`

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

- [ ] `forge test` — all 410+ tests pass
- [ ] `forge test --gas-report` — gas usage within acceptable bounds
- [ ] `forge coverage` — critical paths have >90% coverage
- [ ] Fork test against Berachain mainnet RPC (verify real Kodiak/Infrared integration)
- [ ] Manual test on Bepolia with full deployment flow
- [ ] Verify contract verification works on Berascan

---

## 8. Risk Summary

| Risk | Severity | Mitigation |
|---|---|---|
| IInfrared interface mismatch | High | Verify against real protocol before mainnet |
| No BondingCalculator implementation | Medium | Only affects LP bonds; iBGT bonds work without it |
| TWAP oracle bootstrap manipulation | Low | Fixed: requires 3 updates (~3 hours) before usable |
| Uncommitted audit fixes | High | Commit, test, and verify all changes before deploy |
| Admin key compromise | High | Transfer to multisig immediately after deployment |
