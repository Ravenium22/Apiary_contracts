# Deployment Scripts

Foundry deployment scripts for the Apiary protocol on Berachain.

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env
# Edit .env with your values

# 2. Deploy all contracts
forge script script/deployment/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# 3. Configure protocol
forge script script/deployment/07_ConfigureProtocol.s.sol:ConfigureProtocol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# 4. Verify deployment
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL
```

## Scripts

| Script | Purpose |
|--------|---------|
| `01_DeployToken.s.sol` | Deploy APIARY token |
| `02_DeploysApiary.s.sol` | Deploy sAPIARY token |
| `03_DeployTreasury.s.sol` | Deploy treasury |
| `04_DeployStaking.s.sol` | Deploy staking & warmup |
| `05_DeployBonds.s.sol` | Deploy bonds & oracle |
| `06_DeployYieldManager.s.sol` | Deploy yield manager & adapters |
| `07_ConfigureProtocol.s.sol` | Configure all contracts |
| `DeployAll.s.sol` | Deploy everything |
| `VerifyDeployment.s.sol` | Verify deployment |

## Documentation

- **[DEPLOYMENT_GUIDE.md](../../DEPLOYMENT_GUIDE.md)** - Complete deployment guide
- **[DEPLOYMENT_CHECKLIST.md](../../DEPLOYMENT_CHECKLIST.md)** - Manual checklist
- **[DEPLOYMENT_SCRIPTS_SUMMARY.md](../../DEPLOYMENT_SCRIPTS_SUMMARY.md)** - Overview

## Environment Variables

See `.env.example` for all required variables.

## Support

For issues, consult the troubleshooting section in `DEPLOYMENT_GUIDE.md`.
