const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

/**0x5112fC37E88f4F5A6052adE5FC356175aB45ad83
0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF
0x0959a16d89a039BB5e63b3904D4EBd5D946DED01
0x55422cabb16e16cB84397Ed606076607b00aA2e5
0xd68D714154B033934dF470DA1D8ff89Ac4987eB8
0x37aD1B1c79409609EDF4F9d02EF7FfC8B1E8084D */
const whitelist = [
  "0x5112fC37E88f4F5A6052adE5FC356175aB45ad83",
  "0x061Bc6f643038E4d6561aF4EBbc0B127cc5316cF",
  "0x0959a16d89a039BB5e63b3904D4EBd5D946DED01",
  "0x55422cabb16e16cB84397Ed606076607b00aA2e5",
  "0xd68D714154B033934dF470DA1D8ff89Ac4987eB8",
  "0x37aD1B1c79409609EDF4F9d02EF7FfC8B1E8084D",
];



const leaves = whitelist.map((addr) => keccak256(addr));
const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const rootHash = merkleTree.getRoot().toString("hex");
console.log(`Whitelist Merkle Root: 0x${rootHash}`);
whitelist.forEach((address) => {
  const proof = merkleTree.getHexProof(keccak256(address));
  console.log(`Address: ${address} Proof: ${proof}`);
});
