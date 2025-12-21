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

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    function swapWithDeadline(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapMultiHop(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLP,
        address recipient
    ) external returns (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity);

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

    /// @notice Stake LP tokens (pulls from caller)
    function stakeLP(address lpToken, uint256 amount) external;

    /// @notice Unstake LP tokens (sends to caller)
    function unstakeLP(address lpToken, uint256 amount) external;

    /// @notice Unstake LP tokens to specific recipient
    function unstakeLPTo(address lpToken, uint256 amount, address recipient) external;

    /// @notice Claim rewards (sends to caller)
    function claimLPRewards(address lpToken) external returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /// @notice Claim rewards to specific recipient
    function claimLPRewardsTo(address lpToken, address recipient) external returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get expected swap output
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Alias for getAmountOut
    function getExpectedSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Quote LP tokens for adding liquidity
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external view returns (uint256 expectedLP);

    /// @notice Get LP token address for pair
    function getLPToken(address tokenA, address tokenB) external view returns (address lpToken);

    /// @notice Check if pool exists
    function poolExists(address tokenA, address tokenB) external view returns (bool exists);

    /// @notice Get gauge for LP token
    function lpToGauge(address lpToken) external view returns (address gauge);

    /// @notice Get total staked for LP token
    function totalStakedLP(address lpToken) external view returns (uint256 amount);

    /// @notice Get yield manager address
    function yieldManager() external view returns (address);

    /// @notice Get treasury address
    function treasury() external view returns (address);

    /// @notice Get default slippage
    function defaultSlippageBps() external view returns (uint256);

    /// @notice Get staked balance in gauge
    function getStakedBalance(address lpToken) external view returns (uint256 balance);

    /// @notice Get pending rewards
    function getPendingRewards(address lpToken) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    /// @notice Calculate min output with slippage
    function calculateMinOutput(uint256 amount, uint256 slippageBps) external pure returns (uint256 minAmount);

    /// @notice Get adapter info
    function getAdapterInfo() external view returns (
        address _yieldManager,
        address _treasury,
        uint256 _totalSwaps,
        uint256 _totalLiquidityOps,
        uint256 _totalRewards
    );
}
