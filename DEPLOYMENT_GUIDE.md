# Apiary Protocol Deployment Guide

Complete guide for deploying the Apiary protocol to Berachain mainnet or testnet using Foundry.

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Deployment Architecture](#deployment-architecture)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Configuration](#configuration)
6. [Verification](#verification)
7. [Post-Deployment](#post-deployment)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)

---

## Overview

The Apiary protocol consists of 12 main contracts:

**Core Contracts:**
- ApiaryToken (APIARY) - Main protocol token
- sApiary (sAPIARY) - Staked APIARY token
- ApiaryStaking - Staking mechanism
- ApiaryStakingWarmup - Warmup period for staking
- ApiaryTreasury - Protocol treasury

**Bond Contracts:**
- ApiaryBondDepository (iBGT) - iBGT bonds
- ApiaryBondDepository (LP) - LP token bonds
- ApiaryPreSaleBond - Pre-sale mechanism
- ApiaryUniswapV2TwapOracle - TWAP oracle for pricing

**Yield Management:**
- ApiaryYieldManager - Main yield distribution logic
- ApiaryInfraredAdapter - Infrared staking adapter
- ApiaryKodiakAdapter - Kodiak DEX adapter

---

## Prerequisites

### 1. Development Environment

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
forge --version
cast --version
```

### 2. Dependencies

```bash
# Clone repository
git clone <repository-url>
cd apiary-contracts

# Install dependencies
forge install

# Build contracts
forge build
```

### 3. Required Information

Before deploying, gather:

- **RPC URL**: Berachain mainnet or Bepolia testnet RPC
- **Explorer API Key**: For contract verification
- **Deployer Private Key**: Account with sufficient BERA for gas
- **Multisig Address**: Gnosis Safe or similar for protocol ownership
- **DAO Address**: Address to receive bond fees
- **External Addresses**:
  - iBGT token address
  - HONEY token address
  - Infrared staking contract
  - Kodiak router and factory
  - APIARY/HONEY LP token (create beforehand)

---

## Deployment Architecture

### Deployment Order

The contracts must be deployed in this specific order due to dependencies:

```
1. APIARY Token
   ↓
2. sAPIARY Token
   ↓
3. Treasury
   ↓
4. Staking & Warmup
   ↓
5. TWAP Oracle → Bonds (iBGT, LP, Pre-Sale)
   ↓
6. Adapters → Yield Manager
   ↓
7. Configuration (wire everything together)
```

### Contract Dependencies

```
APIARY Token
├── Treasury (mints APIARY)
├── Pre-Sale (mints APIARY)
├── iBGT Bond (mints APIARY)
└── LP Bond (mints APIARY)

sAPIARY Token
├── Staking (mints/burns sAPIARY)
└── Warmup (holds sAPIARY)

Treasury
├── Yield Manager (borrows iBGT)
├── Bond Contracts (deposit reserves)
└── APIARY Token (receives minting rights)

Yield Manager
├── Infrared Adapter (stakes iBGT)
├── Kodiak Adapter (swaps & adds liquidity)
└── Treasury (borrows/repays iBGT)
```

---

## Step-by-Step Deployment

### Phase 1: Environment Setup

#### 1.1 Create Environment File

```bash
cp .env.example .env
```

#### 1.2 Fill in Required Variables

Edit `.env` with your values:

```bash
# Network
RPC_URL=https://rpc.berachain.com
ETHERSCAN_API_KEY=your_api_key

# Deployer
PRIVATE_KEY=0x...
DEPLOYER_ADDRESS=0x...

# Governance
MULTISIG_ADDRESS=0x...  # Gnosis Safe
DAO_ADDRESS=0x...       # Fee recipient

# Berachain Addresses
IBGT_ADDRESS=0x...
HONEY_ADDRESS=0x...
INFRARED_STAKING=0x...

# Kodiak DEX
KODIAK_ROUTER=0x...
KODIAK_FACTORY=0x...
APIARY_HONEY_LP=0x...  # Create this first!

# Staking Config
EPOCH_LENGTH=28800       # 8 hours at 1s/block
FIRST_EPOCH_NUMBER=0
FIRST_EPOCH_BLOCK=<current_block + EPOCH_LENGTH>

# Pre-Sale
MERKLE_ROOT=0x...        # Generate from whitelist
```

#### 1.3 Create APIARY/HONEY LP Token

Before deployment, you need to create the LP token:

```bash
# Option 1: Using Kodiak UI
# 1. Go to Kodiak DEX
# 2. Create new pair: APIARY/HONEY
# 3. Add initial liquidity
# 4. Copy LP token address to .env

# Option 2: Using cast (after APIARY deployed)
cast send $KODIAK_FACTORY "createPair(address,address)" \
  $APIARY_ADDRESS $HONEY_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

---

### Phase 2: Contract Deployment

You can deploy contracts individually or all at once.

#### Option A: Deploy All Contracts (Recommended)

```bash
# Deploy entire protocol in one command
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv

# For mainnet, add --slow flag
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --slow \
  --broadcast \
  --verify \
  -vvvv
```

This will:
- Deploy all 12 contracts in correct order
- Save addresses to console output
- Verify contracts on block explorer
- Log deployment summary

#### Option B: Deploy Individually

If you need more control or deployment fails mid-way:

```bash
# 1. Deploy APIARY Token
forge script script/deployment/01_DeployToken.s.sol:DeployToken \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 2. Deploy sAPIARY Token
forge script script/deployment/02_DeploysApiary.s.sol:DeploysApiary \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 3. Deploy Treasury
forge script script/deployment/03_DeployTreasury.s.sol:DeployTreasury \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 4. Deploy Staking & Warmup
forge script script/deployment/04_DeployStaking.s.sol:DeployStaking \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 5. Deploy Bonds & Oracle
forge script script/deployment/05_DeployBonds.s.sol:DeployBonds \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 6. Deploy Yield Manager & Adapters
forge script script/deployment/06_DeployYieldManager.s.sol:DeployYieldManager \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

After each deployment, update `.env` with the deployed address before proceeding.

---

### Phase 3: Configuration

After all contracts are deployed, wire them together:

```bash
forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

This configuration script:

1. ✅ Initializes sAPIARY with staking contract
2. ✅ Sets warmup contract in staking
3. ✅ Sets APIARY minting allocations:
   - Treasury: 40,000 APIARY (20%)
   - Pre-Sale: 10,000 APIARY (5%)
   - iBGT Bond: 30,000 APIARY (15%)
   - LP Bond: 30,000 APIARY (15%)
4. ✅ Configures treasury depositors
5. ✅ Sets yield manager in treasury
6. ✅ Updates yield manager adapters
7. ✅ Configures default bond terms
8. ✅ Transfers ownership to multisig

**IMPORTANT**: After this step, deployer loses admin access!

---

### Phase 4: Verification

Verify the deployment is correct:

```bash
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL \
  -vvvv
```

The verification script checks:
- ✅ All contract references are correct
- ✅ All cross-contract integrations work
- ✅ Permissions and roles are properly set
- ✅ Allocation limits are configured
- ✅ Bond terms are set
- ✅ Ownership transferred to multisig

**Expected Output:**
```
=== VERIFICATION SUMMARY ===
Passed: 45
Failed: 0
Total: 45

✓✓✓ ALL CHECKS PASSED ✓✓✓
Protocol is correctly configured and ready for production!
```

If any checks fail, **DO NOT PROCEED** until issues are resolved.

---

## Configuration

### Minting Allocations

Default allocations (total 90% of 200k supply = 180k APIARY):

| Contract | Allocation | Percentage |
|----------|-----------|------------|
| Treasury | 40,000 APIARY | 20% |
| Pre-Sale | 10,000 APIARY | 5% |
| iBGT Bond | 30,000 APIARY | 15% |
| LP Bond | 30,000 APIARY | 15% |
| **Total** | **110,000** | **55%** |

Remaining 90,000 APIARY (45%) can be minted for:
- Team allocation
- Marketing
- Liquidity provision
- Community incentives

### Bond Terms

Default bond configuration:

```solidity
Vesting Term: 129,600 blocks (~36 hours at 1s/block)
Discount Rate: 500 (5% discount)
Max Debt: 50,000 APIARY
```

To modify bond terms:

```bash
# Connect with multisig
cast send $IBGT_BOND_ADDRESS \
  "setBondTerms(uint8,uint256)" \
  0 <NEW_VESTING_TERM> \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

### Yield Manager Configuration

Default Phase 1 configuration (25/25/50):

```solidity
Strategy: PHASE1_LP_BURN
Split Config:
  - To HONEY: 2500 (25%)
  - To APIARY LP: 5000 (50%)
  - To Burn: 2500 (25%)
Slippage Tolerance: 50 bps (0.5%)
Min Yield: 0.1 iBGT
Max Execution: 10,000 iBGT
```

To change strategy:

```bash
# Switch to Phase 2 (require multisig)
cast send $YIELD_MANAGER_ADDRESS \
  "setStrategy(uint8)" \
  1 \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

---

## Verification

### Manual Contract Verification

If auto-verification fails:

```bash
# Verify APIARY Token
forge verify-contract \
  $APIARY_ADDRESS \
  src/ApiaryToken.sol:ApiaryToken \
  --chain-id <CHAIN_ID> \
  --constructor-args $(cast abi-encode "constructor(address)" $DEPLOYER_ADDRESS) \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Verify sAPIARY Token
forge verify-contract \
  $SAPIARY_ADDRESS \
  src/sApiary.sol:sApiary \
  --chain-id <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Continue for all contracts...
```

---

## Post-Deployment

### 1. Multisig Ownership Acceptance

All contracts use `Ownable2Step`, requiring multisig to accept ownership:

```bash
# For each contract, multisig must call:
cast send $TREASURY_ADDRESS \
  "acceptOwnership()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY

# Repeat for:
# - TREASURY_ADDRESS
# - IBGT_BOND_ADDRESS
# - LP_BOND_ADDRESS
# - PRESALE_ADDRESS
# - YIELD_MANAGER_ADDRESS
# - INFRARED_ADAPTER_ADDRESS
# - KODIAK_ADAPTER_ADDRESS
```

### 2. Start Pre-Sale

```bash
# Set TGE (Token Generation Event) time
cast send $PRESALE_ADDRESS \
  "startTge()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY

# Start pre-sale
cast send $PRESALE_ADDRESS \
  "startPreSaleBond()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

### 3. Enable Bonding

Bonds are enabled by default after configuration. To adjust:

```bash
# Pause bonding if needed
cast send $IBGT_BOND_ADDRESS \
  "pause()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY

# Unpause when ready
cast send $IBGT_BOND_ADDRESS \
  "unpause()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

### 4. Test Basic Functionality

```bash
# Test staking (requires APIARY balance)
cast send $STAKING_ADDRESS \
  "stake(uint256,address)" \
  1000000000 $USER_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $USER_PRIVATE_KEY

# Test bonding (requires iBGT balance)
cast send $IBGT_BOND_ADDRESS \
  "deposit(uint256,uint256,address)" \
  1000000000000000000 1000 $USER_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $USER_PRIVATE_KEY

# Test pre-sale (requires HONEY and whitelist)
cast send $PRESALE_ADDRESS \
  "purchaseApiary(uint256,bytes32[])" \
  1000000000 "[...]" \
  --rpc-url $RPC_URL \
  --private-key $USER_PRIVATE_KEY
```

### 5. Deploy Registry (Optional)

For easy address lookup:

```bash
forge create src/DeploymentRegistry.sol:DeploymentRegistry \
  --constructor-args \
    $APIARY_ADDRESS \
    $SAPIARY_ADDRESS \
    $STAKING_ADDRESS \
    $WARMUP_ADDRESS \
    $TREASURY_ADDRESS \
    $IBGT_BOND_ADDRESS \
    $LP_BOND_ADDRESS \
    $PRESALE_ADDRESS \
    $TWAP_ORACLE_ADDRESS \
    $YIELD_MANAGER_ADDRESS \
    $INFRARED_ADAPTER_ADDRESS \
    $KODIAK_ADAPTER_ADDRESS \
    $IBGT_ADDRESS \
    $HONEY_ADDRESS \
    $APIARY_HONEY_LP \
    $INFRARED_STAKING \
    $KODIAK_ROUTER \
    $KODIAK_FACTORY \
    $MULTISIG_ADDRESS \
    $DAO_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --verify
```

---

## Troubleshooting

### Common Issues

#### 1. "APIARY__ALLOCATION_LIMIT_ALREADY_SET"

**Cause**: Trying to set allocation limit twice for same address.

**Solution**: Allocation limits can only be set once. If you need to change, redeploy the contract.

#### 2. "APIARY__INVALID_ADDRESS" / Zero Address Errors

**Cause**: Missing or incorrect environment variable.

**Solution**: Double-check all addresses in `.env`:
```bash
# Verify addresses
cast call $APIARY_ADDRESS "totalSupply()(uint256)" --rpc-url $RPC_URL
```

#### 3. "Ownable: caller is not the owner"

**Cause**: Trying to call admin function after ownership transfer.

**Solution**: Use multisig to call admin functions after configuration.

#### 4. Verification Fails

**Cause**: Constructor arguments mismatch or network issues.

**Solution**:
```bash
# Get constructor args from deployment transaction
cast tx <DEPLOYMENT_TX_HASH> --rpc-url $RPC_URL

# Manually verify with correct args
forge verify-contract <ADDRESS> <CONTRACT> \
  --constructor-args $(cast abi-encode "constructor(...)" ...) \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

#### 5. "EvmError: Revert" During Deployment

**Cause**: Insufficient gas, incorrect parameters, or failed contract requirement.

**Solution**:
```bash
# Use -vvvvv for full trace
forge script <SCRIPT> -vvvvv --rpc-url $RPC_URL

# Check gas price
cast gas-price --rpc-url $RPC_URL

# Increase gas limit if needed
forge script <SCRIPT> --gas-limit 10000000 ...
```

#### 6. Adapters Not Working After Deployment

**Cause**: Yield Manager was deployed with placeholder adapter addresses.

**Solution**: Configuration script updates adapters. Verify:
```bash
cast call $YIELD_MANAGER_ADDRESS \
  "infraredAdapter()(address)" \
  --rpc-url $RPC_URL
```

---

## Security Considerations

### Pre-Deployment

1. ✅ **Audit Contracts**: Get professional security audit
2. ✅ **Test Coverage**: Ensure >95% test coverage
3. ✅ **Static Analysis**: Run Slither, Mythril
4. ✅ **Testnet Testing**: Test all functionality on testnet first
5. ✅ **Key Management**: Use hardware wallet for multisig
6. ✅ **Multisig Setup**: 3/5 or 4/7 multisig recommended

### During Deployment

1. ✅ **Verify Addresses**: Triple-check all addresses in `.env`
2. ✅ **Use --slow**: For mainnet deployments
3. ✅ **Monitor Gas**: Ensure sufficient BERA balance
4. ✅ **Save Artifacts**: Keep deployment transaction hashes
5. ✅ **Verify Contracts**: Ensure all contracts verified on explorer

### Post-Deployment

1. ✅ **Accept Ownership**: Multisig must accept ownership
2. ✅ **Revoke Deployer**: Verify deployer has no admin access
3. ✅ **Monitor Events**: Set up event monitoring
4. ✅ **Incident Response**: Have emergency pause plan ready
5. ✅ **Communication**: Announce deployment to community
6. ✅ **Documentation**: Update all documentation with addresses

### Emergency Procedures

If critical issue found:

1. **Pause Contracts**:
```bash
cast send $YIELD_MANAGER_ADDRESS "pause()" \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

2. **Emergency Withdrawal**:
```bash
cast send $TREASURY_ADDRESS \
  "emergencyWithdraw(address)" \
  $TOKEN_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_PRIVATE_KEY
```

3. **Communicate**: Inform community immediately

---

## Summary

### Deployment Checklist

- [ ] Environment setup complete
- [ ] All dependencies installed
- [ ] `.env` file configured
- [ ] LP token created
- [ ] Merkle root generated
- [ ] Testnet deployment successful
- [ ] Testnet testing complete
- [ ] Security audit complete (recommended)
- [ ] Mainnet deployment complete
- [ ] Configuration complete
- [ ] Verification checks passed
- [ ] Multisig ownership accepted
- [ ] Deployer access revoked
- [ ] Basic functionality tested
- [ ] Monitoring set up
- [ ] Documentation updated
- [ ] Community announced

### Key Commands Reference

```bash
# Deploy all
forge script script/deployment/DeployAll.s.sol:DeployAll --broadcast --verify

# Configure
forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol --broadcast

# Verify
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment

# Accept ownership (multisig)
cast send <CONTRACT> "acceptOwnership()"

# Start pre-sale (multisig)
cast send $PRESALE_ADDRESS "startPreSaleBond()"
```

---

## Support

For issues or questions:
- Review troubleshooting section
- Check deployment logs with `-vvvvv` flag
- Consult `DEPLOYMENT_CHECKLIST.md`
- Review test suite for expected behavior

**Good luck with your deployment! 🚀**
