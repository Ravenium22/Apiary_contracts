// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IKodiakRouter } from "./interfaces/IKodiakRouter.sol";
import { IKodiakFactory } from "./interfaces/IKodiakFactory.sol";
import { IKodiakGauge } from "./interfaces/IKodiakGauge.sol";
import { IKodiakPair } from "./interfaces/IKodiakPair.sol";

/**
 * @title ApiaryKodiakAdapter
 * @author Apiary Protocol
 * @notice Adapter for interacting with Kodiak DEX on Berachain
 * @dev Handles swaps, liquidity provision, and LP staking for yield manager's 25/25/50 strategy
 * 
 * SECURITY:
 * - Only yield manager can execute operations
 * - Slippage protection on all swaps and liquidity operations
 * - Deadline protection prevents stale transactions
 * - Pool validation before operations
 * - ReentrancyGuard on all state-changing functions
 * - No tokens stuck in adapter (immediate forwarding to treasury)
 * 
 * ARCHITECTURE:
 * - Treasury → YieldManager → Adapter → Kodiak DEX
 * - Adapter never holds tokens (flow-through design)
 * - Emergency functions for owner
 * - View functions public for monitoring
 */
contract ApiaryKodiakAdapter is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Kodiak Router for swaps and liquidity
    IKodiakRouter public immutable kodiakRouter;

    /// @notice Kodiak Factory for pool validation
    IKodiakFactory public immutable kodiakFactory;

    /// @notice HONEY stablecoin on Berachain
    IERC20 public immutable honey;

    /// @notice APIARY governance token
    IERC20 public immutable apiary;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to execute yield operations
    address public yieldManager;

    /// @notice Treasury address to receive tokens
    address public treasury;

    /// @notice Default slippage tolerance in basis points (default: 50 = 0.5%)
    uint256 public defaultSlippageBps;

    /// @notice Default deadline offset in seconds (default: 300 = 5 minutes)
    uint256 public defaultDeadlineOffset;

    /// @notice Minimum swap amount to prevent dust attacks
    uint256 public minSwapAmount;

    /// @notice Minimum liquidity amount to prevent dust
    uint256 public minLiquidityAmount;

    /// @notice Mapping of LP token → gauge address
    mapping(address => address) public lpToGauge;

    /// @notice Mapping of LP token → total staked by adapter
    mapping(address => uint256) public totalStakedLP;

    /// @notice Total swaps executed (for monitoring)
    uint256 public totalSwapsExecuted;

    /// @notice Total liquidity operations (for monitoring)
    uint256 public totalLiquidityOps;

    /// @notice Total rewards claimed (for monitoring)
    uint256 public totalRewardsClaimed;

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

    event LiquidityRemoved(
        address indexed tokenA,
        address indexed tokenB,
        uint256 liquidity,
        uint256 amountA,
        uint256 amountB
    );

    event LPStaked(address indexed lpToken, address indexed gauge, uint256 amount);

    event LPUnstaked(address indexed lpToken, address indexed gauge, uint256 amount);

    event RewardsClaimed(address indexed lpToken, address indexed gauge, uint256 rewardCount);

    event YieldManagerUpdated(address indexed oldManager, address indexed newManager);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event GaugeRegistered(address indexed lpToken, address indexed gauge);

    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    event DeadlineOffsetUpdated(uint256 oldOffset, uint256 newOffset);

    event EmergencyWithdraw(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_AMOUNT();
    error APIARY__ONLY_YIELD_MANAGER();
    error APIARY__POOL_DOES_NOT_EXIST();
    error APIARY__GAUGE_NOT_REGISTERED();
    error APIARY__SLIPPAGE_TOO_HIGH();
    error APIARY__BELOW_MINIMUM();
    error APIARY__SWAP_FAILED();
    error APIARY__LIQUIDITY_FAILED();
    error APIARY__INSUFFICIENT_LP_STAKED();
    error APIARY__INVALID_PATH();
    error APIARY__DEADLINE_EXPIRED();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize Kodiak adapter
     * @param _kodiakRouter Kodiak router address
     * @param _kodiakFactory Kodiak factory address
     * @param _honey HONEY token address
     * @param _apiary APIARY token address
     * @param _treasury Treasury address
     * @param _yieldManager Yield manager address
     * @param _owner Owner address
     */
    constructor(
        address _kodiakRouter,
        address _kodiakFactory,
        address _honey,
        address _apiary,
        address _treasury,
        address _yieldManager,
        address _owner
    ) Ownable(_owner) {
        if (
            _kodiakRouter == address(0) || _kodiakFactory == address(0) || _honey == address(0)
                || _apiary == address(0) || _treasury == address(0) || _yieldManager == address(0)
        ) {
            revert APIARY__ZERO_ADDRESS();
        }

        kodiakRouter = IKodiakRouter(_kodiakRouter);
        kodiakFactory = IKodiakFactory(_kodiakFactory);
        honey = IERC20(_honey);
        apiary = IERC20(_apiary);
        treasury = _treasury;
        yieldManager = _yieldManager;

        // Default settings
        defaultSlippageBps = 50; // 0.5%
        defaultDeadlineOffset = 300; // 5 minutes
        minSwapAmount = 0.01e18; // 0.01 tokens
        minLiquidityAmount = 0.01e18; // 0.01 LP tokens
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyYieldManager() {
        if (msg.sender != yieldManager) {
            revert APIARY__ONLY_YIELD_MANAGER();
        }
        _;
    }

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
     * 
     * @dev Requirements:
     * - Only yield manager can call
     * - Amount must be above minimum
     * - Pool must exist
     * - Slippage within tolerance
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 amountOut) {
        // Validate inputs
        if (amountIn == 0 || minAmountOut == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (amountIn < minSwapAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        if (tokenIn == address(0) || tokenOut == address(0) || recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        // Validate pool exists
        address pair = kodiakFactory.getPair(tokenIn, tokenOut);
        if (pair == address(0)) {
            revert APIARY__POOL_DOES_NOT_EXIST();
        }

        // Transfer tokens from sender to adapter
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve router if needed
        _approveTokenIfNeeded(tokenIn, address(kodiakRouter), amountIn);

        // Build swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Calculate deadline
        uint256 deadline = block.timestamp + defaultDeadlineOffset;

        // Execute swap
        uint256[] memory amounts =
            kodiakRouter.swapExactTokensForTokens(amountIn, minAmountOut, path, recipient, deadline);

        amountOut = amounts[1];

        // Verify output meets minimum
        if (amountOut < minAmountOut) {
            revert APIARY__SWAP_FAILED();
        }

        totalSwapsExecuted++;

        emit Swapped(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

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
    ) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 amountOut) {
        if (deadline < block.timestamp) {
            revert APIARY__DEADLINE_EXPIRED();
        }

        if (amountIn == 0 || minAmountOut == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (amountIn < minSwapAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        address pair = kodiakFactory.getPair(tokenIn, tokenOut);
        if (pair == address(0)) {
            revert APIARY__POOL_DOES_NOT_EXIST();
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        _approveTokenIfNeeded(tokenIn, address(kodiakRouter), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts =
            kodiakRouter.swapExactTokensForTokens(amountIn, minAmountOut, path, recipient, deadline);

        amountOut = amounts[1];

        if (amountOut < minAmountOut) {
            revert APIARY__SWAP_FAILED();
        }

        totalSwapsExecuted++;

        emit Swapped(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    /**
     * @notice Multi-hop swap through multiple pools
     * @param path Array of token addresses for swap route
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum output amount
     * @param recipient Address to receive output tokens
     * @return amountOut Actual amount of tokens received
     */
    function swapMultiHop(address[] calldata path, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 amountOut)
    {
        if (path.length < 2) {
            revert APIARY__INVALID_PATH();
        }

        if (amountIn == 0 || minAmountOut == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        // Validate all pools exist
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = kodiakFactory.getPair(path[i], path[i + 1]);
            if (pair == address(0)) {
                revert APIARY__POOL_DOES_NOT_EXIST();
            }
        }

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        _approveTokenIfNeeded(path[0], address(kodiakRouter), amountIn);

        uint256 deadline = block.timestamp + defaultDeadlineOffset;

        uint256[] memory amounts =
            kodiakRouter.swapExactTokensForTokens(amountIn, minAmountOut, path, recipient, deadline);

        amountOut = amounts[amounts.length - 1];

        if (amountOut < minAmountOut) {
            revert APIARY__SWAP_FAILED();
        }

        totalSwapsExecuted++;

        emit Swapped(path[0], path[path.length - 1], amountIn, amountOut, recipient);
    }

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
    )
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity)
    {
        // Validate inputs
        if (amountA == 0 || amountB == 0 || minLP == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (tokenA == address(0) || tokenB == address(0) || recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        // Validate pool exists (or will be created)
        address pair = kodiakFactory.getPair(tokenA, tokenB);
        // Note: pair can be address(0) - factory will create it

        // Transfer tokens from sender
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        // Approve router
        _approveTokenIfNeeded(tokenA, address(kodiakRouter), amountA);
        _approveTokenIfNeeded(tokenB, address(kodiakRouter), amountB);

        // Calculate minimum amounts with slippage protection
        uint256 minAmountA = (amountA * (10000 - defaultSlippageBps)) / 10000;
        uint256 minAmountB = (amountB * (10000 - defaultSlippageBps)) / 10000;

        uint256 deadline = block.timestamp + defaultDeadlineOffset;

        // Add liquidity
        (actualAmountA, actualAmountB, liquidity) =
            kodiakRouter.addLiquidity(tokenA, tokenB, amountA, amountB, minAmountA, minAmountB, recipient, deadline);

        // Verify LP amount meets minimum
        if (liquidity < minLP) {
            revert APIARY__LIQUIDITY_FAILED();
        }

        // Return unused tokens to sender
        uint256 unusedA = amountA - actualAmountA;
        uint256 unusedB = amountB - actualAmountB;

        if (unusedA > 0) {
            IERC20(tokenA).safeTransfer(msg.sender, unusedA);
        }

        if (unusedB > 0) {
            IERC20(tokenB).safeTransfer(msg.sender, unusedB);
        }

        totalLiquidityOps++;

        emit LiquidityAdded(tokenA, tokenB, actualAmountA, actualAmountB, liquidity, recipient);
    }

    /**
     * @notice Remove liquidity from Kodiak pool
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param liquidity Amount of LP tokens to burn
     * @param minAmountA Minimum amount of token A (slippage protection)
     * @param minAmountB Minimum amount of token B (slippage protection)
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
    ) external onlyYieldManager whenNotPaused nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (liquidity == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (liquidity < minLiquidityAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        // Get LP token address
        address lpToken = kodiakFactory.getPair(tokenA, tokenB);
        if (lpToken == address(0)) {
            revert APIARY__POOL_DOES_NOT_EXIST();
        }

        // Transfer LP tokens from sender
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), liquidity);

        // Approve router
        _approveTokenIfNeeded(lpToken, address(kodiakRouter), liquidity);

        uint256 deadline = block.timestamp + defaultDeadlineOffset;

        // Remove liquidity
        (amountA, amountB) =
            kodiakRouter.removeLiquidity(tokenA, tokenB, liquidity, minAmountA, minAmountB, recipient, deadline);

        totalLiquidityOps++;

        emit LiquidityRemoved(tokenA, tokenB, liquidity, amountA, amountB);
    }

    /*//////////////////////////////////////////////////////////////
                        LP STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake LP tokens in Kodiak gauge
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to stake
     * @dev Gauge must be registered first via registerGauge()
     */
    function stakeLP(address lpToken, uint256 amount) external onlyYieldManager whenNotPaused nonReentrant {
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (amount < minLiquidityAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        address gauge = lpToGauge[lpToken];
        if (gauge == address(0)) {
            revert APIARY__GAUGE_NOT_REGISTERED();
        }

        // Transfer LP tokens from sender
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        // Approve gauge
        _approveTokenIfNeeded(lpToken, gauge, amount);

        // Stake in gauge
        IKodiakGauge(gauge).stake(amount);

        // Update tracking
        totalStakedLP[lpToken] += amount;

        emit LPStaked(lpToken, gauge, amount);
    }

    /**
     * @notice Unstake LP tokens from Kodiak gauge (sends to caller)
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to unstake
     */
    function unstakeLP(address lpToken, uint256 amount)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
    {
        _unstakeLP(lpToken, amount, msg.sender);
    }

    /**
     * @notice Unstake LP tokens from Kodiak gauge to specific recipient
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to unstake
     * @param recipient Address to receive unstaked LP tokens
     */
    function unstakeLPTo(address lpToken, uint256 amount, address recipient)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
    {
        _unstakeLP(lpToken, amount, recipient);
    }

    /**
     * @notice Internal unstake implementation
     */
    function _unstakeLP(address lpToken, uint256 amount, address recipient) internal {
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address gauge = lpToGauge[lpToken];
        if (gauge == address(0)) {
            revert APIARY__GAUGE_NOT_REGISTERED();
        }

        if (amount > totalStakedLP[lpToken]) {
            revert APIARY__INSUFFICIENT_LP_STAKED();
        }

        // Withdraw from gauge
        IKodiakGauge(gauge).withdraw(amount);

        // Update tracking
        totalStakedLP[lpToken] -= amount;

        // Transfer LP tokens to recipient
        IERC20(lpToken).safeTransfer(recipient, amount);

        emit LPUnstaked(lpToken, gauge, amount);
    }

    /**
     * @notice Claim rewards from staked LP tokens (sends to caller)
     * @param lpToken LP token address
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of reward amounts
     */
    function claimLPRewards(address lpToken)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        return _claimLPRewards(lpToken, msg.sender);
    }

    /**
     * @notice Claim rewards from staked LP tokens to specific recipient
     * @param lpToken LP token address
     * @param recipient Address to receive rewards
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of reward amounts
     */
    function claimLPRewardsTo(address lpToken, address recipient)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        return _claimLPRewards(lpToken, recipient);
    }

    /**
     * @notice Internal claim implementation
     */
    function _claimLPRewards(address lpToken, address recipient)
        internal
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        if (recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address gauge = lpToGauge[lpToken];
        if (gauge == address(0)) {
            revert APIARY__GAUGE_NOT_REGISTERED();
        }

        IKodiakGauge gaugeContract = IKodiakGauge(gauge);

        // Get reward tokens count
        uint256 rewardCount = gaugeContract.rewardTokensLength();

        // Get balances before claim
        rewardTokens = new address[](rewardCount);
        rewardAmounts = new uint256[](rewardCount);

        uint256[] memory balancesBefore = new uint256[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            rewardTokens[i] = gaugeContract.rewardTokens(i);
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        // Claim rewards
        gaugeContract.getReward();

        // Calculate received amounts and transfer to recipient
        for (uint256 i = 0; i < rewardCount; i++) {
            uint256 balanceAfter = IERC20(rewardTokens[i]).balanceOf(address(this));
            rewardAmounts[i] = balanceAfter - balancesBefore[i];

            if (rewardAmounts[i] > 0) {
                IERC20(rewardTokens[i]).safeTransfer(recipient, rewardAmounts[i]);
            }
        }

        totalRewardsClaimed++;

        emit RewardsClaimed(lpToken, gauge, rewardCount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get expected output amount for a swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function getExpectedSwapOutput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = kodiakRouter.getAmountsOut(amountIn, path);
        amountOut = amounts[1];
    }

    /**
     * @notice Get expected output amount for a swap (alias for interface compatibility)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = kodiakRouter.getAmountsOut(amountIn, path);
        amountOut = amounts[1];
    }

    /**
     * @notice Get expected output for multi-hop swap
     * @param path Array of token addresses
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function getExpectedMultiHopOutput(address[] calldata path, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        uint256[] memory amounts = kodiakRouter.getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
    }

    /**
     * @notice Check if pool exists
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return exists True if pool exists
     */
    function poolExists(address tokenA, address tokenB) external view returns (bool exists) {
        address pair = kodiakFactory.getPair(tokenA, tokenB);
        exists = (pair != address(0));
    }

    /**
     * @notice Get LP token address for a token pair
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return lpToken LP token address (address(0) if pool doesn't exist)
     */
    function getLPToken(address tokenA, address tokenB) external view returns (address lpToken) {
        lpToken = kodiakFactory.getPair(tokenA, tokenB);
    }

    /**
     * @notice Quote expected LP tokens for adding liquidity
     * @dev This is an estimate - actual LP received may differ slightly
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param amountA Amount of token A
     * @param amountB Amount of token B
     * @return expectedLP Estimated LP tokens to receive
     */
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external view returns (uint256 expectedLP) {
        address pair = kodiakFactory.getPair(tokenA, tokenB);
        
        if (pair == address(0)) {
            // New pool - LP tokens will be sqrt(amountA * amountB) minus minimum liquidity
            expectedLP = _sqrt(amountA * amountB);
            if (expectedLP > 1000) {
                expectedLP -= 1000; // Subtract MINIMUM_LIQUIDITY
            }
        } else {
            // Existing pool - calculate based on reserves
            (uint112 reserve0, uint112 reserve1,) = IKodiakPair(pair).getReserves();
            
            if (reserve0 == 0 || reserve1 == 0) {
                expectedLP = _sqrt(amountA * amountB);
            } else {
                uint256 totalSupply = IERC20(pair).totalSupply();
                
                // Sort tokens to match pair ordering
                (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
                (uint256 amount0, uint256 amount1) = tokenA == token0 
                    ? (amountA, amountB) 
                    : (amountB, amountA);
                
                // LP = min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1)
                uint256 liquidity0 = (amount0 * totalSupply) / reserve0;
                uint256 liquidity1 = (amount1 * totalSupply) / reserve1;
                
                expectedLP = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
            }
        }
    }

    /**
     * @notice Internal sqrt function for LP calculation
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Get staked LP balance for a token
     * @param lpToken LP token address
     * @return balance Staked balance
     */
    function getStakedBalance(address lpToken) external view returns (uint256 balance) {
        address gauge = lpToGauge[lpToken];
        if (gauge == address(0)) {
            return 0;
        }

        balance = IKodiakGauge(gauge).balanceOf(address(this));
    }

    /**
     * @notice Get pending rewards for staked LP
     * @param lpToken LP token address
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of pending reward amounts
     */
    function getPendingRewards(address lpToken)
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        address gauge = lpToGauge[lpToken];
        if (gauge == address(0)) {
            return (new address[](0), new uint256[](0));
        }

        IKodiakGauge gaugeContract = IKodiakGauge(gauge);
        uint256 rewardCount = gaugeContract.rewardTokensLength();

        rewardTokens = new address[](rewardCount);
        rewardAmounts = new uint256[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            rewardTokens[i] = gaugeContract.rewardTokens(i);
            rewardAmounts[i] = gaugeContract.earned(address(this), rewardTokens[i]);
        }
    }

    /**
     * @notice Get adapter info
     * @return _yieldManager Yield manager address
     * @return _treasury Treasury address
     * @return _totalSwaps Total swaps executed
     * @return _totalLiquidityOps Total liquidity operations
     * @return _totalRewards Total rewards claimed
     */
    function getAdapterInfo()
        external
        view
        returns (
            address _yieldManager,
            address _treasury,
            uint256 _totalSwaps,
            uint256 _totalLiquidityOps,
            uint256 _totalRewards
        )
    {
        _yieldManager = yieldManager;
        _treasury = treasury;
        _totalSwaps = totalSwapsExecuted;
        _totalLiquidityOps = totalLiquidityOps;
        _totalRewards = totalRewardsClaimed;
    }

    /**
     * @notice Calculate slippage-adjusted minimum output
     * @param amount Input amount
     * @param slippageBps Slippage in basis points
     * @return minAmount Minimum amount with slippage applied
     */
    function calculateMinOutput(uint256 amount, uint256 slippageBps) public pure returns (uint256 minAmount) {
        minAmount = (amount * (10000 - slippageBps)) / 10000;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register gauge for LP token staking
     * @param lpToken LP token address
     * @param gauge Gauge contract address
     */
    function registerGauge(address lpToken, address gauge) external onlyOwner {
        if (lpToken == address(0) || gauge == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        lpToGauge[lpToken] = gauge;

        emit GaugeRegistered(lpToken, gauge);
    }

    /**
     * @notice Update yield manager
     * @param newManager New yield manager address
     */
    function setYieldManager(address newManager) external onlyOwner {
        if (newManager == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldManager = yieldManager;
        yieldManager = newManager;

        emit YieldManagerUpdated(oldManager, newManager);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Update default slippage tolerance
     * @param newSlippageBps New slippage in basis points
     */
    function setDefaultSlippage(uint256 newSlippageBps) external onlyOwner {
        if (newSlippageBps > 1000) {
            // Max 10%
            revert APIARY__SLIPPAGE_TOO_HIGH();
        }

        uint256 oldSlippage = defaultSlippageBps;
        defaultSlippageBps = newSlippageBps;

        emit SlippageUpdated(oldSlippage, newSlippageBps);
    }

    /**
     * @notice Update default deadline offset
     * @param newOffset New deadline offset in seconds
     */
    function setDefaultDeadlineOffset(uint256 newOffset) external onlyOwner {
        uint256 oldOffset = defaultDeadlineOffset;
        defaultDeadlineOffset = newOffset;

        emit DeadlineOffsetUpdated(oldOffset, newOffset);
    }

    /**
     * @notice Update minimum swap amount
     * @param newMinSwap New minimum swap amount
     */
    function setMinSwapAmount(uint256 newMinSwap) external onlyOwner {
        minSwapAmount = newMinSwap;
    }

    /**
     * @notice Update minimum liquidity amount
     * @param newMinLiquidity New minimum liquidity amount
     */
    function setMinLiquidityAmount(uint256 newMinLiquidity) external onlyOwner {
        minLiquidityAmount = newMinLiquidity;
    }

    /**
     * @notice Pause adapter
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause adapter
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw tokens stuck in adapter
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdrawToken(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        IERC20(token).safeTransfer(treasury, amount);

        emit EmergencyWithdraw(token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approve token spending if needed
     * @param token Token address
     * @param spender Spender address
     * @param amount Amount to approve
     */
    function _approveTokenIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), spender);

        if (currentAllowance < amount) {
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }
}
