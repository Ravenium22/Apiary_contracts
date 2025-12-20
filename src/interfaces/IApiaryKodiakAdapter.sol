// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IApiaryKodiakAdapter
 * @notice Interface for the Apiary Kodiak DEX adapter
 * @dev Used by YieldManager for swaps, liquidity provision, and LP staking
 */
interface IApiaryKodiakAdapter {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Swapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed recipient
    );

    event LPStaked(address indexed lpToken, address indexed gauge, uint256 amount);
    event LPUnstaked(address indexed lpToken, address indexed gauge, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Swap tokens via Kodiak router
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum output amount (slippage protection)
     * @param recipient Address to receive output tokens
     * @return amountOut Actual amount of tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /**
     * @notice Swap with custom deadline
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum output amount
     * @param recipient Address to receive output tokens
     * @param deadline Custom deadline timestamp
     * @return amountOut Actual amount of tokens received
     */
    function swapWithDeadline(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /**
     * @notice Multi-hop swap through multiple pools
     * @param path Array of token addresses for swap route
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum output amount
     * @param recipient Address to receive output tokens
     * @return amountOut Actual amount of tokens received
     */
    function swapMultiHop(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add liquidity to Kodiak pool
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param amountA Amount of token A
     * @param amountB Amount of token B
     * @param minLP Minimum LP tokens to receive (slippage protection)
     * @param recipient Address to receive LP tokens
     * @return actualAmountA Actual amount of token A added
     * @return actualAmountB Actual amount of token B added
     * @return liquidity Amount of LP tokens received
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLP,
        address recipient
    ) external returns (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity);

    /**
     * @notice Remove liquidity from Kodiak pool
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param liquidity Amount of LP tokens to burn
     * @param minAmountA Minimum amount of token A
     * @param minAmountB Minimum amount of token B
     * @param recipient Address to receive tokens
     * @return amountA Amount of token A received
     * @return amountB Amount of token B received
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB,
        address recipient
    ) external returns (uint256 amountA, uint256 amountB);

    /*//////////////////////////////////////////////////////////////
                        LP STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake LP tokens in Kodiak gauge
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to stake
     */
    function stakeLP(address lpToken, uint256 amount) external;

    /**
     * @notice Unstake LP tokens from Kodiak gauge
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to unstake
     */
    function unstakeLP(address lpToken, uint256 amount) external;

    /**
     * @notice Claim rewards from LP gauge
     * @param lpToken LP token address
     */
    function claimLPRewards(address lpToken) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get expected output amount for a swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return amountOut Expected output amount
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /**
     * @notice Quote expected LP tokens for adding liquidity
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param amountA Amount of token A
     * @param amountB Amount of token B
     * @return expectedLP Expected LP tokens to receive
     */
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external view returns (uint256 expectedLP);

    /**
     * @notice Get LP token address for a pair
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return lpToken LP token address
     */
    function getLPToken(address tokenA, address tokenB) external view returns (address lpToken);

    /**
     * @notice Check if pool exists
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return exists True if pool exists
     */
    function poolExists(address tokenA, address tokenB) external view returns (bool exists);

    /**
     * @notice Get gauge address for LP token
     * @param lpToken LP token address
     * @return gauge Gauge address
     */
    function lpToGauge(address lpToken) external view returns (address gauge);

    /**
     * @notice Get total staked LP for a token
     * @param lpToken LP token address
     * @return amount Total staked amount
     */
    function totalStakedLP(address lpToken) external view returns (uint256 amount);

    /**
     * @notice Get yield manager address
     * @return Yield manager address
     */
    function yieldManager() external view returns (address);

    /**
     * @notice Get treasury address
     * @return Treasury address
     */
    function treasury() external view returns (address);

    /**
     * @notice Get default slippage in basis points
     * @return Default slippage bps
     */
    function defaultSlippageBps() external view returns (uint256);
}
