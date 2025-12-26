# Apiary Protocol - Berachain Reserve Currency

Apiary is a decentralized reserve currency protocol built on Berachain, featuring bonding mechanisms, staking rewards, and yield management through Kodiak and Infrared integrations.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      APIARY PROTOCOL                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   APIARY     │     │   sAPIARY    │     │   Treasury   │    │
│  │   Token      │◄────│   (Staked)   │◄────│              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│         │                    ▲                    ▲            │
│         │                    │                    │            │
│         ▼                    │                    │            │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   Staking    │─────│  Yield       │─────│   Bonds      │    │
│  │   Contract   │     │  Manager     │     │  (iBGT/LP)   │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│                              │                                  │
│                    ┌─────────┴─────────┐                       │
│                    ▼                   ▼                       │
│             ┌──────────────┐    ┌──────────────┐               │
│             │   Infrared   │    │    Kodiak    │               │
│             │   Adapter    │    │    Adapter   │               │
│             └──────────────┘    └──────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Contracts

| Contract | Description |
|----------|-------------|
| `ApiaryToken.sol` | ERC20 token with per-minter allocation limits |
| `sApiary.sol` | Staked APIARY token with rebase mechanics |
| `ApiaryTreasury.sol` | Protocol treasury managing reserves |
| `ApiaryStaking.sol` | Staking contract with epoch-based rewards |
| `ApiaryBondDepository.sol` | Bond sales for iBGT and LP tokens |
| `ApiaryPreSaleBond.sol` | Merkle-tree whitelist pre-sale bonds |
| `ApiaryYieldManager.sol` | Manages yield from iBGT staking |
| `ApiaryInfraredAdapter.sol` | Integration with Infrared protocol |
| `ApiaryKodiakAdapter.sol` | Integration with Kodiak DEX |
| `ApiaryUniswapV2TwapOracle.sol` | TWAP price oracle for bonds |

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd BeraReserve-contracts-main

# Install dependencies
forge install
npm install

# Copy environment file
cp .env.example .env
# Edit .env with your values
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/ApiaryToken.t.sol

# Run with gas report
forge test --gas-report
```

### Coverage

```bash
forge coverage --report summary --skip script
```

## Environment Setup

Copy `.env.example` to `.env` and fill in:

```bash
cp .env.example .env
```

Required variables:
- `PRIVATE_KEY` - Deployer wallet private key
- `BERASCAN_API_KEY` - For contract verification

See `.env.example` for all available options.

## Deployment

### Full Deployment (Recommended)

The `DeployAll.s.sol` script deploys all core contracts in sequence:

```bash
# Dry run (simulation)
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url https://bepolia.rpc.berachain.com \
  --private-key $PRIVATE_KEY

# Actual deployment
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url https://bepolia.rpc.berachain.com \
  --private-key $PRIVATE_KEY \
  --broadcast

# With verification
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url https://bepolia.rpc.berachain.com \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $BERASCAN_API_KEY
```

### Individual Deployments

For more control, deploy contracts individually:

```bash
# 1. Deploy APIARY Token
forge script script/deployment/01_DeployToken.s.sol:DeployToken --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 2. Deploy sAPIARY Token
forge script script/deployment/02_DeploysApiary.s.sol:DeploysApiary --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 3. Deploy Treasury
forge script script/deployment/03_DeployTreasury.s.sol:DeployTreasury --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 4. Deploy Staking
forge script script/deployment/04_DeployStaking.s.sol:DeployStaking --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 5. Deploy Bonds (requires LP pair)
forge script script/deployment/05_DeployBonds.s.sol:DeployBonds --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 6. Deploy Yield Manager
forge script script/deployment/06_DeployYieldManager.s.sol:DeployYieldManager --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Network Configuration

### Berachain Mainnet
- RPC: `https://rpc.berachain.com`
- Chain ID: `80094`
- Explorer: `https://berascan.com`

### Bepolia Testnet
- RPC: `https://bepolia.rpc.berachain.com`
- Chain ID: `80069`
- Explorer: `https://testnet.berascan.com`

## 📍 Deployed Addresses (Bepolia Testnet)

| Contract | Address |
|----------|---------|
| APIARY Token | `0xC6a576Efe2BC8d0Bc66580262958d9Df06fD1825` |
| sAPIARY Token | `0xa960d5814d685f2B0b673907336f46f577884C67` |
| Treasury | `0xd02a9497c613978eADC4aB9059F208d5e2DA2dd1` |
| Staking | `0x61F530A4f9Fc06484DB41a3a809968a5401a968c` |
| Pre-Sale Bond | `0xFc81E9Be15722612606c534C1C4a5E724336f3A3` |
| Yield Manager | `0x775824eF40239Cf80EeC6aEd776B6ab116A08ED2` |
| Infrared Adapter | `0x8FaeB0DB71947efBC4836283506cEa0f583f0E47` |
| Kodiak Adapter | `0x791Cc5b3a033b6dbE6Dd6f0FE72F42Cee1D1C7c5` |

## Post-Deployment Steps

After deploying core contracts:

1. **Create LP Pool**: Create APIARY/HONEY pool on [Kodiak](https://app.kodiak.finance)
2. **Add Liquidity**: Add initial liquidity to the pool
3. **Deploy Bonds**: Run `05_DeployBonds.s.sol` with the LP pair address
4. **Configure Bonds**: Set bond terms (vesting, discount, max debt)
5. **Update Merkle Root**: Set whitelist for pre-sale bonds
6. **Create Farm**: Create Kodiak farm for LP rewards

## Useful Commands

```bash
# Format code
forge fmt

# Gas snapshot
forge snapshot

# Generate merkle tree for whitelist
node scripts/generateMerkleTree.js

# Verify merkle proof
node scripts/verifyMerkleProof.js

# Cast commands for interaction
cast call <CONTRACT> "functionName()" --rpc-url $RPC_URL
cast send <CONTRACT> "functionName(args)" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

## Project Structure

```
├── src/                    # Smart contracts
│   ├── interfaces/         # Contract interfaces
│   ├── libs/              # Libraries (ERC20, etc.)
│   ├── types/             # Type definitions
│   └── utils/             # Utility contracts
├── test/                  # Test files
│   ├── integration/       # Integration tests
│   └── utils/            # Test utilities
├── script/               # Deployment scripts
│   ├── deployment/       # Deploy scripts
│   └── utils/           # Utility scripts
├── lib/                  # Dependencies (forge-std, openzeppelin)
└── broadcast/           # Deployment artifacts
```

## 📄 License

AGPL-3.0-or-later
