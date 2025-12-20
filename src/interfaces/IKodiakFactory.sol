// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IKodiakFactory
 * @notice Interface for Kodiak DEX Factory (Uniswap V2 style)
 * @dev Factory creates and manages pair contracts
 */
interface IKodiakFactory {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /*//////////////////////////////////////////////////////////////
                            PAIR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new token pair
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @return pair Address of created pair
     */
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /**
     * @notice Get pair address for two tokens
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @return pair Address of pair (address(0) if doesn't exist)
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /**
     * @notice Get pair at specific index
     * @param index Index of pair
     * @return pair Address of pair
     */
    function allPairs(uint256 index) external view returns (address pair);

    /**
     * @notice Get total number of pairs
     * @return Total number of pairs created
     */
    function allPairsLength() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            FEE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get fee recipient address
     * @return Address that receives protocol fees
     */
    function feeTo() external view returns (address);

    /**
     * @notice Get fee setter address
     * @return Address that can change fee recipient
     */
    function feeToSetter() external view returns (address);
}
