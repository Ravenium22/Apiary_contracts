/**
 * Merkle Tree Generation Script for Apiary Pre-Sale Whitelist
 *
 * New format: leaves encode (address, maxAllocation) for NFT-proportional caps.
 * Leaf = keccak256(bytes.concat(keccak256(abi.encode(address, maxAllocation))))
 *
 * Usage:
 *   npm install merkletreejs keccak256 ethers
 *   node scripts/generateMerkleTree.js
 */

const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const { ethers } = require('ethers');
const fs = require('fs');

// ============================================================================
// CONFIGURATION
// ============================================================================

const CSV_PATH = './merged_holders.csv';

// Total APIARY allocated to pre-sale (9 decimals)
// UPDATE THIS on launch day after OTC deals are done and remaining balance is known
const TOTAL_PRESALE_APIARY = ethers.BigNumber.from(process.env.PRESALE_APIARY || '16800000000000'); // default 16,800 APIARY

// Extra addresses to include (with manual quantity) — NONE for production
const EXTRA_ENTRIES = [];

// ============================================================================
// LOAD ADDRESSES + QUANTITIES FROM CSV
// ============================================================================

function loadFromCSV(csvPath) {
    const csv = fs.readFileSync(csvPath, 'utf8');
    const lines = csv.trim().split('\n');
    const entries = [];
    // Skip header: "HolderAddress","Quantity","PendingBalanceUpdate"
    for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',');
        const addr = cols[0].replace(/"/g, '').trim();
        const qty = parseInt(cols[1].replace(/"/g, '').trim(), 10);
        if (addr && ethers.utils.isAddress(addr) && addr !== '0x000000000000000000000000000000000000dead' && qty > 0) {
            entries.push({ address: addr, quantity: qty });
        }
    }
    return entries;
}

// ============================================================================
// BUILD WHITELIST WITH ALLOCATIONS
// ============================================================================

let entries = [];
if (fs.existsSync(CSV_PATH)) {
    console.log(`Loading addresses from ${CSV_PATH}...`);
    entries = [...loadFromCSV(CSV_PATH), ...EXTRA_ENTRIES];
} else {
    console.log('No CSV found, using EXTRA_ENTRIES only');
    entries = [...EXTRA_ENTRIES];
}

// Deduplicate (case-insensitive), sum quantities if duplicate
const entryMap = new Map();
for (const e of entries) {
    const key = e.address.toLowerCase();
    if (entryMap.has(key)) {
        entryMap.get(key).quantity += e.quantity;
    } else {
        entryMap.set(key, { address: ethers.utils.getAddress(e.address), quantity: e.quantity });
    }
}
const whitelist = Array.from(entryMap.values());

// Calculate total quantity for proportional allocation
const totalQuantity = whitelist.reduce((sum, e) => sum + e.quantity, 0);
console.log(`Total addresses: ${whitelist.length}`);
console.log(`Total quantity: ${totalQuantity}`);
console.log(`Total pre-sale APIARY: ${ethers.utils.formatUnits(TOTAL_PRESALE_APIARY, 9)}\n`);

// Calculate maxAllocation for each user (proportional, 9 decimals)
// Floor each allocation, then distribute remainder to largest holders
const allocations = whitelist.map(e => {
    const alloc = TOTAL_PRESALE_APIARY.mul(e.quantity).div(totalQuantity);
    return { ...e, maxAllocation: alloc };
});

// Verify total allocated doesn't exceed budget
const totalAllocated = allocations.reduce((sum, e) => sum.add(e.maxAllocation), ethers.BigNumber.from(0));
console.log(`Total allocated: ${ethers.utils.formatUnits(totalAllocated, 9)} APIARY`);
console.log(`Rounding dust: ${ethers.utils.formatUnits(TOTAL_PRESALE_APIARY.sub(totalAllocated), 9)} APIARY\n`);

// ============================================================================
// MERKLE TREE GENERATION
// ============================================================================

/**
 * Generate leaf hash matching contract:
 * keccak256(bytes.concat(keccak256(abi.encode(address, maxAllocation))))
 */
function hashLeaf(address, maxAllocation) {
    const innerHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(['address', 'uint256'], [address, maxAllocation])
    );
    return ethers.utils.keccak256(innerHash);
}

function generateMerkleTree() {
    console.log('Generating Merkle Tree for Apiary Pre-Sale (address, maxAllocation)...\n');

    // Generate leaves
    const leaves = allocations.map(e => hashLeaf(e.address, e.maxAllocation));

    // Create tree
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = tree.getHexRoot();

    console.log('Merkle Root:', root, '\n');

    // Generate proofs
    const proofs = {};
    allocations.forEach((e, i) => {
        const proof = tree.getHexProof(leaves[i]);
        proofs[e.address] = {
            proof,
            maxAllocation: e.maxAllocation.toString(),
            quantity: e.quantity
        };
    });

    const output = {
        merkleRoot: root,
        totalAddresses: allocations.length,
        totalPresaleApiary: TOTAL_PRESALE_APIARY.toString(),
        totalQuantity,
        proofs,
        generatedAt: new Date().toISOString()
    };

    const outputPath = './merkle-tree-output.json';
    fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
    console.log(`Saved to: ${outputPath}\n`);

    // Sample
    const sample = allocations[0];
    console.log('Sample entry:');
    console.log(`  Address: ${sample.address}`);
    console.log(`  Quantity: ${sample.quantity}`);
    console.log(`  maxAllocation: ${sample.maxAllocation.toString()} (${ethers.utils.formatUnits(sample.maxAllocation, 9)} APIARY)`);
    console.log(`  Proof: ${JSON.stringify(proofs[sample.address].proof)}\n`);

    return output;
}

// ============================================================================
// VERIFICATION
// ============================================================================

function verifyProof(address, maxAllocation, proof, merkleRoot) {
    const leaf = hashLeaf(address, maxAllocation);
    const leaves = allocations.map(e => hashLeaf(e.address, e.maxAllocation));
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const valid = tree.verify(proof, leaf, merkleRoot);

    console.log(`Verification for ${address}:`);
    console.log(`  maxAllocation: ${maxAllocation.toString()}`);
    console.log(`  Valid: ${valid ? 'YES' : 'NO'}`);
    return valid;
}

// ============================================================================
// MAIN
// ============================================================================

if (require.main === module) {
    try {
        const output = generateMerkleTree();

        // Verify first entry
        const testAddr = allocations[0].address;
        const testData = output.proofs[testAddr];
        verifyProof(testAddr, ethers.BigNumber.from(testData.maxAllocation), testData.proof, output.merkleRoot);

        console.log('\nDone! Next steps:');
        console.log('1. Update contract: setMerkleRoot("' + output.merkleRoot + '")');
        console.log('2. Send merkle-tree-output.json to frontend team');
        console.log('3. Frontend calls purchaseApiary(honeyAmt, proof, maxAllocation, minApiary)\n');
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

module.exports = { generateMerkleTree, verifyProof, hashLeaf };
