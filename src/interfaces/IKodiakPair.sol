// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IKodiakPair
 * @notice Interface for Kodiak LP token pairs (Uniswap V2 style)
 * @dev Pair contracts represent liquidity pools
 */
interface IKodiakPair {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get token0 address
     * @return Address of token0
     */
    function token0() external view returns (address);

    /**
     * @notice Get token1 address
     * @return Address of token1
     */
    function token1() external view returns (address);

    /**
     * @notice Get current reserves and last update time
     * @return reserve0 Reserve of token0
     * @return reserve1 Reserve of token1
     * @return blockTimestampLast Timestamp of last update
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @notice Get price0 cumulative last
     * @return Cumulative price of token0
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @notice Get price1 cumulative last
     * @return Cumulative price of token1
     */
    function price1CumulativeLast() external view returns (uint256);

    /**
     * @notice Get kLast value for fee calculation
     * @return kLast value
     */
    function kLast() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint LP tokens
     * @param to Recipient of LP tokens
     * @return liquidity Amount of LP tokens minted
     */
    function mint(address to) external returns (uint256 liquidity);

    /**
     * @notice Burn LP tokens
     * @param to Recipient of underlying tokens
     * @return amount0 Amount of token0 returned
     * @return amount1 Amount of token1 returned
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Swap tokens
     * @param amount0Out Amount of token0 to receive
     * @param amount1Out Amount of token1 to receive
     * @param to Recipient address
     * @param data Callback data for flash swaps
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    /**
     * @notice Force reserves to match balances
     * @param to Address to send excess tokens to
     */
    function skim(address to) external;

    /**
     * @notice Force balances to match reserves
     */
    function sync() external;
}
