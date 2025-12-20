# Apiary Protocol Deployment Checklist

## Pre-Deployment Preparation

### 1. Environment Setup
- [ ] Copy `.env.example` to `.env`
- [ ] Fill in all required environment variables
- [ ] Verify RPC_URL is correct (mainnet/testnet)
- [ ] Verify DEPLOYER_ADDRESS has sufficient BERA for gas
- [ ] Verify MULTISIG_ADDRESS is a Gnosis Safe or similar
- [ ] Never commit `.env` to version control

### 2. External Dependencies
- [ ] iBGT token address verified on Berachain
- [ ] HONEY token address verified
- [ ] Infrared staking contract address verified
- [ ] Kodiak router address verified
- [ ] Kodiak factory address verified

### 3. LP Token Creation
- [ ] Create APIARY/HONEY pair on Kodiak (if not exists)
- [ ] Add initial liquidity to APIARY/HONEY pool
- [ ] Save APIARY_HONEY_LP address to `.env`
- [ ] Verify LP token has liquidity

### 4. Pre-Sale Whitelist
- [ ] Generate merkle tree from whitelist addresses
- [ ] Calculate merkle root
- [ ] Save MERKLE_ROOT to `.env`
- [ ] Keep merkle tree JSON for users to generate proofs

### 5. Code Preparation
- [ ] Run all tests: `forge test`
- [ ] Check code coverage: `forge coverage`
- [ ] Run static analysis: `slither .`
- [ ] Review all TODO comments
- [ ] Update contract documentation

---

## Testnet Deployment

### 1. Deploy to Bepolia Testnet
```bash
# Deploy all contracts
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

- [ ] All 12 contracts deployed successfully
- [ ] All contracts verified on block explorer
- [ ] Save all deployed addresses

### 2. Configure Protocol
```bash
# Wire all contracts together
forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

- [ ] sAPIARY initialized with staking contract
- [ ] Warmup contract set in staking
- [ ] APIARY minting allocations set
- [ ] Treasury depositors configured
- [ ] Yield manager set in treasury
- [ ] Adapters set in yield manager
- [ ] Bond terms configured
- [ ] Ownership transferred to multisig

### 3. Verify Deployment
```bash
# Run verification checks
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL
```

- [ ] All verification checks passed
- [ ] No failed checks in output
- [ ] Review verification report

### 4. Multisig Ownership Acceptance
- [ ] Multisig accepts ownership of Treasury
- [ ] Multisig accepts ownership of iBGT Bond
- [ ] Multisig accepts ownership of LP Bond
- [ ] Multisig accepts ownership of Pre-Sale
- [ ] Multisig accepts ownership of Yield Manager
- [ ] Multisig accepts ownership of Infrared Adapter
- [ ] Multisig accepts ownership of Kodiak Adapter
- [ ] Verify deployer has no admin access

### 5. Testnet Testing
- [ ] Test staking: Stake APIARY → Receive sAPIARY
- [ ] Test unstaking: Unstake sAPIARY → Receive APIARY
- [ ] Test iBGT bonding: Bond iBGT → Receive vested APIARY
- [ ] Test LP bonding: Bond LP → Receive vested APIARY
- [ ] Test pre-sale: Purchase APIARY with HONEY
- [ ] Test pre-sale vesting: Claim vested APIARY
- [ ] Test yield execution: Execute yield strategy
- [ ] Test emergency pause
- [ ] Test emergency withdrawal
- [ ] Test all admin functions from multisig

### 6. Security Checks
- [ ] Verify no single point of failure
- [ ] Verify multisig controls all admin functions
- [ ] Verify deployer has no residual permissions
- [ ] Check for unclaimed tokens in contracts
- [ ] Verify all token approvals are correct
- [ ] Test reentrancy protection
- [ ] Test access control on all functions

---

## Mainnet Deployment

### 1. Final Preparation
- [ ] All testnet testing completed successfully
- [ ] Security audit completed (recommended)
- [ ] Community review period completed
- [ ] Documentation finalized
- [ ] Deployment plan reviewed by team
- [ ] Multisig signers ready and available
- [ ] Gas price acceptable for deployment

### 2. Deploy to Mainnet
```bash
# Use --slow flag for mainnet safety
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --slow \
  --broadcast \
  --verify
```

- [ ] All contracts deployed successfully
- [ ] All contracts verified on block explorer
- [ ] Save deployment transaction hashes
- [ ] Save all contract addresses
- [ ] Update frontend with contract addresses

### 3. Configure Mainnet Protocol
```bash
forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --slow \
  --broadcast
```

- [ ] Configuration completed successfully
- [ ] Ownership transferred to multisig
- [ ] Save configuration transaction hash

### 4. Verify Mainnet Deployment
```bash
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $MAINNET_RPC_URL
```

- [ ] All verification checks passed
- [ ] Generate verification report
- [ ] Share report with team

### 5. Multisig Actions
- [ ] All signers verify contract addresses
- [ ] Accept ownership of all contracts
- [ ] Verify deployer has zero permissions
- [ ] Set initial bond terms (if not default)
- [ ] Start pre-sale when ready
- [ ] Enable trading on Kodiak

### 6. Post-Deployment
- [ ] Update website with contract addresses
- [ ] Update documentation
- [ ] Announce deployment to community
- [ ] Monitor first transactions
- [ ] Set up monitoring/alerting
- [ ] Monitor contract events
- [ ] Prepare incident response plan

---

## Emergency Procedures

### If Deployment Fails Mid-Way
1. Stop immediately - DO NOT continue
2. Document which contracts were deployed
3. Note which step failed
4. Review error messages
5. DO NOT send any transactions until issue resolved
6. Consult team before proceeding

### If Configuration Fails
1. Stop immediately
2. Check which configurations succeeded
3. Contracts may need re-deployment
4. Do not accept multisig ownership until all configs pass

### If Verification Checks Fail
1. DO NOT proceed to production
2. Identify failed checks
3. Fix configuration issues
4. Re-run verification
5. Only proceed when all checks pass

---

## Rollback Plan

### If Critical Issue Found After Deployment
1. Multisig pauses all contracts immediately
2. Emergency withdrawal of user funds (if applicable)
3. Communicate issue to community
4. Fix contracts
5. Re-deploy if necessary
6. Migration plan for existing users

---

## Monitoring Setup

### Post-Deployment Monitoring
- [ ] Set up contract event monitoring
- [ ] Set up error/revert monitoring
- [ ] Set up TVL tracking
- [ ] Set up yield distribution tracking
- [ ] Set up bond metrics tracking
- [ ] Set up gas usage alerts
- [ ] Set up unusual transaction alerts

---

## Documentation Updates

### After Successful Deployment
- [ ] Update README with contract addresses
- [ ] Update developer documentation
- [ ] Update user guides
- [ ] Create deployment report
- [ ] Archive deployment artifacts
- [ ] Update audit report (if applicable)

---

## Sign-Off

**Testnet Deployment**
- Deployed by: _________________ Date: _________________
- Verified by: _________________ Date: _________________

**Mainnet Deployment**
- Deployed by: _________________ Date: _________________
- Verified by: _________________ Date: _________________
- Multisig confirmed by: _________________ Date: _________________

---

**Notes:**
- Keep this checklist with deployment artifacts
- Update with any deployment-specific notes
- Share with auditors/security team
