/**
 * APIARY Yield Keeper
 *
 * Periodically checks if yield can be executed on the YieldManager,
 * and calls executeYield() when eligible.
 *
 * Environment variables:
 *   PRIVATE_KEY          - Keeper wallet private key (needs BERA for gas only)
 *   RPC_URL              - Berachain RPC (default: https://rpc.berachain.com)
 *   YIELD_MANAGER        - YieldManager contract address
 *   POLL_MINUTES         - How often to check (default: 15)
 *   MIN_YIELD_THRESHOLD  - Minimum pending yield in wei to bother executing (default: 0)
 */

const { ethers } = require('ethers');

const YIELD_MANAGER = process.env.YIELD_MANAGER || '';
const RPC_URL = process.env.RPC_URL || 'https://rpc.berachain.com';
const POLL_MS = (parseInt(process.env.POLL_MINUTES) || 15) * 60 * 1000;
const MIN_THRESHOLD = ethers.BigNumber.from(process.env.MIN_YIELD_THRESHOLD || '0');

const ABI = [
    'function executeYield() external',
    'function canExecuteYield() external view returns (bool canExecute, uint256 pending, uint256 timeUntilNextExecution)',
    'function pendingYield() external view returns (uint256)',
    'function keeper() external view returns (address)',
    'function owner() external view returns (address)',
    'function lastExecutionTime() external view returns (uint256)',
    'function paused() external view returns (bool)'
];

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

function formatiBGT(wei) {
    return ethers.utils.formatUnits(wei, 18);
}

async function main() {
    if (!process.env.PRIVATE_KEY) {
        console.error('PRIVATE_KEY environment variable required');
        process.exit(1);
    }
    if (!YIELD_MANAGER) {
        console.error('YIELD_MANAGER environment variable required');
        process.exit(1);
    }

    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const ym = new ethers.Contract(YIELD_MANAGER, ABI, wallet);

    // Verify keeper authorization
    const keeper = await ym.keeper();
    const owner = await ym.owner();
    const isAuthorized = wallet.address.toLowerCase() === keeper.toLowerCase() ||
                         wallet.address.toLowerCase() === owner.toLowerCase();

    log('APIARY Yield Keeper started');
    log(`YieldManager: ${YIELD_MANAGER}`);
    log(`Wallet: ${wallet.address}`);
    log(`Keeper on contract: ${keeper}`);
    log(`Authorized: ${isAuthorized ? 'YES' : 'NO — executeYield() will revert!'}`);
    log(`Poll interval: ${POLL_MS / 60000}min`);
    log(`Min threshold: ${formatiBGT(MIN_THRESHOLD)} iBGT`);
    log('');

    if (!isAuthorized) {
        log('WARNING: This wallet is not the keeper or owner. Call setKeeper() on the YieldManager first.');
    }

    let consecutiveErrors = 0;

    async function tick() {
        try {
            const paused = await ym.paused();
            if (paused) {
                log('YieldManager is PAUSED — skipping');
                return;
            }

            const pending = await ym.pendingYield();

            let canExecute, timeUntil;
            try {
                const result = await ym.canExecuteYield();
                canExecute = result.canExecute;
                timeUntil = result.timeUntilNextExecution;
            } catch {
                canExecute = false;
                timeUntil = ethers.BigNumber.from(0);
            }

            log(`pending: ${formatiBGT(pending)} iBGT | canExecute: ${canExecute} | nextIn: ${timeUntil}s`);

            if (!canExecute) {
                if (timeUntil.gt(0)) {
                    log(`Waiting ${Math.ceil(timeUntil.toNumber() / 60)}min until next execution window`);
                } else if (pending.eq(0)) {
                    log('No pending yield');
                }
                consecutiveErrors = 0;
                return;
            }

            if (pending.lt(MIN_THRESHOLD)) {
                log(`Pending ${formatiBGT(pending)} below threshold ${formatiBGT(MIN_THRESHOLD)} — skipping`);
                consecutiveErrors = 0;
                return;
            }

            log('Calling executeYield()...');
            const tx = await ym.executeYield({ gasLimit: 2000000 });
            const receipt = await tx.wait();
            log(`Done! tx: ${receipt.transactionHash} | gas: ${receipt.gasUsed.toString()}`);

            // Check new state
            const newPending = await ym.pendingYield();
            log(`Remaining pending: ${formatiBGT(newPending)} iBGT`);

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
