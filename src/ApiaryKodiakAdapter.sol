// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IKodiakRouter } from "./interfaces/IKodiakRouter.sol";
import { IKodiakFactory } from "./interfaces/IKodiakFactory.sol";
import { IKodiakFarm } from "./interfaces/IKodiakFarm.sol";
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

    /// @notice Mapping of LP token → farm address (replaces gauge)
    mapping(address => address) public lpToFarm;

    /// @notice Mapping of LP token → configured lock duration in seconds
    mapping(address => uint256) public lpLockDuration;

    /// @notice Mapping of LP token → array of active stake kek_ids
    mapping(address => bytes32[]) public lpStakeIds;

    /// @notice Mapping of kek_id → bool to verify stake ownership
    mapping(bytes32 => bool) public isOurStake;

    /// @notice Mapping of kek_id → LP token for reverse lookup
    mapping(bytes32 => address) public stakeIdToLP;

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

    event LPStaked(
        address indexed lpToken,
        address indexed farm,
        uint256 amount,
        bytes32 indexed kekId,
        uint256 lockDuration
    );

    event LPUnstaked(
        address indexed lpToken,
        address indexed farm,
        uint256 amount,
        bytes32 indexed kekId
    );

    event AllExpiredLPUnstaked(
        address indexed lpToken,
        address indexed farm,
        uint256 totalAmount,
        uint256 stakesWithdrawn
    );

    event RewardsClaimed(
        address indexed lpToken,
        address indexed farm,
        address[] rewardTokens,
        uint256[] rewardAmounts
    );

    event FarmRegistered(address indexed lpToken, address indexed farm);

    event LockDurationUpdated(address indexed lpToken, uint256 oldDuration, uint256 newDuration);

    event YieldManagerUpdated(address indexed oldManager, address indexed newManager);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

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
    error APIARY__FARM_NOT_REGISTERED();
    error APIARY__SLIPPAGE_TOO_HIGH();
    error APIARY__BELOW_MINIMUM();
    error APIARY__SWAP_FAILED();
    error APIARY__LIQUIDITY_FAILED();
    error APIARY__NOT_OUR_STAKE();
    error APIARY__INVALID_PATH();
    error APIARY__DEADLINE_EXPIRED();
    error APIARY__LOCK_DURATION_TOO_SHORT();
    error APIARY__LOCK_DURATION_NOT_SET();
    error APIARY__STAKE_NOT_EXPIRED();

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
     * @notice Stake LP tokens in Kodiak Farm with locked staking
     * @dev Each stake creates a unique kek_id that must be tracked for withdrawal
     * @param lpToken LP token address
     * @param amount Amount of LP tokens to stake
     * @return kekId The unique identifier for this stake position
     * 
     * Lock Duration:
     * - Must be set via setLockDuration() before staking
     * - Longer duration = higher reward multiplier
     * - Cannot withdraw until lock expires (unless farm has stakesUnlocked)
     */
    function stakeLP(address lpToken, uint256 amount) 
        external 
        onlyYieldManager 
        whenNotPaused 
        nonReentrant 
        returns (bytes32 kekId) 
    {
        if (amount == 0) {
            revert APIARY__INVALID_AMOUNT();
        }

        if (amount < minLiquidityAmount) {
            revert APIARY__BELOW_MINIMUM();
        }

        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        uint256 lockDuration = lpLockDuration[lpToken];
        if (lockDuration == 0) {
            revert APIARY__LOCK_DURATION_NOT_SET();
        }

        // Transfer LP tokens from sender
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        // Approve farm
        _approveTokenIfNeeded(lpToken, farm, amount);

        // Get stake count before to identify new stake
        IKodiakFarm farmContract = IKodiakFarm(farm);
        uint256 stakeCountBefore = farmContract.lockedStakesOf(address(this)).length;

        // Stake with configured lock duration
        farmContract.stakeLocked(amount, lockDuration);

        // Get the new kek_id from the stakes array (last element)
        IKodiakFarm.LockedStake[] memory stakes = farmContract.lockedStakesOf(address(this));
        require(stakes.length > stakeCountBefore, "Stake not created");
        kekId = stakes[stakes.length - 1].kek_id;

        // Track the stake
        lpStakeIds[lpToken].push(kekId);
        isOurStake[kekId] = true;
        stakeIdToLP[kekId] = lpToken;

        emit LPStaked(lpToken, farm, amount, kekId, lockDuration);
    }

    /**
     * @notice Unstake a specific locked stake by kek_id
     * @dev Only works after lock period expires (unless farm has stakesUnlocked)
     * @param lpToken LP token address
     * @param kekId The unique identifier of the stake to withdraw
     * @return amount Amount of LP tokens withdrawn
     */
    function unstakeLP(address lpToken, bytes32 kekId)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 amount)
    {
        return _unstakeLP(lpToken, kekId, msg.sender);
    }

    /**
     * @notice Unstake a specific locked stake to a recipient
     * @param lpToken LP token address
     * @param kekId The unique identifier of the stake to withdraw
     * @param recipient Address to receive unstaked LP tokens
     * @return amount Amount of LP tokens withdrawn
     */
    function unstakeLPTo(address lpToken, bytes32 kekId, address recipient)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 amount)
    {
        return _unstakeLP(lpToken, kekId, recipient);
    }

    /**
     * @notice Internal unstake implementation for a single stake
     */
    function _unstakeLP(address lpToken, bytes32 kekId, address recipient) 
        internal 
        returns (uint256 amount) 
    {
        if (recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        if (!isOurStake[kekId]) {
            revert APIARY__NOT_OUR_STAKE();
        }

        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        // Get LP balance before withdrawal
        uint256 balanceBefore = IERC20(lpToken).balanceOf(address(this));

        // Withdraw the specific stake
        IKodiakFarm(farm).withdrawLocked(kekId);

        // Calculate amount received
        amount = IERC20(lpToken).balanceOf(address(this)) - balanceBefore;

        // Clean up tracking
        _removeStakeId(lpToken, kekId);
        isOurStake[kekId] = false;
        delete stakeIdToLP[kekId];

        // Transfer LP tokens to recipient
        if (amount > 0) {
            IERC20(lpToken).safeTransfer(recipient, amount);
        }

        emit LPUnstaked(lpToken, farm, amount, kekId);
    }

    /**
     * @notice Withdraw all expired stakes for an LP token
     * @dev Only withdraws stakes where ending_timestamp has passed
     * @param lpToken LP token address
     * @return totalAmount Total LP tokens withdrawn
     */
    function unstakeAllExpired(address lpToken)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 totalAmount)
    {
        return _unstakeAllExpired(lpToken, msg.sender);
    }

    /**
     * @notice Withdraw all expired stakes for an LP token to a recipient
     * @param lpToken LP token address
     * @param recipient Address to receive unstaked LP tokens
     * @return totalAmount Total LP tokens withdrawn
     */
    function unstakeAllExpiredTo(address lpToken, address recipient)
        external
        onlyYieldManager
        whenNotPaused
        nonReentrant
        returns (uint256 totalAmount)
    {
        return _unstakeAllExpired(lpToken, recipient);
    }

    /**
     * @notice Internal implementation for withdrawing all expired stakes
     */
    function _unstakeAllExpired(address lpToken, address recipient) 
        internal 
        returns (uint256 totalAmount) 
    {
        if (recipient == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        // Get LP balance before withdrawal
        uint256 balanceBefore = IERC20(lpToken).balanceOf(address(this));

        // Withdraw all expired stakes at once
        IKodiakFarm(farm).withdrawLockedAll();

        // Calculate total amount received
        totalAmount = IERC20(lpToken).balanceOf(address(this)) - balanceBefore;

        // Sync our tracking with actual farm state
        uint256 stakesWithdrawn = _syncStakeIds(lpToken);

        // Transfer LP tokens to recipient
        if (totalAmount > 0) {
            IERC20(lpToken).safeTransfer(recipient, totalAmount);
        }

        emit AllExpiredLPUnstaked(lpToken, farm, totalAmount, stakesWithdrawn);
    }

    /**
     * @notice Claim rewards from staked LP tokens
     * @param lpToken LP token address
     * @return rewardTokens Array of reward token addresses
     * @return rewardAmounts Array of reward amounts claimed
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
     * @return rewardAmounts Array of reward amounts claimed
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

        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        IKodiakFarm farmContract = IKodiakFarm(farm);

        // Get all reward tokens
        rewardTokens = farmContract.getAllRewardTokens();
        uint256 rewardCount = rewardTokens.length;

        // Get balances before claim
        uint256[] memory balancesBefore = new uint256[](rewardCount);
        for (uint256 i = 0; i < rewardCount; i++) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        // Claim all rewards
        farmContract.getReward();

        // Calculate received amounts and transfer to recipient
        rewardAmounts = new uint256[](rewardCount);
        for (uint256 i = 0; i < rewardCount; i++) {
            uint256 balanceAfter = IERC20(rewardTokens[i]).balanceOf(address(this));
            rewardAmounts[i] = balanceAfter - balancesBefore[i];

            if (rewardAmounts[i] > 0) {
                IERC20(rewardTokens[i]).safeTransfer(recipient, rewardAmounts[i]);
            }
        }

        totalRewardsClaimed++;

        emit RewardsClaimed(lpToken, farm, rewardTokens, rewardAmounts);
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
     * @notice Get staked LP balance for a token (total locked liquidity)
     * @param lpToken LP token address
     * @return balance Total locked LP balance
     */
    function getStakedBalance(address lpToken) external view returns (uint256 balance) {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return 0;
        }

        balance = IKodiakFarm(farm).lockedLiquidityOf(address(this));
    }

    /**
     * @notice Get all stake IDs for an LP token
     * @param lpToken LP token address
     * @return Array of kek_ids for all active stakes
     */
    function getStakeIds(address lpToken) external view returns (bytes32[] memory) {
        return lpStakeIds[lpToken];
    }

    /**
     * @notice Get detailed stake info by kek_id
     * @param lpToken LP token address
     * @param kekId The unique stake identifier
     * @return stake The LockedStake struct with all details
     */
    function getStakeInfo(address lpToken, bytes32 kekId) 
        external 
        view 
        returns (IKodiakFarm.LockedStake memory stake) 
    {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        IKodiakFarm.LockedStake[] memory allStakes = IKodiakFarm(farm).lockedStakesOf(address(this));
        for (uint256 i = 0; i < allStakes.length; i++) {
            if (allStakes[i].kek_id == kekId) {
                return allStakes[i];
            }
        }
        revert APIARY__NOT_OUR_STAKE();
    }

    /**
     * @notice Get all stakes that have expired and can be withdrawn
     * @param lpToken LP token address
     * @return expiredKekIds Array of kek_ids for expired stakes
     * @return totalExpiredLiquidity Total LP that can be withdrawn
     */
    function getExpiredStakes(address lpToken) 
        external 
        view 
        returns (bytes32[] memory expiredKekIds, uint256 totalExpiredLiquidity) 
    {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return (new bytes32[](0), 0);
        }

        IKodiakFarm.LockedStake[] memory allStakes = IKodiakFarm(farm).lockedStakesOf(address(this));
        
        // First pass: count expired stakes
        uint256 expiredCount = 0;
        for (uint256 i = 0; i < allStakes.length; i++) {
            if (block.timestamp >= allStakes[i].ending_timestamp) {
                expiredCount++;
            }
        }

        // Second pass: populate array
        expiredKekIds = new bytes32[](expiredCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < allStakes.length; i++) {
            if (block.timestamp >= allStakes[i].ending_timestamp) {
                expiredKekIds[idx] = allStakes[i].kek_id;
                totalExpiredLiquidity += allStakes[i].liquidity;
                idx++;
            }
        }
    }

    /**
     * @notice Get total staked LP for a token (alias for totalStakedLP view)
     * @param lpToken LP token address
     * @return Total locked LP tokens
     */
    function totalStakedLP(address lpToken) external view returns (uint256) {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return 0;
        }
        return IKodiakFarm(farm).lockedLiquidityOf(address(this));
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
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return (new address[](0), new uint256[](0));
        }

        IKodiakFarm farmContract = IKodiakFarm(farm);
        rewardTokens = farmContract.getAllRewardTokens();
        rewardAmounts = farmContract.earned(address(this));
    }

    /**
     * @notice Get farm configuration info
     * @param lpToken LP token address
     * @return minLock Minimum lock time in seconds
     * @return maxMultiplierLock Lock time for maximum multiplier
     * @return maxMultiplier Maximum reward multiplier (1e18 = 1x)
     * @return isPaused Whether staking is paused
     * @return areStakesUnlocked Whether early withdrawal is allowed
     */
    function getFarmConfig(address lpToken)
        external
        view
        returns (
            uint256 minLock,
            uint256 maxMultiplierLock,
            uint256 maxMultiplier,
            bool isPaused,
            bool areStakesUnlocked
        )
    {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return (0, 0, 0, true, false);
        }

        IKodiakFarm farmContract = IKodiakFarm(farm);
        minLock = farmContract.lock_time_min();
        maxMultiplierLock = farmContract.lock_time_for_max_multiplier();
        maxMultiplier = farmContract.lock_max_multiplier();
        isPaused = farmContract.stakingPaused();
        areStakesUnlocked = farmContract.stakesUnlocked();
    }

    /**
     * @notice Get lock multiplier for a specific duration
     * @param lpToken LP token address
     * @param secs Lock duration in seconds
     * @return multiplier The reward multiplier (1e18 = 1x)
     */
    function getLockMultiplier(address lpToken, uint256 secs) external view returns (uint256 multiplier) {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return 0;
        }
        return IKodiakFarm(farm).lockMultiplier(secs);
    }

    /**
     * @notice Get combined weight for adapter in farm (includes multipliers)
     * @param lpToken LP token address
     * @return weight Combined weight value
     */
    function getCombinedWeight(address lpToken) external view returns (uint256 weight) {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return 0;
        }
        return IKodiakFarm(farm).combinedWeightOf(address(this));
    }

    /**
     * @notice Get the configured lock duration for an LP token
     * @param lpToken LP token address
     * @return Duration in seconds
     */
    function getLockDuration(address lpToken) external view returns (uint256) {
        return lpLockDuration[lpToken];
    }

    /**
     * @notice Get farm address for LP token (replaces lpToGauge)
     * @param lpToken LP token address
     * @return Farm contract address
     */
    function lpToGauge(address lpToken) external view returns (address) {
        return lpToFarm[lpToken];
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
     * @notice Register farm for LP token staking
     * @dev Replaces the old registerGauge function for locked staking model
     * @param lpToken LP token address
     * @param farm Farm contract address
     */
    function registerFarm(address lpToken, address farm) external onlyOwner {
        if (lpToken == address(0) || farm == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        // Validate farm accepts this LP token
        require(IKodiakFarm(farm).stakingToken() == lpToken, "Farm LP mismatch");

        lpToFarm[lpToken] = farm;

        emit FarmRegistered(lpToken, farm);
    }

    /**
     * @notice Alias for registerFarm (backward compatibility)
     */
    function registerGauge(address lpToken, address farm) external onlyOwner {
        if (lpToken == address(0) || farm == address(0)) {
            revert APIARY__ZERO_ADDRESS();
        }

        require(IKodiakFarm(farm).stakingToken() == lpToken, "Farm LP mismatch");

        lpToFarm[lpToken] = farm;

        emit FarmRegistered(lpToken, farm);
    }

    /**
     * @notice Set lock duration for staking LP tokens
     * @dev Must be >= farm's minimum lock time
     * @param lpToken LP token address
     * @param _seconds Lock duration in seconds
     * 
     * Lock Duration Guide:
     * - Minimum: farm.lock_time_min() (usually 7 days)
     * - For max rewards: farm.lock_time_for_max_multiplier() (usually 365 days)
     * - Final value depends on partnership deal negotiation
     */
    function setLockDuration(address lpToken, uint256 _seconds) external onlyOwner {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            revert APIARY__FARM_NOT_REGISTERED();
        }

        // Validate against farm's minimum lock time
        uint256 minLock = IKodiakFarm(farm).lock_time_min();
        if (_seconds < minLock) {
            revert APIARY__LOCK_DURATION_TOO_SHORT();
        }

        uint256 oldDuration = lpLockDuration[lpToken];
        lpLockDuration[lpToken] = _seconds;

        emit LockDurationUpdated(lpToken, oldDuration, _seconds);
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

    /**
     * @notice Remove a specific stake ID from tracking array
     * @param lpToken LP token address
     * @param kekId The stake ID to remove
     */
    function _removeStakeId(address lpToken, bytes32 kekId) internal {
        bytes32[] storage stakeIds = lpStakeIds[lpToken];
        uint256 length = stakeIds.length;
        
        for (uint256 i = 0; i < length; i++) {
            if (stakeIds[i] == kekId) {
                // Move last element to this position and pop
                stakeIds[i] = stakeIds[length - 1];
                stakeIds.pop();
                return;
            }
        }
    }

    /**
     * @notice Sync tracked stake IDs with actual farm state
     * @dev Called after withdrawLockedAll() to clean up withdrawn stakes
     * @param lpToken LP token address
     * @return removedCount Number of stakes that were removed from tracking
     */
    function _syncStakeIds(address lpToken) internal returns (uint256 removedCount) {
        address farm = lpToFarm[lpToken];
        if (farm == address(0)) {
            return 0;
        }

        // Get current stakes from farm
        IKodiakFarm.LockedStake[] memory currentStakes = IKodiakFarm(farm).lockedStakesOf(address(this));
        
        // Build a set of current kek_ids for O(1) lookup
        // Using a simple array check since stake count is typically small
        bytes32[] storage trackedIds = lpStakeIds[lpToken];
        
        // Create new array with only valid stakes
        bytes32[] memory validIds = new bytes32[](currentStakes.length);
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < currentStakes.length; i++) {
            bytes32 kekId = currentStakes[i].kek_id;
            if (isOurStake[kekId]) {
                validIds[validCount] = kekId;
                validCount++;
            }
        }

        // Calculate removed count
        removedCount = trackedIds.length > validCount ? trackedIds.length - validCount : 0;

        // Clean up isOurStake and stakeIdToLP for removed stakes
        for (uint256 i = 0; i < trackedIds.length; i++) {
            bytes32 kekId = trackedIds[i];
            bool stillExists = false;
            
            for (uint256 j = 0; j < validCount; j++) {
                if (validIds[j] == kekId) {
                    stillExists = true;
                    break;
                }
            }
            
            if (!stillExists) {
                isOurStake[kekId] = false;
                delete stakeIdToLP[kekId];
            }
        }

        // Replace tracked array with valid stakes only
        delete lpStakeIds[lpToken];
        for (uint256 i = 0; i < validCount; i++) {
            lpStakeIds[lpToken].push(validIds[i]);
        }
    }
}
