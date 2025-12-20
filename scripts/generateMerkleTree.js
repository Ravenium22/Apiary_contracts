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
const WHITELIST_ADDRESSES = [
    // ===== PLUG ADDRESSES =====
    '0x1111111111111111111111111111111111111111',
    '0x2222222222222222222222222222222222222222',
    
    // ===== APDAO ADDRESSES =====
    '0x3333333333333333333333333333333333333333',
    '0x4444444444444444444444444444444444444444',
    
    // ===== YEETDAT ADDRESSES =====
    '0x5555555555555555555555555555555555555555',
    '0x6666666666666666666666666666666666666666',
    
    // ===== BOOGABULLAS ADDRESSES =====
    '0x7777777777777777777777777777777777777777',
    '0x8888888888888888888888888888888888888888',
    
    // Add more addresses as needed...
];

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
