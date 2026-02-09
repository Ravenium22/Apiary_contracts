# Mainnet Checklist (Code Hygiene / "Did We Forget Anything?")

**Date:** 2026-02-09

This checklist is focused on "codebase gotchas" before mainnet: mocks, placeholders, test-only wiring, accidental debug helpers, and deployment-script footguns.

## 0. Repo Hygiene (Before Any Mainnet Run)

- [ ] `git status` is clean (no accidental local edits going to mainnet).
- [ ] No secrets are tracked: `.env`, private keys, API keys (should be gitignored).
- [x] Build artifacts are not tracked: `cache/`, `out/`, `broadcast/**/dry-run/` (covered by .gitignore).

## 1. Quick "No Mocks / No Debug" Scans

- [x] No mock contracts in production sources (`rg -n "contract\s+Mock" src` returns nothing).
- [x] No test cheatcode usage in production sources (`rg -nF "vm." src` returns nothing).
- [x] No Forge console in production sources (`rg -nF "console2.log" src` returns nothing).
- [x] TODO/FIXME/HACK are understood and acceptable:
  - `src/libs/ERC20.sol` (comment-only TODO about hash value)
  - `script/utils/FindActiveFarms.s.sol` (optional utility script TODO)

## 2. Placeholder Address Footguns (Must Be Eliminated)

- [ ] YieldManager is not left with placeholder adapters (`address(1)` / `address(2)`).
  - `DeployAll.s.sol` deploys with placeholders but wires real adapters in the same script.
  - `VerifyDeployment.s.sol` checks for non-placeholder adapters. **Run it.**
- [x] `LP_PAIR_ADDRESS` hard-reverts on mainnet chain 80094 if missing or without code.
- [x] `MERKLE_ROOT` hard-reverts on mainnet chain 80094 if placeholder.
- [x] `MULTISIG_ADDRESS` hard-reverts on mainnet chain 80094 if zero.

## 3. External Dependencies (No "Oops Wrong Address")

- [ ] All external addresses point to **mainnet** contracts and have code (`extcodesize > 0`):
  - [ ] iBGT token: `0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b`
  - [ ] HONEY token: `0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce`
  - [ ] Infrared vault: `0x75F3Be06b02E235f6d0E7EF2D462b29739168301`
  - [ ] Kodiak router: `0xd91dd58387Ccd9B66B390ae2d7c66dBD46BC6022`
  - [ ] Kodiak factory: `0x5e705e184d233ff2a7cb1553793464a9d0c3028f`
  - [ ] APIARY/HONEY LP pair (created post-deploy on Kodiak)
- [ ] iBGT/USD oracle (RedStone): `0x243507C8C114618d7C8AD94b51118dB7b4e32ECe`
  - [ ] Implements `IAggregatorV3` (`latestRoundData` + `decimals`)
  - [ ] Returns valid (non-zero, non-negative) price
  - [ ] `updatedAt` is within staleness threshold (default 1 hour)
  - [ ] Fork test `MainnetFork.t.sol` verifies all of the above

## 4. Deployment Script Safety Checks

- [ ] `DeployAll.s.sol` run completes all 17 steps (no silent skips).
- [ ] Post-deploy: `VerifyDeployment.s.sol` passes end-to-end on target RPC.
- [x] Contract sizes are safe (EIP-170 24KB limit):
  - ApiaryBondDepository: 13,498 B (11 KB margin)
  - ApiaryKodiakAdapter: 16,767 B (7.8 KB margin)
  - ApiaryYieldManager: 16,634 B (7.9 KB margin)
  - All others: well under limit

## 5. Access Control / Admin Hygiene (Post-Deploy)

- [ ] Step 17 of `DeployAll.s.sol` initiates ownership transfer to multisig.
- [ ] Multisig calls `acceptOwnership()` on each Ownable2Step contract:
  - [ ] Treasury
  - [ ] Staking
  - [ ] sApiary
  - [ ] iBGT Bond Depository
  - [ ] LP Bond Depository
  - [ ] Pre-Sale Bond
  - [ ] Yield Manager
  - [ ] Infrared Adapter
  - [ ] Kodiak Adapter
- [ ] Deployer renounces APIARY `DEFAULT_ADMIN_ROLE` (script: `AcceptOwnership.s.sol`).
- [ ] YieldManager `keeper` is set to the intended ops address.

Use `script/deployment/AcceptOwnership.s.sol` for the multisig acceptance + deployer renounce steps.

## 6. "Not In Code" Items (Confirm Intentionally Missing)

These were described in the project docs/PDF but are not implemented as on-chain logic in this repo. Confirm you are OK shipping without them (or track them as separate deliverables).

- [ ] Phase 3 PoL specifics (reward vault bribing, vBGT conversion/staking, subvalidator launch, management fee routing) are not implemented (Phase 3 is currently a placeholder in YieldManager).
- [ ] Phase exit criteria enforcement (LP depth/TVL thresholds, 1-month fallback rule) is not on-chain.
- [ ] Special pre-bond features (DAO matching-purchase escrow + slashing, non-withdrawable NFT-treasury staking, NFT buy/burn flows, raffles) are not on-chain.
- [ ] Automatic BCV/discount adjustment based on demand is intentionally off-chain (admin calls `setBondTerms()` or a keeper bot does it).

**Previously missing, now implemented:**
- [x] Daily issuance cap: 3% of total APIARY supply per day (on-chain in BondDepository via `_checkAndUpdateDailyIssuance`).
- [x] Treasury-value-based max bond: `maxPayout()` now uses 1% of treasury value (with allocation-based fallback).

## 7. Final Build/Test Gates (Before Mainnet Broadcast)

- [x] `forge test` — 438 passed, 0 failed
- [ ] `forge test --gas-report` (spot-check: bond deposit, redeemAll, yield execution)
- [ ] Fork test `test/integration/MainnetFork.t.sol` passes against Berachain mainnet RPC
