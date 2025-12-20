# Apiary Pre-Sale Bond System

Complete whitelisted pre-sale system for Apiary protocol with merkle tree verification and linear vesting.

---

## 📦 What's Included

### Smart Contracts

| File | Description |
|------|-------------|
| `src/ApiaryPreSaleBond.sol` | Main pre-sale contract with whitelist verification and vesting |
| `src/interfaces/IApiaryPreSaleBond.sol` | Interface for pre-sale contract |

### Scripts & Tools

| File | Description |
|------|-------------|
| `scripts/generateMerkleTree.js` | Generate merkle tree from whitelist addresses |
| `scripts/verifyMerkleProof.js` | Frontend examples for proof verification |
| `PRESALE_DEPLOYMENT_GUIDE.md` | Complete deployment walkthrough |

---

## 🎯 Key Features

### ✅ Whitelist System
- **Merkle proof based** - Cryptographically secure, gas-efficient
- **Partners included**: Plug, ApDao, YeetDat, BoogaBullas
- **Admin updatable** - Can update whitelist before sale starts
- **Optional toggle** - Can disable whitelist for public sale

### ✅ Fair Allocation
- **Total Supply**: 110,000 APIARY (55% of 200k total)
- **Per-Wallet Limit**: 500 APIARY ($125 at $0.25/token)
- **Automatic Refunds**: Excess HONEY returned if limit exceeded
- **Sold-Out Protection**: Last buyers get remaining amount + refund

### ✅ Secure Vesting
- **Linear Vesting**: 5 days from TGE
- **Claim Anytime**: Users can claim proportionally before full vest
- **No Manipulation**: Timestamp-based, cannot be gamed
- **State Tracking**: Prevents double-claiming

### ✅ Security Features
- **ReentrancyGuard**: Prevents reentrancy attacks ✨ **ADDED**
- **Slippage Protection**: Users set minimum APIARY to receive ✨ **ADDED**
- **Pausable**: Emergency stop capability
- **Ownable2Step**: Prevents accidental ownership loss
- **One-Way States**: Cannot revert from Ended to Live
- **Immediate Treasury Transfer**: HONEY never stuck in contract

---

## 📊 Pre-Sale Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Total Allocation** | 110,000 APIARY | 55% of total supply |
| **Token Price** | $0.25 per APIARY | $50k market cap / 200k supply |
| **Market Cap** | $50,000 | Initial valuation |
| **Payment Token** | HONEY | Berachain stablecoin |
| **Per-Wallet Limit** | 500 APIARY | $125 maximum per wallet |
| **Vesting Period** | 5 days | Linear from TGE |
| **Max Raise** | $27,500 HONEY | 110,000 × $0.25 |

---

## 🚀 Quick Start

### 1. Generate Whitelist Merkle Tree

```bash
# Install dependencies
npm install merkletreejs keccak256 ethers

# Update whitelist addresses in scripts/generateMerkleTree.js
# Then run:
node scripts/generateMerkleTree.js

# Output: merkle-tree-output.json
# - merkleRoot (for deployment)
# - proofs (for frontend)
```

### 2. Deploy Contract

```bash
# Set environment variables
export HONEY_ADDRESS="0x..." # HONEY token
export TREASURY_ADDRESS="0x..." # Multi-sig treasury
export ADMIN_ADDRESS="0x..." # Admin wallet
export MERKLE_ROOT="0x..." # From merkle-tree-output.json

# Deploy
forge create src/ApiaryPreSaleBond.sol:ApiaryPreSaleBond \
    --constructor-args $HONEY_ADDRESS $TREASURY_ADDRESS $ADMIN_ADDRESS $MERKLE_ROOT \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify
```

### 3. Configure & Start

```bash
# Set APIARY token address
cast send $PRESALE_ADDRESS "setApiaryToken(address)" $APIARY_TOKEN \
    --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Start pre-sale (NotStarted → Live)
cast send $PRESALE_ADDRESS "startPreSaleBond()" \
    --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

### 4. After Pre-Sale Ends

```bash
# End pre-sale (Live → Ended)
cast send $PRESALE_ADDRESS "endPreSaleBond()" \
    --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Mint APIARY to contract
cast send $PRESALE_ADDRESS "mintApiary()" \
    --rpc-url $RPC_URL --private-key $ADMIN_KEY

# Start TGE (enable vesting)
cast send $PRESALE_ADDRESS "setTgeStartTime()" \
    --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

---

## 💻 Frontend Integration

### Check Whitelist Status

```javascript
import { ethers } from 'ethers';
import merkleData from './merkle-tree-output.json';

async function checkWhitelist(userAddress) {
    const checksumAddress = ethers.utils.getAddress(userAddress);
    
    // Check if in whitelist
    if (!merkleData.addresses.includes(checksumAddress)) {
        return { whitelisted: false, proof: null };
    }
    
    // Get proof for this address
    const proof = merkleData.proofs[checksumAddress];
    
    return { whitelisted: true, proof };
}
```

### Purchase APIARY

```javascript
const { whitelisted, proof } = await checkWhitelist(userAddress);

if (!whitelisted) {
    alert('You are not whitelisted!');
    return;
}

const preSale = new ethers.Contract(PRESALE_ADDRESS, PRESALE_ABI, signer);
const honey = new ethers.Contract(HONEY_ADDRESS, ERC20_ABI, signer);

// 1. Approve HONEY
const honeyAmount = ethers.utils.parseUnits('100', 18); // 100 HONEY
await honey.approve(PRESALE_ADDRESS, honeyAmount);

// 2. Purchase with slippage protection
// Expect ~400 APIARY, allow 2.5% slippage
const minApiary = ethers.utils.parseUnits('390', 9);
const tx = await preSale.purchaseApiary(honeyAmount, proof, minApiary);
await tx.wait();

console.log('Purchase successful!');
```

### Claim Vested APIARY

```javascript
// Check vested amount
const vested = await preSale.vestedAmount(userAddress);
const unlocked = await preSale.unlockedAmount(userAddress);

console.log('Total vested:', ethers.utils.formatUnits(vested, 9), 'APIARY');
console.log('Claimable:', ethers.utils.formatUnits(unlocked, 9), 'APIARY');

// Claim
const tx = await preSale.unlockApiary();
await tx.wait();
```

---

## 🔐 Security Improvements ✨ NEW

### Added Features

1. **ReentrancyGuard**
   - Prevents reentrancy attacks on `purchaseApiary()` and `unlockApiary()`
   - Uses OpenZeppelin's battle-tested implementation

2. **Slippage Protection**
   - New `minApiaryAmount` parameter in `purchaseApiary()`
   - Reverts if calculated APIARY < minimum
   - Protects against front-running and price changes

### Example Usage

```solidity
// Before (vulnerable to front-running)
preSale.purchaseApiary(honeyAmount, proof);

// After (protected)
preSale.purchaseApiary(honeyAmount, proof, minApiaryAmount);
```

---

## 📖 Documentation

### For Developers
- **Deployment Guide**: `PRESALE_DEPLOYMENT_GUIDE.md` - Complete walkthrough
- **Security Analysis**: See inline documentation for attack vectors
- **Code Comments**: Extensive NatSpec documentation in contracts

### For Frontend Teams
- **Merkle Proof Examples**: `scripts/verifyMerkleProof.js`
  - React hooks
  - Vue.js components
  - Wagmi/Viem integration
  - API endpoints

### For Auditors
- **Security Checklist**: See deployment guide
- **Test Coverage**: Run `forge coverage`
- **Known Issues**: Sybil attack via multiple wallets (mitigated by whitelist curation)

---

## 🧪 Testing

### Run Tests

```bash
# Compile
forge build

# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testPurchaseApiary

# Coverage report
forge coverage
```

### Test Scenarios Covered

- ✅ Whitelist verification (valid/invalid proofs)
- ✅ Purchase flow (normal, over limit, sold out)
- ✅ Refund mechanism (exceeding limit/supply)
- ✅ Vesting calculations (linear over 5 days)
- ✅ State transitions (NotStarted → Live → Ended)
- ✅ Emergency pause/unpause
- ✅ Reentrancy protection
- ✅ Slippage protection

---

## 🎯 User Journey

### 1. Pre-Sale Phase

```
User → Check whitelist → Approve HONEY → Purchase APIARY
  ↓
Contract verifies proof → Calculates payout → Sends HONEY to treasury
  ↓
User receives APIARY allocation (vesting)
```

### 2. Vesting Phase (After TGE)

```
Day 0: 0% vested
Day 1: 20% vested  ← User can claim
Day 2: 40% vested  ← User can claim
Day 3: 60% vested  ← User can claim
Day 4: 80% vested  ← User can claim
Day 5: 100% vested ← Fully unlocked
```

### 3. Claiming

```
User → Call unlockApiary() → Receive vested APIARY
  ↓
Can claim multiple times (each time gets newly vested amount)
```

---

## ⚠️ Important Notes

### Before Mainnet Launch

- [ ] **Get professional audit** (OpenZeppelin, Trail of Bits, etc.)
- [ ] **Deploy with multi-sig** as owner (2-of-3 or 3-of-5)
- [ ] **Test on testnet** with real partner addresses
- [ ] **Verify merkle tree** with all partners
- [ ] **Set up monitoring** for suspicious activity
- [ ] **Prepare emergency procedures** (pause, recovery)

### During Pre-Sale

- Monitor `totalBondsSold` vs target
- Watch for Sybil attack patterns (many wallets, similar amounts)
- Be ready to pause if issues detected
- Track HONEY flow to treasury

### After Pre-Sale

- Verify `totalBondsSold` equals APIARY minted
- Double-check TGE start time before setting
- Monitor vesting claims for anomalies
- Keep clawBack as last resort only

---

## 📞 Support

### For Issues
- Check `PRESALE_DEPLOYMENT_GUIDE.md` troubleshooting section
- Review security analysis in deployment guide
- Test on testnet before reporting bugs

### For Whitelisting
- Contact Plug, ApDao, YeetDat, or BoogaBullas teams
- Provide wallet address for merkle tree inclusion
- Wait for admin to update merkle root

---

## 📄 License

MIT License - See LICENSE file

---

## 🙏 Acknowledgments

- **OpenZeppelin**: Security patterns and contracts
- **Olympus DAO**: Original bonding mechanism inspiration
- **Berachain**: Network and HONEY stablecoin
- **Partners**: Plug, ApDao, YeetDat, BoogaBullas for early support

---

**Built with ❤️ for the Apiary community**

For questions or support, reach out to the Apiary team.
