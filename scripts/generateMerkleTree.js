/**
 * Merkle Tree Generation Script for Apiary Pre-Sale Whitelist
 * 
 * This script generates a merkle tree from whitelisted addresses and outputs:
 * 1. Merkle root (for contract deployment/update)
 * 2. Merkle proofs for each address (for frontend)
 * 
 * Partners to whitelist:
 * - Plug
 * - ApDao
 * - YeetDat
 * - BoogaBullas
 * 
 * Usage:
 * 1. Install dependencies: npm install merkletreejs keccak256 ethers
 * 2. Update WHITELIST_ADDRESSES with actual addresses
 * 3. Run: node scripts/generateMerkleTree.js
 */

const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const { ethers } = require('ethers');
const fs = require('fs');

// ============================================================================
// WHITELIST CONFIGURATION
// ============================================================================

/**
 * Whitelisted addresses for pre-sale
 * 
 * Replace these with actual partner addresses:
 * - Plug team/community addresses
 * - ApDao team/community addresses
 * - YeetDat team/community addresses
 * - BoogaBullas NFT holders or team addresses
 */
// Load addresses from test.csv (or override with manual list below)
function loadAddressesFromCSV(csvPath) {
    const csv = fs.readFileSync(csvPath, 'utf8');
    const lines = csv.trim().split('\n');
    const addresses = [];
    // Skip header row
    for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',');
        const addr = cols[0].replace(/"/g, '').trim();
        if (addr && ethers.utils.isAddress(addr) && addr !== '0x000000000000000000000000000000000000dead') {
            addresses.push(addr);
        }
    }
    return addresses;
}

const CSV_PATH = './test.csv';
const EXTRA_ADDRESSES = [
    // Deployer address for testing
    '0xe098B97D835CEA2c938A12E15d0da8B3F67a69B5',
];

let WHITELIST_ADDRESSES;
if (fs.existsSync(CSV_PATH)) {
    console.log(`Loading addresses from ${CSV_PATH}...`);
    WHITELIST_ADDRESSES = [...loadAddressesFromCSV(CSV_PATH), ...EXTRA_ADDRESSES];
} else {
    console.log('No CSV found, using EXTRA_ADDRESSES only');
    WHITELIST_ADDRESSES = EXTRA_ADDRESSES;
}

// Deduplicate (case-insensitive)
const seen = new Set();
WHITELIST_ADDRESSES = WHITELIST_ADDRESSES.filter(addr => {
    const lower = addr.toLowerCase();
    if (seen.has(lower)) return false;
    seen.add(lower);
    return true;
});

// ============================================================================
// MERKLE TREE GENERATION
// ============================================================================

/**
 * Generate leaf hash for an address
 * Must match contract logic: keccak256(bytes.concat(keccak256(abi.encode(address))))
 */
function hashAddress(address) {
    // First hash: keccak256(abi.encode(address))
    const firstHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(['address'], [address])
    );
    
    // Second hash: keccak256(bytes.concat(firstHash))
    const leaf = ethers.utils.keccak256(firstHash);
    
    return leaf;
}

/**
 * Generate merkle tree and proofs
 */
function generateMerkleTree() {
    console.log('🌳 Generating Merkle Tree for Apiary Pre-Sale Whitelist...\n');
    
    // Validate addresses
    const validatedAddresses = WHITELIST_ADDRESSES.map((addr, index) => {
        if (!ethers.utils.isAddress(addr)) {
            throw new Error(`Invalid address at index ${index}: ${addr}`);
        }
        return ethers.utils.getAddress(addr); // Checksum format
    });
    
    console.log(`✅ Validated ${validatedAddresses.length} addresses\n`);
    
    // Generate leaf hashes
    const leaves = validatedAddresses.map(addr => hashAddress(addr));
    
    // Create merkle tree
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    
    // Get merkle root
    const root = tree.getHexRoot();
    
    console.log('📋 Merkle Root (for contract):');
    console.log(root);
    console.log('\n');
    
    // Generate proofs for each address
    const proofs = {};
    validatedAddresses.forEach((addr, index) => {
        const leaf = leaves[index];
        const proof = tree.getHexProof(leaf);
        proofs[addr] = proof;
    });
    
    // Output results
    const output = {
        merkleRoot: root,
        totalAddresses: validatedAddresses.length,
        addresses: validatedAddresses,
        proofs: proofs,
        generatedAt: new Date().toISOString()
    };
    
    // Save to file
    const outputPath = './merkle-tree-output.json';
    fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
    
    console.log(`💾 Merkle tree data saved to: ${outputPath}\n`);
    
    // Print sample proof
    const sampleAddress = validatedAddresses[0];
    console.log('🔍 Sample Proof (for testing):');
    console.log(`Address: ${sampleAddress}`);
    console.log(`Proof: ${JSON.stringify(proofs[sampleAddress])}\n`);
    
    // Print tree structure
    console.log('🌲 Merkle Tree Structure:');
    console.log(tree.toString());
    
    return output;
}

// ============================================================================
// VERIFICATION FUNCTION
// ============================================================================

/**
 * Verify a merkle proof locally (for testing)
 */
function verifyProof(address, proof, merkleRoot) {
    const leaf = hashAddress(address);
    const tree = new MerkleTree(
        WHITELIST_ADDRESSES.map(addr => hashAddress(ethers.utils.getAddress(addr))),
        keccak256,
        { sortPairs: true }
    );
    
    const verified = tree.verify(proof, leaf, merkleRoot);
    
    console.log(`\n✓ Verification for ${address}:`);
    console.log(`  Leaf: ${leaf}`);
    console.log(`  Proof: ${JSON.stringify(proof)}`);
    console.log(`  Root: ${merkleRoot}`);
    console.log(`  Valid: ${verified ? '✅ YES' : '❌ NO'}`);
    
    return verified;
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

if (require.main === module) {
    try {
        const output = generateMerkleTree();
        
        // Test verification with first address
        const testAddress = WHITELIST_ADDRESSES[0];
        const testProof = output.proofs[ethers.utils.getAddress(testAddress)];
        verifyProof(ethers.utils.getAddress(testAddress), testProof, output.merkleRoot);
        
        console.log('\n✅ Merkle tree generation complete!');
        console.log('\n📝 Next Steps:');
        console.log('1. Update contract with merkle root using setMerkleRoot()');
        console.log('2. Provide merkle-tree-output.json to frontend team');
        console.log('3. Frontend will use proofs for purchaseApiary() calls\n');
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Export functions for use in other scripts
module.exports = {
    generateMerkleTree,
    verifyProof,
    hashAddress,
    WHITELIST_ADDRESSES
};
