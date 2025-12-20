// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IKodiakRouter
 * @notice Interface for Kodiak DEX Router (Uniswap V2 style)
 * @dev Router handles swaps and liquidity operations on Kodiak
 */
interface IKodiakRouter {
    /*//////////////////////////////////////////////////////////////
                                SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Swap exact tokens for tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens (slippage protection)
     * @param path Array of token addresses for swap route
     * @param to Recipient address
     * @param deadline Unix timestamp after which transaction reverts
     * @return amounts Array of amounts for each swap in the path
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swap tokens for exact tokens
     * @param amountOut Desired amount of output tokens
     * @param amountInMax Maximum amount of input tokens (slippage protection)
     * @param path Array of token addresses for swap route
     * @param to Recipient address
     * @param deadline Unix timestamp after which transaction reverts
     * @return amounts Array of amounts for each swap in the path
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swap exact tokens for tokens supporting fee-on-transfer tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses for swap route
     * @param to Recipient address
     * @param deadline Unix timestamp after which transaction reverts
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add liquidity to a Kodiak pool
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param amountADesired Desired amount of token A
     * @param amountBDesired Desired amount of token B
     * @param amountAMin Minimum amount of token A (slippage protection)
     * @param amountBMin Minimum amount of token B (slippage protection)
     * @param to Recipient of LP tokens
     * @param deadline Unix timestamp after which transaction reverts
     * @return amountA Actual amount of token A added
     * @return amountB Actual amount of token B added
     * @return liquidity Amount of LP tokens minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /**
     * @notice Remove liquidity from a Kodiak pool
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param liquidity Amount of LP tokens to burn
     * @param amountAMin Minimum amount of token A to receive
     * @param amountBMin Minimum amount of token B to receive
     * @param to Recipient of tokens
     * @param deadline Unix timestamp after which transaction reverts
     * @return amountA Amount of token A received
     * @return amountB Amount of token B received
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get factory address
     * @return Address of Kodiak factory
     */
    function factory() external view returns (address);

    /**
     * @notice Get WBERA address
     * @return Address of wrapped BERA
     */
    function WETH() external view returns (address);

    /**
     * @notice Get expected output amounts for a given input amount and path
     * @param amountIn Input amount
     * @param path Array of token addresses for swap route
     * @return amounts Array of expected amounts for each step
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Get required input amounts for a given output amount and path
     * @param amountOut Output amount
     * @param path Array of token addresses for swap route
     * @return amounts Array of required amounts for each step
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Quote liquidity for token amounts
     * @param amountA Amount of token A
     * @param reserveA Reserve of token A in pool
     * @param reserveB Reserve of token B in pool
     * @return amountB Corresponding amount of token B
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external
        pure
        returns (uint256 amountB);
}
