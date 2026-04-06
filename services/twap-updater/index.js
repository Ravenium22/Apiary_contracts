/**
 * APIARY TWAP Oracle Updater
 *
 * Runs 24/7 on Railway (or any hosting).
 * Calls update() on the TWAP oracle every hour to keep prices fresh.
 *
 * Environment variables:
 *   PRIVATE_KEY       - Deployer/keeper wallet private key
 *   RPC_URL           - Berachain RPC (default: https://rpc.berachain.com)
 *   TWAP_ADDRESS      - TWAP oracle address
 *   POLL_MINUTES      - How often to check (default: 10)
 */

const { ethers } = require('ethers');

const TWAP_ADDRESS = process.env.TWAP_ADDRESS || '0x58b0042e39764de33f9a6fdcdcdf15ffba59507f';
const RPC_URL = process.env.RPC_URL || 'https://rpc.berachain.com';
const POLL_MS = (parseInt(process.env.POLL_MINUTES) || 10) * 60 * 1000;

const ABI = [
    'function update() public',
    'function updateCount() public view returns (uint256)',
    'function blockTimestampLast() public view returns (uint32)',
    'function price0Average() public view returns (uint224)',
    'function PERIOD() public view returns (uint256)',
    'function MIN_UPDATES_REQUIRED() public view returns (uint256)'
];

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

async function main() {
    if (!process.env.PRIVATE_KEY) {
        console.error('PRIVATE_KEY environment variable required');
        process.exit(1);
    }

    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const twap = new ethers.Contract(TWAP_ADDRESS, ABI, wallet);

    const period = Number(await twap.PERIOD());
    const minUpdates = Number(await twap.MIN_UPDATES_REQUIRED());

    log('APIARY TWAP Oracle Updater started');
    log(`Oracle: ${TWAP_ADDRESS}`);
    log(`Wallet: ${wallet.address}`);
    log(`Period: ${period}s | Min updates: ${minUpdates} | Poll: ${POLL_MS / 60000}min`);

    let consecutiveErrors = 0;

    async function tick() {
        try {
            const updateCount = Number(await twap.updateCount());
            const lastTimestamp = Number(await twap.blockTimestampLast());
            const now = Math.floor(Date.now() / 1000);
            const elapsed = now - lastTimestamp;
            const remaining = Math.max(0, period - elapsed);
            const isLive = updateCount >= minUpdates;

            log(`count: ${updateCount}/${minUpdates} | elapsed: ${elapsed}s | ${isLive ? 'LIVE' : 'WARMING UP'}`);

            if (remaining <= 0) {
                log('Calling update()...');
                const tx = await twap.update({ gasLimit: 200000 });
                const receipt = await tx.wait();
                const newCount = Number(await twap.updateCount());
                log(`Done! tx: ${receipt.transactionHash} | count: ${newCount}/${minUpdates}`);
            } else {
                log(`Next update in ${Math.ceil(remaining / 60)}min`);
            }

            consecutiveErrors = 0;
        } catch (err) {
            consecutiveErrors++;
            log(`Error (${consecutiveErrors}): ${err.message}`);

            if (consecutiveErrors >= 10) {
                log('Too many consecutive errors, waiting 30min before retry');
                await new Promise(r => setTimeout(r, 30 * 60 * 1000));
                consecutiveErrors = 0;
            }
        }
    }

    // Run immediately then poll
    await tick();
    setInterval(tick, POLL_MS);
}

main().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
});
