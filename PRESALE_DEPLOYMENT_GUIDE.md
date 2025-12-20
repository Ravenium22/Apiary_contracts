# Apiary Pre-Sale Bond Deployment Guide

## 📋 Overview

This guide covers the complete deployment process for the Apiary pre-sale bond system, including:
- Contract deployment
- Merkle tree generation for whitelist
- State transitions
- Testing procedures
- Security considerations

---

## 🚀 Pre-Deployment Checklist

### 1. Environment Setup

```bash
# Install dependencies
npm install

# Compile contracts
forge build

# Run tests
forge test

# Check test coverage
forge coverage
```

### 2. Prepare Whitelist Data

Update `scripts/generateMerkleTree.js` with actual partner addresses:

```javascript
const WHITELIST_ADDRESSES = [
    // ===== PLUG ADDRESSES =====
    '0x...', // Plug team wallet 1
    '0x...', // Plug team wallet 2
    
    // ===== APDAO ADDRESSES =====
    '0x...', // ApDao team wallet 1
    '0x...', // ApDao community wallet
    
    // ===== YEETDAT ADDRESSES =====
    '0x...', // YeetDat team wallet
    
    // ===== BOOGABULLAS ADDRESSES =====
    '0x...', // BoogaBullas NFT holder 1
    '0x...', // BoogaBullas NFT holder 2
    // ... add all whitelisted addresses
];
```

### 3. Generate Merkle Tree

```bash
# Install dependencies
npm install merkletreejs keccak256 ethers

# Generate merkle tree
node scripts/generateMerkleTree.js

# Output: merkle-tree-output.json
# Contains:
# - merkleRoot (for contract deployment)
# - proofs (for frontend)
```

### 4. Verify Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| Total Allocation | 110,000 APIARY | 55% of 200k supply |
| Token Price | 0.25e18 HONEY | $0.25 per APIARY |
| Per-Wallet Limit | 500e9 APIARY | $125 at $0.25/token |
| Vesting Duration | 5 days | PRE_SALE_VESTING_DURATION |
| Payment Token | HONEY address | Berachain stablecoin |
| Treasury Address | Multi-sig | Receives HONEY payments |

---

## 📝 Deployment Steps

### Step 1: Deploy HONEY Token (if testnet)

**Skip this on mainnet if HONEY already exists**

```solidity
// For testnet only - deploy mock HONEY
forge create src/mocks/MockERC20.sol:MockERC20 \
    --constructor-args "HONEY" "HONEY" 18 \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY
```

### Step 2: Deploy Multi-Sig Treasury (Recommended)

```bash
# Option A: Gnosis Safe (Recommended)
# Deploy via Gnosis Safe UI: https://app.safe.global
# Configuration: 2-of-3 or 3-of-5 signers

# Option B: Simple multi-sig contract
forge create src/utils/MultiSigWallet.sol:MultiSigWallet \
    --constructor-args "[0xSigner1, 0xSigner2, 0xSigner3]" 2 \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY
```

### Step 3: Deploy ApiaryPreSaleBond

```bash
# Set environment variables
export HONEY_ADDRESS="0x..." # HONEY token address
export TREASURY_ADDRESS="0x..." # Multi-sig treasury address
export ADMIN_ADDRESS="0x..." # Admin wallet (can be multi-sig)
export MERKLE_ROOT="0x..." # From merkle-tree-output.json

# Deploy contract
forge create src/ApiaryPreSaleBond.sol:ApiaryPreSaleBond \
    --constructor-args $HONEY_ADDRESS $TREASURY_ADDRESS $ADMIN_ADDRESS $MERKLE_ROOT \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --verify
```

**Expected Output:**
```
Deployer: 0x...
Deployed to: 0xAbC123... (PRESALE_ADDRESS)
Transaction hash: 0x...
```

### Step 4: Verify Deployment

```bash
# Check deployed contract
cast call $PRESALE_ADDRESS "merkleRoot()(bytes32)" --rpc-url $BERACHAIN_RPC_URL
cast call $PRESALE_ADDRESS "treasury()(address)" --rpc-url $BERACHAIN_RPC_URL
cast call $PRESALE_ADDRESS "tokenPrice()(uint128)" --rpc-url $BERACHAIN_RPC_URL
cast call $PRESALE_ADDRESS "bondPurchaseLimit()(uint128)" --rpc-url $BERACHAIN_RPC_URL

# Expected outputs:
# merkleRoot: 0x... (matches merkle-tree-output.json)
# treasury: 0x... (matches TREASURY_ADDRESS)
# tokenPrice: 250000000000000000 (0.25e18)
# bondPurchaseLimit: 500000000000 (500e9)
```

---

## 🔧 Post-Deployment Configuration

### Step 5: Set APIARY Token Address

**After APIARY token is deployed**

```bash
export APIARY_TOKEN_ADDRESS="0x..." # ApiaryToken contract address

# Set APIARY token in pre-sale contract
cast send $PRESALE_ADDRESS \
    "setApiaryToken(address)" $APIARY_TOKEN_ADDRESS \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY
```

### Step 6: Optional Parameter Adjustments

```bash
# Adjust token price (if needed)
# Example: Set to $0.30 = 0.3e18
cast send $PRESALE_ADDRESS \
    "setTokenPrice(uint128)" 300000000000000000 \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Adjust per-wallet limit (if needed)
# Example: Set to 1,000 APIARY = 1000e9
cast send $PRESALE_ADDRESS \
    "setBondPurchaseLimit(uint128)" 1000000000000 \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Update merkle root (if whitelist changes)
export NEW_MERKLE_ROOT="0x..." # From updated merkle-tree-output.json
cast send $PRESALE_ADDRESS \
    "setMerkleRoot(bytes32)" $NEW_MERKLE_ROOT \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY
```

---

## 🎬 Starting the Pre-Sale

### Step 7: Start Pre-Sale (NotStarted → Live)

**Only call when ready for purchases**

```bash
# Transition to Live state
cast send $PRESALE_ADDRESS \
    "startPreSaleBond()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Verify state
cast call $PRESALE_ADDRESS "currentPreSaleBondState()(uint8)" --rpc-url $BERACHAIN_RPC_URL
# Expected: 1 (Live)
```

### Step 8: Monitor Pre-Sale

```bash
# Check total sold
cast call $PRESALE_ADDRESS "totalBondsSold()(uint128)" --rpc-url $BERACHAIN_RPC_URL

# Check available
cast call $PRESALE_ADDRESS "apiaryTokensAvailable()(uint256)" --rpc-url $BERACHAIN_RPC_URL

# Check HONEY raised
cast call $PRESALE_ADDRESS "totalHoneyRaised()(uint128)" --rpc-url $BERACHAIN_RPC_URL

# Check specific user allocation
cast call $PRESALE_ADDRESS \
    "investorAllocations(address)(uint128,uint128,uint48,uint48)" \
    0xUserAddress \
    --rpc-url $BERACHAIN_RPC_URL
```

---

## 🏁 Ending the Pre-Sale

### Step 9: End Pre-Sale (Live → Ended)

**Call when pre-sale period is complete**

```bash
# Transition to Ended state
cast send $PRESALE_ADDRESS \
    "endPreSaleBond()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Verify state
cast call $PRESALE_ADDRESS "currentPreSaleBondState()(uint8)" --rpc-url $BERACHAIN_RPC_URL
# Expected: 2 (Ended)
```

### Step 10: Mint APIARY to Contract

**Mint exactly totalBondsSold to contract for vesting distribution**

```bash
# Check total sold
export TOTAL_SOLD=$(cast call $PRESALE_ADDRESS "totalBondsSold()(uint128)" --rpc-url $BERACHAIN_RPC_URL)
echo "Total sold: $TOTAL_SOLD APIARY (9 decimals)"

# Mint APIARY to pre-sale contract
cast send $PRESALE_ADDRESS \
    "mintApiary()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Verify APIARY balance
cast call $APIARY_TOKEN_ADDRESS \
    "balanceOf(address)(uint256)" $PRESALE_ADDRESS \
    --rpc-url $BERACHAIN_RPC_URL
# Expected: Equal to totalBondsSold
```

### Step 11: Start TGE (Begin Vesting)

**Call when ready for users to start claiming**

```bash
# Set TGE start time (enables vesting)
cast send $PRESALE_ADDRESS \
    "setTgeStartTime()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Verify TGE started
cast call $PRESALE_ADDRESS "tgeStarted()(bool)" --rpc-url $BERACHAIN_RPC_URL
# Expected: true

cast call $PRESALE_ADDRESS "tgeStartTime()(uint48)" --rpc-url $BERACHAIN_RPC_URL
# Expected: Current block timestamp
```

---

## 🧪 Testing Procedures

### Test 1: Whitelist Verification

```bash
# Test address verification
node scripts/verifyMerkleProof.js 0xWhitelistedAddress

# Expected output:
# Testing address: 0x...
# Merkle root: 0x...
# Proof: [...]
# Verification: ✅ VALID
# On-chain verification: ✅ VALID
```

### Test 2: Purchase Flow (Testnet)

```javascript
// Frontend test script
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

const preSale = new ethers.Contract(PRESALE_ADDRESS, PRESALE_ABI, signer);
const honey = new ethers.Contract(HONEY_ADDRESS, ERC20_ABI, signer);

// 1. Approve HONEY
const honeyAmount = ethers.utils.parseUnits('100', 18); // 100 HONEY
await honey.approve(PRESALE_ADDRESS, honeyAmount);

// 2. Get merkle proof
const proof = merkleData.proofs[signer.address];

// 3. Purchase APIARY (with slippage protection)
const minApiary = ethers.utils.parseUnits('390', 9); // 390 APIARY min (2.5% slippage)
const tx = await preSale.purchaseApiary(honeyAmount, proof, minApiary);
await tx.wait();

console.log('Purchase successful!');
```

### Test 3: Vesting Claim (After TGE)

```javascript
// Wait for some vesting time to pass
// Example: 1 day after TGE = 20% vested

// Check vested amount
const vested = await preSale.vestedAmount(signer.address);
console.log('Vested:', ethers.utils.formatUnits(vested, 9), 'APIARY');

// Check unlocked (claimable) amount
const unlocked = await preSale.unlockedAmount(signer.address);
console.log('Unlocked:', ethers.utils.formatUnits(unlocked, 9), 'APIARY');

// Claim vested APIARY
const tx = await preSale.unlockApiary();
await tx.wait();

console.log('Claimed!');
```

---

## 🔒 Security Procedures

### Emergency Pause

```bash
# Pause contract (stops all purchases and unlocks)
cast send $PRESALE_ADDRESS \
    "pause()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Unpause when safe
cast send $PRESALE_ADDRESS \
    "unpause()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY
```

### Emergency Token Recovery

```bash
# Recover accidentally sent tokens
export TOKEN_ADDRESS="0x..." # Token to recover
export AMOUNT="1000000000000000000" # Amount in wei

cast send $PRESALE_ADDRESS \
    "clawBack(address,uint256)" $TOKEN_ADDRESS $AMOUNT \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY
```

### Transfer Ownership (Two-Step)

```bash
# Step 1: Propose new owner
export NEW_OWNER="0x..." # New multi-sig address

cast send $PRESALE_ADDRESS \
    "transferOwnership(address)" $NEW_OWNER \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Step 2: New owner accepts
cast send $PRESALE_ADDRESS \
    "acceptOwnership()" \
    --rpc-url $BERACHAIN_RPC_URL \
    --private-key $NEW_OWNER_PRIVATE_KEY
```

---

## 📊 Monitoring & Analytics

### Key Metrics to Track

```bash
# Real-time dashboard queries
while true; do
    echo "=== Apiary Pre-Sale Status ==="
    echo "Total Sold: $(cast call $PRESALE_ADDRESS 'totalBondsSold()(uint128)' --rpc-url $BERACHAIN_RPC_URL)"
    echo "Available: $(cast call $PRESALE_ADDRESS 'apiaryTokensAvailable()(uint256)' --rpc-url $BERACHAIN_RPC_URL)"
    echo "HONEY Raised: $(cast call $PRESALE_ADDRESS 'totalHoneyRaised()(uint128)' --rpc-url $BERACHAIN_RPC_URL)"
    echo "State: $(cast call $PRESALE_ADDRESS 'currentPreSaleBondState()(uint8)' --rpc-url $BERACHAIN_RPC_URL)"
    echo "========================="
    sleep 60
done
```

### Event Monitoring

```javascript
// Listen for purchase events
preSale.on('ApiaryPurchased', (user, apiaryAmount, honeyAmount, event) => {
    console.log(`Purchase: ${user}`);
    console.log(`  APIARY: ${ethers.utils.formatUnits(apiaryAmount, 9)}`);
    console.log(`  HONEY: ${ethers.utils.formatUnits(honeyAmount, 18)}`);
});

// Listen for unlock events
preSale.on('ApiaryUnlocked', (user, amount, event) => {
    console.log(`Unlock: ${user}`);
    console.log(`  Amount: ${ethers.utils.formatUnits(amount, 9)} APIARY`);
});
```

---

## 🐛 Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `APIARY__INVALID_PROOF` | User not whitelisted or wrong proof | Verify address in merkle tree, regenerate proof |
| `APIARY__PRE_SALE_NOT_LIVE` | Pre-sale not started or ended | Check state, call startPreSaleBond() |
| `APIARY__MAX_BOND_REACHED` | User exceeded limit | User maxed out allocation |
| `APIARY__APIARY_SOLD_OUT` | All 110k APIARY sold | Pre-sale complete |
| `APIARY__SLIPPAGE_EXCEEDED` | Price changed before tx | Increase minApiaryAmount tolerance |
| `APIARY__TGE_NOT_STARTED` | Trying to claim before TGE | Wait for admin to call setTgeStartTime() |

### Debug Commands

```bash
# Check contract state
cast call $PRESALE_ADDRESS "currentPreSaleBondState()(uint8)"
# 0 = NotStarted, 1 = Live, 2 = Ended

# Check if whitelist enabled
cast call $PRESALE_ADDRESS "isWhitelistEnabled()(bool)"

# Verify merkle root
cast call $PRESALE_ADDRESS "merkleRoot()(bytes32)"

# Check user allocation
cast call $PRESALE_ADDRESS \
    "investorAllocations(address)" \
    0xUserAddress

# Test whitelist verification
cast call $PRESALE_ADDRESS \
    "isWhitelisted(address,bytes32[])(bool)" \
    0xUserAddress \
    "[0xProof1, 0xProof2, ...]"
```

---

## 📚 Additional Resources

- [OpenZeppelin Contracts Documentation](https://docs.openzeppelin.com/contracts/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Merkle Tree Explanation](https://en.wikipedia.org/wiki/Merkle_tree)
- [Berachain Documentation](https://docs.berachain.com/)

---

## ✅ Final Checklist

Before mainnet deployment:

- [ ] Merkle tree generated with all partner addresses
- [ ] All addresses verified by partners (Plug, ApDao, YeetDat, BoogaBullas)
- [ ] Multi-sig treasury deployed and tested
- [ ] Contract deployed with correct constructor parameters
- [ ] APIARY token address set
- [ ] Token price verified ($0.25 = 0.25e18)
- [ ] Per-wallet limit verified (500e9 APIARY)
- [ ] Merkle root matches merkle-tree-output.json
- [ ] Test purchases completed on testnet
- [ ] Test vesting/claiming completed on testnet
- [ ] Emergency pause tested
- [ ] Ownership transferred to multi-sig
- [ ] Professional audit completed
- [ ] Frontend integration tested
- [ ] Documentation provided to users
- [ ] Monitoring dashboard set up

---

**Deployment Complete! 🎉**

Start the pre-sale when ready with `startPreSaleBond()`
