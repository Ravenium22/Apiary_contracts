/**
 * TWAP Oracle Updater
 *
 * Calls update() on the TWAP oracle every hour until MIN_UPDATES_REQUIRED (6) is reached.
 * After 6 successful updates, consult() will stop reverting and the frontend can read prices.
 *
 * Usage:
 *   node scripts/twapUpdater.js
 *
 * Requires:
 *   npm install ethers@5
 *   PRIVATE_KEY and BERACHAIN_RPC_URL in .env
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Load .env manually
const envPath = path.join(__dirname, '..', '.env');
const envFile = fs.readFileSync(envPath, 'utf8');
const env = {};
envFile.split('\n').forEach(line => {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
        const eqIndex = trimmed.indexOf('=');
        if (eqIndex > 0) {
            env[trimmed.slice(0, eqIndex)] = trimmed.slice(eqIndex + 1);
        }
    }
});

const TWAP_ADDRESS = '0xDBA9624dfd8aC6198440FFfb2C98EE428ec0263c';
const MIN_UPDATES = 6;
const POLL_INTERVAL_MS = 10 * 60 * 1000; // check every 10 minutes
const TWAP_ABI = [
    'function update() public',
    'function updateCount() public view returns (uint256)',
    'function blockTimestampLast() public view returns (uint32)',
    'function price0Average() public view returns (uint224)',
    'function consult(uint256 amountIn) external returns (uint256 amountOut)',
    'function PERIOD() public view returns (uint256)',
    'function MIN_UPDATES_REQUIRED() public view returns (uint256)'
];

async function main() {
    const provider = new ethers.providers.JsonRpcProvider(env.BERACHAIN_RPC_URL || 'https://rpc.berachain.com');
    const wallet = new ethers.Wallet(env.PRIVATE_KEY, provider);
    const twap = new ethers.Contract(TWAP_ADDRESS, TWAP_ABI, wallet);

    console.log('===========================================');
    console.log('  TWAP Oracle Updater');
    console.log('===========================================');
    console.log('Oracle:', TWAP_ADDRESS);
    console.log('Caller:', wallet.address);
    console.log('');

    const period = await twap.PERIOD();
    const minUpdates = await twap.MIN_UPDATES_REQUIRED();
    console.log(`PERIOD: ${period.toNumber()}s (${period.toNumber() / 3600}h)`);
    console.log(`MIN_UPDATES_REQUIRED: ${minUpdates.toString()}`);
    console.log(`Polling every ${POLL_INTERVAL_MS / 60000} minutes\n`);

    async function checkAndUpdate() {
        try {
            const updateCount = await twap.updateCount();
            const blockTimestampLast = await twap.blockTimestampLast();
            const now = Math.floor(Date.now() / 1000);
            const elapsed = now - blockTimestampLast;
            const remaining = Math.max(0, period.toNumber() - elapsed);

            console.log(`[${new Date().toLocaleTimeString()}] updateCount: ${updateCount}/${minUpdates} | last update: ${elapsed}s ago | next eligible in: ${remaining}s`);

            if (updateCount.gte(minUpdates)) {
                console.log('  -> Oracle is LIVE (consult() works)');
            } else {
                const updatesLeft = minUpdates.sub(updateCount).toNumber();
                console.log(`  -> ${updatesLeft} updates until oracle is live`);
            }

            if (remaining <= 0) {
                console.log('  -> Calling update()...');
                const tx = await twap.update({ gasLimit: 200000 });
                const receipt = await tx.wait();
                const newCount = await twap.updateCount();
                console.log(`  -> Done! tx: ${receipt.transactionHash}`);
                console.log(`  -> updateCount: ${newCount}/${minUpdates}\n`);
            } else {
                const mins = Math.ceil(remaining / 60);
                console.log(`  -> Waiting ${mins} min until next update window\n`);
            }
        } catch (err) {
            console.error(`  -> Error: ${err.message}\n`);
        }
    }

    // Run immediately, then poll
    await checkAndUpdate();
    setInterval(checkAndUpdate, POLL_INTERVAL_MS);
}

main().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
});
