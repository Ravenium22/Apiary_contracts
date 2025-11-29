const { StandardMerkleTree } = require('@openzeppelin/merkle-tree');
const fs = require('fs');

// Read and parse the file
const fileContent = fs.readFileSync('PresaleBondWhitelistAddresses.txt', 'utf-8');
const lines = fileContent.trim().split('\n');

// Convert file data into whitelist
const whitelist = lines.map((line) => {
    const [address] = line.split(/\s+/); // Split by whitespace or tabs

    return [address];
});

// // (2)
const tree = StandardMerkleTree.of(whitelist, ['address']);

// Prepare output
let output = `Merkle Root: ${tree.root}\n\nEntries:\n`;
console.log('Merkle Root: ', tree.root);
for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    output += `Value: ${JSON.stringify(v)}\nProof: ${JSON.stringify(proof)}\n\n`;
}

//Write to output.txt
fs.writeFileSync('MerkleTreePresaleOwners.txt', output);
