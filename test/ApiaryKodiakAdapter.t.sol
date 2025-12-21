// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ApiaryKodiakAdapter Test Cases
 * @notice Comprehensive test coverage for Kodiak DEX adapter
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Swap Operations
 * 3. Liquidity Operations
 * 4. LP Staking Operations
 * 5. Access Control
 * 6. Edge Cases
 * 7. Emergency Functions
 * 8. View Functions
 * 9. Security Tests
 */

import { Test } from "forge-std/Test.sol";
import { ApiaryKodiakAdapter } from "../src/ApiaryKodiakAdapter.sol";
import { IKodiakRouter } from "../src/interfaces/IKodiakRouter.sol";
import { IKodiakFactory } from "../src/interfaces/IKodiakFactory.sol";
import { IKodiakFarm } from "../src/interfaces/IKodiakFarm.sol";
import { IKodiakPair } from "../src/interfaces/IKodiakPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
                            MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 is IERC20 {
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private totalSupplyAmount;
    string public name;
    string public symbol;
    uint8 public decimals;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupplyAmount += amount;
    }
    
    function totalSupply() external view returns (uint256) {
        return totalSupplyAmount;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        
        return true;
    }
}

contract MockKodiakPair is MockERC20, IKodiakPair {
    address public token0Address;
    address public token1Address;
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;
    
    constructor(address _token0, address _token1) MockERC20("Kodiak LP", "KDK-LP", 18) {
        token0Address = _token0;
        token1Address = _token1;
    }
    
    function token0() external view returns (address) {
        return token0Address;
    }
    
    function token1() external view returns (address) {
        return token1Address;
    }
    
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
    }
    
    function price0CumulativeLast() external view returns (uint256) {
        return 0;
    }
    
    function price1CumulativeLast() external view returns (uint256) {
        return 0;
    }
    
    function kLast() external view returns (uint256) {
        return 0;
    }
    
    function mint(address to) external returns (uint256 liquidity) {
        // Simplified: mint 1:1 with smallest reserve
        liquidity = reserve0 < reserve1 ? reserve0 : reserve1;
        MockERC20(address(this)).mint(to, liquidity);
    }
    
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 balance = this.balanceOf(address(this));
        amount0 = balance;
        amount1 = balance;
        
        MockERC20(token0Address).transfer(to, amount0);
        MockERC20(token1Address).transfer(to, amount1);
    }
    
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
        if (amount0Out > 0) MockERC20(token0Address).transfer(to, amount0Out);
        if (amount1Out > 0) MockERC20(token1Address).transfer(to, amount1Out);
    }
    
    function skim(address) external {}
    function sync() external {}
}

contract MockKodiakFactory is IKodiakFactory {
    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairsArray;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        pair = address(new MockKodiakPair(token0, token1));
        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairsArray.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairsArray.length);
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = pairs[token0][token1];
    }
    
    function allPairs(uint256 index) external view returns (address pair) {
        pair = allPairsArray[index];
    }
    
    function allPairsLength() external view returns (uint256) {
        return allPairsArray.length;
    }
    
    function feeTo() external pure returns (address) {
        return address(0);
    }
    
    function feeToSetter() external pure returns (address) {
        return address(0);
    }
}

contract MockKodiakRouter is IKodiakRouter {
    MockKodiakFactory public factoryContract;
    
    constructor(address _factory) {
        factoryContract = MockKodiakFactory(_factory);
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Deadline expired");
        require(path.length >= 2, "Invalid path");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        // Simplified: 1:1 swap minus 0.3% fee
        for (uint256 i = 0; i < path.length - 1; i++) {
            uint256 amountOut = (amounts[i] * 997) / 1000; // 0.3% fee
            amounts[i + 1] = amountOut;
        }
        
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output");
        
        // Transfer tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amounts[amounts.length - 1]);
    }
    
    function swapTokensForExactTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external pure returns (uint256[] memory) {
        revert("Not implemented");
    }
    
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(deadline >= block.timestamp, "Deadline expired");
        
        uint256 amountOut = (amountIn * 997) / 1000;
        require(amountOut >= amountOutMin, "Insufficient output");
        
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amountOut);
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "Deadline expired");
        
        // Get or create pair
        address pair = factoryContract.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factoryContract.createPair(tokenA, tokenB);
        }
        
        // Simplified: use desired amounts
        amountA = amountADesired;
        amountB = amountBDesired;
        
        require(amountA >= amountAMin, "Insufficient A");
        require(amountB >= amountBMin, "Insufficient B");
        
        // Transfer tokens
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        
        // Mint LP tokens (simplified)
        liquidity = amountA < amountB ? amountA : amountB;
        MockKodiakPair(pair).mint(to, liquidity);
        MockKodiakPair(pair).setReserves(uint112(amountA), uint112(amountB));
    }
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Deadline expired");
        
        address pair = factoryContract.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair doesn't exist");
        
        // Transfer LP tokens to pair
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        
        // Burn (simplified: 1:1 return)
        amountA = liquidity;
        amountB = liquidity;
        
        require(amountA >= amountAMin, "Insufficient A");
        require(amountB >= amountBMin, "Insufficient B");
        
        MockERC20(tokenA).transfer(to, amountA);
        MockERC20(tokenB).transfer(to, amountB);
    }
    
    function factory() external view returns (address) {
        return address(factoryContract);
    }
    
    function WETH() external pure returns (address) {
        return address(0);
    }
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = (amounts[i] * 997) / 1000; // 0.3% fee
        }
    }
    
    function getAmountsIn(uint256, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
    }
    
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB) {
        amountB = (amountA * reserveB) / reserveA;
    }
}

contract MockKodiakFarm is IKodiakFarm {
    address public stakingTokenAddress;
    address[] public rewardTokensArray;
    uint256[] public rewardRatesArray;
    
    // Stake tracking
    mapping(address => LockedStake[]) internal userStakes;
    mapping(address => uint256) public lockedLiquidityByUser;
    mapping(address => uint256) public combinedWeightByUser;
    mapping(address => uint256[]) public earnedByUser;
    
    uint256 public totalLockedLiquidity;
    uint256 public nonce;
    
    // Config
    uint256 public minLockTime = 7 days;
    uint256 public maxLockTime = 365 days;
    uint256 public maxMultiplier = 3e18; // 3x
    bool public isPaused;
    bool public isRewardsPaused;
    bool public isUnlocked;
    uint256 public periodFinishTime;
    
    constructor(address _stakingToken, address[] memory _rewardTokens) {
        stakingTokenAddress = _stakingToken;
        rewardTokensArray = _rewardTokens;
        rewardRatesArray = new uint256[](_rewardTokens.length);
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardRatesArray[i] = 1e18; // 1 token per second
        }
        periodFinishTime = block.timestamp + 365 days;
    }
    
    function stakeLocked(uint256 liquidity, uint256 secs) external returns (bytes32 kek_id) {
        require(!isPaused, "Staking paused");
        require(secs >= minLockTime, "Lock too short");
        
        IERC20(stakingTokenAddress).transferFrom(msg.sender, address(this), liquidity);
        
        // Generate unique kek_id
        nonce++;
        kek_id = keccak256(abi.encodePacked(msg.sender, block.timestamp, nonce));
        
        // Calculate multiplier
        uint256 multiplier = lockMultiplier(secs);
        
        // Create stake
        LockedStake memory stake = LockedStake({
            kek_id: kek_id,
            start_timestamp: block.timestamp,
            liquidity: liquidity,
            ending_timestamp: block.timestamp + secs,
            lock_multiplier: multiplier
        });
        
        userStakes[msg.sender].push(stake);
        lockedLiquidityByUser[msg.sender] += liquidity;
        combinedWeightByUser[msg.sender] += (liquidity * multiplier) / 1e18;
        totalLockedLiquidity += liquidity;
        
        emit StakeLocked(msg.sender, liquidity, secs, kek_id, msg.sender);
    }
    
    function withdrawLocked(bytes32 kek_id) external {
        LockedStake[] storage stakes = userStakes[msg.sender];
        bool found = false;
        uint256 liquidity;
        
        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].kek_id == kek_id) {
                require(isUnlocked || block.timestamp >= stakes[i].ending_timestamp, "Stake not expired");
                
                liquidity = stakes[i].liquidity;
                uint256 multiplier = stakes[i].lock_multiplier;
                
                // Remove stake (swap with last and pop)
                stakes[i] = stakes[stakes.length - 1];
                stakes.pop();
                
                lockedLiquidityByUser[msg.sender] -= liquidity;
                combinedWeightByUser[msg.sender] -= (liquidity * multiplier) / 1e18;
                totalLockedLiquidity -= liquidity;
                
                found = true;
                break;
            }
        }
        
        require(found, "Stake not found");
        
        IERC20(stakingTokenAddress).transfer(msg.sender, liquidity);
        emit WithdrawLocked(msg.sender, liquidity, kek_id, msg.sender);
    }
    
    function withdrawLockedAll() external {
        LockedStake[] storage stakes = userStakes[msg.sender];
        uint256 totalWithdrawn;
        
        // Iterate backwards to safely remove
        for (int256 i = int256(stakes.length) - 1; i >= 0; i--) {
            uint256 idx = uint256(i);
            if (isUnlocked || block.timestamp >= stakes[idx].ending_timestamp) {
                uint256 liquidity = stakes[idx].liquidity;
                bytes32 kek_id = stakes[idx].kek_id;
                uint256 multiplier = stakes[idx].lock_multiplier;
                
                totalWithdrawn += liquidity;
                lockedLiquidityByUser[msg.sender] -= liquidity;
                combinedWeightByUser[msg.sender] -= (liquidity * multiplier) / 1e18;
                totalLockedLiquidity -= liquidity;
                
                // Remove stake
                stakes[idx] = stakes[stakes.length - 1];
                stakes.pop();
                
                emit WithdrawLocked(msg.sender, liquidity, kek_id, msg.sender);
            }
        }
        
        if (totalWithdrawn > 0) {
            IERC20(stakingTokenAddress).transfer(msg.sender, totalWithdrawn);
        }
    }
    
    function withdrawLockedMultiple(bytes32[] calldata kek_ids) external {
        for (uint256 i = 0; i < kek_ids.length; i++) {
            this.withdrawLocked(kek_ids[i]);
        }
    }
    
    function emergencyWithdraw(bytes32 kek_id) external {
        // Same as withdrawLocked but ignores lock time (with penalty in real impl)
        LockedStake[] storage stakes = userStakes[msg.sender];
        
        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].kek_id == kek_id) {
                uint256 liquidity = stakes[i].liquidity;
                uint256 multiplier = stakes[i].lock_multiplier;
                
                stakes[i] = stakes[stakes.length - 1];
                stakes.pop();
                
                lockedLiquidityByUser[msg.sender] -= liquidity;
                combinedWeightByUser[msg.sender] -= (liquidity * multiplier) / 1e18;
                totalLockedLiquidity -= liquidity;
                
                // In real impl, there would be a penalty
                IERC20(stakingTokenAddress).transfer(msg.sender, liquidity);
                emit WithdrawLocked(msg.sender, liquidity, kek_id, msg.sender);
                return;
            }
        }
        revert("Stake not found");
    }
    
    function getReward() external returns (uint256[] memory rewardAmounts) {
        require(!isRewardsPaused, "Rewards paused");
        
        rewardAmounts = new uint256[](rewardTokensArray.length);
        
        for (uint256 i = 0; i < rewardTokensArray.length; i++) {
            uint256 reward = earnedByUser[msg.sender].length > i ? earnedByUser[msg.sender][i] : 0;
            if (reward > 0) {
                earnedByUser[msg.sender][i] = 0;
                IERC20(rewardTokensArray[i]).transfer(msg.sender, reward);
                rewardAmounts[i] = reward;
                emit RewardPaid(msg.sender, rewardTokensArray[i], reward, msg.sender);
            }
        }
    }
    
    // View functions
    function lockedLiquidityOf(address account) external view returns (uint256) {
        return lockedLiquidityByUser[account];
    }
    
    function lockedStakesOf(address account) external view returns (LockedStake[] memory) {
        return userStakes[account];
    }
    
    function earned(address account) external view returns (uint256[] memory) {
        if (earnedByUser[account].length == 0) {
            return new uint256[](rewardTokensArray.length);
        }
        return earnedByUser[account];
    }
    
    function combinedWeightOf(address account) external view returns (uint256) {
        return combinedWeightByUser[account];
    }
    
    function lockMultiplier(uint256 secs) public view returns (uint256 multiplier) {
        if (secs <= minLockTime) {
            return 1e18; // 1x
        }
        if (secs >= maxLockTime) {
            return maxMultiplier;
        }
        // Linear interpolation
        uint256 range = maxLockTime - minLockTime;
        uint256 elapsed = secs - minLockTime;
        uint256 multiplierRange = maxMultiplier - 1e18;
        multiplier = 1e18 + (multiplierRange * elapsed) / range;
    }
    
    function getAllRewardTokens() external view returns (address[] memory) {
        return rewardTokensArray;
    }
    
    function getAllRewardRates() external view returns (uint256[] memory) {
        return rewardRatesArray;
    }
    
    function stakingToken() external view returns (address) {
        return stakingTokenAddress;
    }
    
    function lock_time_min() external view returns (uint256) {
        return minLockTime;
    }
    
    function lock_time_for_max_multiplier() external view returns (uint256) {
        return maxLockTime;
    }
    
    function lock_max_multiplier() external view returns (uint256) {
        return maxMultiplier;
    }
    
    function stakingPaused() external view returns (bool) {
        return isPaused;
    }
    
    function rewardsCollectionPaused() external view returns (bool) {
        return isRewardsPaused;
    }
    
    function stakesUnlocked() external view returns (bool) {
        return isUnlocked;
    }
    
    function totalLiquidityLocked() external view returns (uint256) {
        return totalLockedLiquidity;
    }
    
    function periodFinish() external view returns (uint256) {
        return periodFinishTime;
    }
    
    // Test helpers
    function setEarnedRewards(address account, uint256[] memory amounts) external {
        earnedByUser[account] = amounts;
    }
    
    function setStakesUnlocked(bool unlocked) external {
        isUnlocked = unlocked;
    }
    
    function setMinLockTime(uint256 _minLockTime) external {
        minLockTime = _minLockTime;
    }
}

/*//////////////////////////////////////////////////////////////
                            MAIN TEST CONTRACT
//////////////////////////////////////////////////////////////*/

contract ApiaryKodiakAdapterTest is Test {
    ApiaryKodiakAdapter public adapter;
    MockKodiakRouter public router;
    MockKodiakFactory public factory;
    MockKodiakFarm public farm;
    MockERC20 public honey;
    MockERC20 public apiary;
    MockERC20 public xkdk;
    MockERC20 public bgt;
    
    address public owner = address(1);
    address public yieldManager = address(2);
    address public treasury = address(3);
    address public user = address(4);
    
    address public lpToken;
    
    // Lock duration for testing (7 days minimum)
    uint256 public constant TEST_LOCK_DURATION = 7 days;
    
    function setUp() public {
        // Deploy mock tokens
        honey = new MockERC20("HONEY", "HONEY", 18);
        apiary = new MockERC20("APIARY", "APIARY", 18);
        xkdk = new MockERC20("xKDK", "xKDK", 18);
        bgt = new MockERC20("BGT", "BGT", 18);
        
        // Deploy Kodiak mocks
        factory = new MockKodiakFactory();
        router = new MockKodiakRouter(address(factory));
        
        // Create APIARY/HONEY pair
        factory.createPair(address(apiary), address(honey));
        lpToken = factory.getPair(address(apiary), address(honey));
        
        // Setup farm with rewards
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(xkdk);
        rewardTokens[1] = address(bgt);
        farm = new MockKodiakFarm(lpToken, rewardTokens);
        
        // Deploy adapter
        vm.prank(owner);
        adapter = new ApiaryKodiakAdapter(
            address(router),
            address(factory),
            address(honey),
            address(apiary),
            treasury,
            yieldManager,
            owner
        );
        
        // Mint tokens for testing
        honey.mint(yieldManager, 100000e18);
        apiary.mint(yieldManager, 100000e18);
        honey.mint(address(router), 100000e18);
        apiary.mint(address(router), 100000e18);
        xkdk.mint(address(farm), 10000e18);
        bgt.mint(address(farm), 10000e18);
        
        // Setup pair reserves
        MockKodiakPair(lpToken).setReserves(50000e18, 50000e18);
        
        // Register farm and set lock duration
        vm.startPrank(owner);
        adapter.registerFarm(lpToken, address(farm));
        adapter.setLockDuration(lpToken, TEST_LOCK_DURATION);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        1. DEPLOYMENT & INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    
    function testDeployment() public {
        assertEq(address(adapter.kodiakRouter()), address(router));
        assertEq(address(adapter.kodiakFactory()), address(factory));
        assertEq(address(adapter.honey()), address(honey));
        assertEq(address(adapter.apiary()), address(apiary));
        assertEq(adapter.yieldManager(), yieldManager);
        assertEq(adapter.treasury(), treasury);
        assertEq(adapter.owner(), owner);
        assertEq(adapter.defaultSlippageBps(), 50);
        assertEq(adapter.defaultDeadlineOffset(), 300);
    }
    
    function testDeploymentRevertsZeroAddress() public {
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__ZERO_ADDRESS.selector);
        new ApiaryKodiakAdapter(address(0), address(factory), address(honey), address(apiary), treasury, yieldManager, owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                            2. SWAP OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    function testSwap() public {
        uint256 amountIn = 100e18;
        uint256 expectedOut = (amountIn * 997) / 1000; // 0.3% fee
        uint256 minAmountOut = (expectedOut * 9950) / 10000; // 0.5% slippage
        
        vm.startPrank(yieldManager);
        honey.approve(address(adapter), amountIn);
        
        uint256 amountOut = adapter.swap(
            address(honey),
            address(apiary),
            amountIn,
            minAmountOut,
            treasury
        );
        vm.stopPrank();
        
        assertGt(amountOut, 0);
        assertGe(amountOut, minAmountOut);
        assertEq(adapter.totalSwapsExecuted(), 1);
    }
    
    function testSwapRevertsNonYieldManager() public {
        vm.prank(user);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__ONLY_YIELD_MANAGER.selector);
        adapter.swap(address(honey), address(apiary), 100e18, 99e18, treasury);
    }
    
    function testSwapRevertsZeroAmount() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__INVALID_AMOUNT.selector);
        adapter.swap(address(honey), address(apiary), 0, 0, treasury);
    }
    
    function testSwapRevertsBelowMinimum() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__BELOW_MINIMUM.selector);
        adapter.swap(address(honey), address(apiary), 0.001e18, 0.001e18, treasury);
    }
    
    function testSwapRevertsPoolDoesNotExist() public {
        MockERC20 fakeToken = new MockERC20("FAKE", "FAKE", 18);
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__POOL_DOES_NOT_EXIST.selector);
        adapter.swap(address(honey), address(fakeToken), 100e18, 99e18, treasury);
    }
    
    function testSwapWithDeadline() public {
        uint256 amountIn = 100e18;
        uint256 minAmountOut = 99e18;
        uint256 deadline = block.timestamp + 600;
        
        vm.startPrank(yieldManager);
        honey.approve(address(adapter), amountIn);
        
        adapter.swapWithDeadline(
            address(honey),
            address(apiary),
            amountIn,
            minAmountOut,
            treasury,
            deadline
        );
        vm.stopPrank();
        
        assertEq(adapter.totalSwapsExecuted(), 1);
    }
    
    function testSwapWithDeadlineRevertsExpired() public {
        uint256 deadline = block.timestamp - 1;
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__DEADLINE_EXPIRED.selector);
        adapter.swapWithDeadline(
            address(honey),
            address(apiary),
            100e18,
            99e18,
            treasury,
            deadline
        );
    }
    
    function testFuzzSwap(uint256 amountIn) public {
        amountIn = bound(amountIn, adapter.minSwapAmount(), 10000e18);
        
        uint256 expectedOut = (amountIn * 997) / 1000;
        uint256 minAmountOut = (expectedOut * 9950) / 10000;
        
        vm.startPrank(yieldManager);
        honey.approve(address(adapter), amountIn);
        
        uint256 amountOut = adapter.swap(
            address(honey),
            address(apiary),
            amountIn,
            minAmountOut,
            treasury
        );
        vm.stopPrank();
        
        assertGe(amountOut, minAmountOut);
    }
    
    /*//////////////////////////////////////////////////////////////
                        3. LIQUIDITY OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    function testAddLiquidity() public {
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        uint256 minLP = 900e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            minLP,
            treasury
        );
        vm.stopPrank();
        
        assertEq(actualAmountA, amountA);
        assertEq(actualAmountB, amountB);
        assertGe(liquidity, minLP);
        assertEq(adapter.totalLiquidityOps(), 1);
    }
    
    function testAddLiquidityRevertsZeroAmount() public {
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__INVALID_AMOUNT.selector);
        adapter.addLiquidity(
            address(apiary),
            address(honey),
            0,
            1000e18,
            100e18,
            treasury
        );
    }
    
    function testRemoveLiquidity() public {
        // First add liquidity
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        // Then remove liquidity
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        (uint256 receivedA, uint256 receivedB) = adapter.removeLiquidity(
            address(apiary),
            address(honey),
            liquidity,
            0,
            0,
            treasury
        );
        vm.stopPrank();
        
        assertGt(receivedA, 0);
        assertGt(receivedB, 0);
        assertEq(adapter.totalLiquidityOps(), 2); // add + remove
    }
    
    /*//////////////////////////////////////////////////////////////
                        4. LP STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    function testStakeLP() public {
        // Add liquidity first
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        // Stake LP
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        assertEq(adapter.totalStakedLP(lpToken), liquidity);
        assertEq(farm.lockedLiquidityOf(address(adapter)), liquidity);
        assertTrue(adapter.isOurStake(kekId));
        
        // Verify stake info
        bytes32[] memory stakeIds = adapter.getStakeIds(lpToken);
        assertEq(stakeIds.length, 1);
        assertEq(stakeIds[0], kekId);
    }
    
    function testStakeLPRevertsFarmNotRegistered() public {
        MockERC20 fakeLpToken = new MockERC20("FAKE-LP", "FAKE-LP", 18);
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__FARM_NOT_REGISTERED.selector);
        adapter.stakeLP(address(fakeLpToken), 100e18);
    }
    
    function testStakeLPRevertsLockDurationNotSet() public {
        // Create new LP/farm without lock duration set
        MockERC20 newLpToken = new MockERC20("NEW-LP", "NEW-LP", 18);
        address[] memory rewards = new address[](1);
        rewards[0] = address(xkdk);
        MockKodiakFarm newFarm = new MockKodiakFarm(address(newLpToken), rewards);
        
        vm.prank(owner);
        adapter.registerFarm(address(newLpToken), address(newFarm));
        // Note: lock duration not set
        
        newLpToken.mint(yieldManager, 1000e18);
        
        vm.startPrank(yieldManager);
        newLpToken.approve(address(adapter), 100e18);
        
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__LOCK_DURATION_NOT_SET.selector);
        adapter.stakeLP(address(newLpToken), 100e18);
        vm.stopPrank();
    }
    
    function testStakeLPWithDifferentLockDurations() public {
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Stake half
        bytes32 kekId1 = adapter.stakeLP(lpToken, liquidity / 2);
        vm.stopPrank();
        
        // Change lock duration
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 30 days);
        
        // Stake the other half with new duration
        vm.startPrank(yieldManager);
        bytes32 kekId2 = adapter.stakeLP(lpToken, liquidity / 2);
        vm.stopPrank();
        
        // Both stakes should exist
        bytes32[] memory stakeIds = adapter.getStakeIds(lpToken);
        assertEq(stakeIds.length, 2);
        assertTrue(kekId1 != kekId2);
    }
    
    function testUnstakeLP() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Warp time past lock expiration
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        // Unstake
        vm.prank(yieldManager);
        uint256 unstaked = adapter.unstakeLPTo(lpToken, kekId, treasury);
        
        assertEq(adapter.totalStakedLP(lpToken), 0);
        assertEq(IERC20(lpToken).balanceOf(treasury), liquidity);
        assertEq(unstaked, liquidity);
        assertFalse(adapter.isOurStake(kekId));
    }
    
    function testUnstakeLPRevertsBeforeLockExpires() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        
        // Try to unstake before lock expires
        vm.expectRevert("Stake not expired");
        adapter.unstakeLPTo(lpToken, kekId, treasury);
        vm.stopPrank();
    }
    
    function testUnstakeAllExpired() public {
        // Setup: Add liquidity and create multiple stakes
        uint256 amountA = 2000e18;
        uint256 amountB = 2000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Create two stakes
        bytes32 kekId1 = adapter.stakeLP(lpToken, liquidity / 2);
        bytes32 kekId2 = adapter.stakeLP(lpToken, liquidity / 2);
        vm.stopPrank();
        
        assertEq(adapter.getStakeIds(lpToken).length, 2);
        
        // Warp past lock expiration
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        // Unstake all expired
        vm.prank(yieldManager);
        uint256 totalUnstaked = adapter.unstakeAllExpiredTo(lpToken, treasury);
        
        assertEq(totalUnstaked, liquidity);
        assertEq(adapter.getStakeIds(lpToken).length, 0);
        assertEq(adapter.totalStakedLP(lpToken), 0);
    }
    
    function testUnstakeLPRevertsNotOurStake() public {
        bytes32 fakeKekId = keccak256("fake");
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__NOT_OUR_STAKE.selector);
        adapter.unstakeLP(lpToken, fakeKekId);
    }
    
    function testUnstakeLPRemovesFromTracking() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Verify stake is tracked
        assertTrue(adapter.isOurStake(kekId));
        assertEq(adapter.stakeIdToLP(kekId), lpToken);
        assertEq(adapter.getStakeIds(lpToken).length, 1);
        
        // Warp and unstake
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        vm.prank(yieldManager);
        adapter.unstakeLP(lpToken, kekId);
        
        // Verify tracking is cleaned up
        assertFalse(adapter.isOurStake(kekId));
        assertEq(adapter.stakeIdToLP(kekId), address(0));
        assertEq(adapter.getStakeIds(lpToken).length, 0);
    }
    
    function testUnstakeAllExpiredNothingExpiredReturnsZero() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // Try to unstake expired (nothing expired yet)
        uint256 unstaked = adapter.unstakeAllExpired(lpToken);
        vm.stopPrank();
        
        assertEq(unstaked, 0);
        // Stake should still exist
        assertEq(adapter.getStakeIds(lpToken).length, 1);
    }
    
    function testClaimLPRewards() public {
        // Setup: Add liquidity, stake, set rewards
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // Set rewards
        uint256[] memory rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 100e18;
        rewardAmounts[1] = 50e18;
        farm.setEarnedRewards(address(adapter), rewardAmounts);
        
        // Claim rewards
        (address[] memory rewardTokens, uint256[] memory amounts) = adapter.claimLPRewardsTo(lpToken, treasury);
        vm.stopPrank();
        
        assertEq(rewardTokens.length, 2);
        assertEq(amounts[0], 100e18); // xKDK
        assertEq(amounts[1], 50e18); // BGT
        assertEq(xkdk.balanceOf(treasury), 100e18);
        assertEq(bgt.balanceOf(treasury), 50e18);
        assertEq(adapter.totalRewardsClaimed(), 1);
    }
    
    function testClaimMultipleRewardTokens() public {
        // Setup: Add liquidity, stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // Set multiple rewards
        uint256[] memory rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 200e18; // xKDK
        rewardAmounts[1] = 100e18; // BGT
        farm.setEarnedRewards(address(adapter), rewardAmounts);
        
        // Claim all rewards
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimLPRewardsTo(lpToken, treasury);
        vm.stopPrank();
        
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(xkdk));
        assertEq(tokens[1], address(bgt));
        assertEq(amounts[0], 200e18);
        assertEq(amounts[1], 100e18);
    }
    
    function testClaimRewardsNoRewardsReturnsEmpty() public {
        // Setup: Add liquidity and stake, but no rewards
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // No rewards set - claim should return empty/zero amounts
        (address[] memory tokens, uint256[] memory amounts) = adapter.claimLPRewardsTo(lpToken, treasury);
        vm.stopPrank();
        
        assertEq(tokens.length, 2);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
    }
    
    function testGetExpiredStakes() public {
        // Setup: Create multiple stakes with same lock duration
        uint256 amountA = 2000e18;
        uint256 amountB = 2000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Create two stakes
        adapter.stakeLP(lpToken, liquidity / 2);
        adapter.stakeLP(lpToken, liquidity / 2);
        vm.stopPrank();
        
        // Check expired before time passes
        (bytes32[] memory expiredBefore, uint256 liquidityBefore) = adapter.getExpiredStakes(lpToken);
        assertEq(expiredBefore.length, 0);
        assertEq(liquidityBefore, 0);
        
        // Warp past lock
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        // Check expired after time passes
        (bytes32[] memory expiredAfter, uint256 liquidityAfter) = adapter.getExpiredStakes(lpToken);
        assertEq(expiredAfter.length, 2);
        assertEq(liquidityAfter, liquidity);
    }
    
    function testGetFarmConfig() public {
        (
            uint256 minLock,
            uint256 maxMultiplierLock,
            uint256 maxMultiplier,
            bool isPaused,
            bool areStakesUnlocked
        ) = adapter.getFarmConfig(lpToken);
        
        assertEq(minLock, 7 days);
        assertEq(maxMultiplierLock, 365 days);
        assertEq(maxMultiplier, 3e18); // 3x
        assertFalse(isPaused);
        assertFalse(areStakesUnlocked);
    }
    
    function testGetLockMultiplier() public {
        // Minimum lock gets 1x
        uint256 minMultiplier = adapter.getLockMultiplier(lpToken, 7 days);
        assertEq(minMultiplier, 1e18);
        
        // Max lock gets 3x
        uint256 maxMultiplier = adapter.getLockMultiplier(lpToken, 365 days);
        assertEq(maxMultiplier, 3e18);
    }
    
    function testSetLockDuration() public {
        uint256 newDuration = 14 days;
        
        vm.prank(owner);
        adapter.setLockDuration(lpToken, newDuration);
        
        assertEq(adapter.getLockDuration(lpToken), newDuration);
    }
    
    function testSetLockDurationRevertsBelowMinimum() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__LOCK_DURATION_TOO_SHORT.selector);
        adapter.setLockDuration(lpToken, 1 days); // Below 7 day minimum
    }
    
    function testSetLockDurationRevertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.setLockDuration(lpToken, 14 days);
    }
    
    function testStakeLPRevertsNonYieldManager() public {
        vm.prank(user);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__ONLY_YIELD_MANAGER.selector);
        adapter.stakeLP(lpToken, 100e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            5. ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/
    
    function testSetYieldManager() public {
        address newManager = address(5);
        
        vm.prank(owner);
        adapter.setYieldManager(newManager);
        
        assertEq(adapter.yieldManager(), newManager);
    }
    
    function testSetYieldManagerRevertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.setYieldManager(address(5));
    }
    
    function testSetTreasury() public {
        address newTreasury = address(6);
        
        vm.prank(owner);
        adapter.setTreasury(newTreasury);
        
        assertEq(adapter.treasury(), newTreasury);
    }
    
    function testRegisterFarm() public {
        MockERC20 newLpToken = new MockERC20("NEW-LP", "NEW-LP", 18);
        address[] memory rewards = new address[](1);
        rewards[0] = address(xkdk);
        MockKodiakFarm newFarm = new MockKodiakFarm(address(newLpToken), rewards);
        
        vm.prank(owner);
        adapter.registerFarm(address(newLpToken), address(newFarm));
        
        assertEq(adapter.lpToFarm(address(newLpToken)), address(newFarm));
        // backward compat alias
        assertEq(adapter.lpToGauge(address(newLpToken)), address(newFarm));
    }
    
    /*//////////////////////////////////////////////////////////////
                            6. EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function testSwapWhenPaused() public {
        vm.prank(owner);
        adapter.pause();
        
        vm.prank(yieldManager);
        vm.expectRevert();
        adapter.swap(address(honey), address(apiary), 100e18, 99e18, treasury);
    }
    
    function testUnpause() public {
        vm.startPrank(owner);
        adapter.pause();
        assertTrue(adapter.paused());
        
        adapter.unpause();
        assertFalse(adapter.paused());
        vm.stopPrank();
    }
    
    function testSetDefaultSlippage() public {
        vm.prank(owner);
        adapter.setDefaultSlippage(100); // 1%
        
        assertEq(adapter.defaultSlippageBps(), 100);
    }
    
    function testSetDefaultSlippageRevertsTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__SLIPPAGE_TOO_HIGH.selector);
        adapter.setDefaultSlippage(1001); // > 10%
    }
    
    /*//////////////////////////////////////////////////////////////
                            7. EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function testEmergencyWithdrawToken() public {
        // Send tokens to adapter (simulating stuck tokens)
        honey.mint(address(adapter), 100e18);
        
        uint256 treasuryBalanceBefore = honey.balanceOf(treasury);
        
        vm.prank(owner);
        adapter.emergencyWithdrawToken(address(honey), 100e18);
        
        assertEq(honey.balanceOf(treasury), treasuryBalanceBefore + 100e18);
        assertEq(honey.balanceOf(address(adapter)), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            8. VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function testGetExpectedSwapOutput() public {
        uint256 amountIn = 100e18;
        
        uint256 expectedOut = adapter.getExpectedSwapOutput(
            address(honey),
            address(apiary),
            amountIn
        );
        
        assertGt(expectedOut, 0);
        assertEq(expectedOut, (amountIn * 997) / 1000); // 0.3% fee
    }
    
    function testPoolExists() public {
        assertTrue(adapter.poolExists(address(apiary), address(honey)));
        
        MockERC20 fakeToken = new MockERC20("FAKE", "FAKE", 18);
        assertFalse(adapter.poolExists(address(apiary), address(fakeToken)));
    }
    
    function testGetStakedBalance() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        uint256 stakedBalance = adapter.getStakedBalance(lpToken);
        assertEq(stakedBalance, liquidity);
    }
    
    function testGetPendingRewards() public {
        // Setup: Add liquidity and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Set rewards
        uint256[] memory rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 100e18;
        rewardAmounts[1] = 50e18;
        farm.setEarnedRewards(address(adapter), rewardAmounts);
        
        (address[] memory rewardTokens, uint256[] memory amounts) = adapter.getPendingRewards(lpToken);
        
        assertEq(rewardTokens.length, 2);
        assertEq(amounts[0], 100e18);
        assertEq(amounts[1], 50e18);
    }
    
    function testGetStakeIdsReturnsAll() public {
        // Setup: Create multiple stakes
        uint256 amountA = 3000e18;
        uint256 amountB = 3000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Create 3 stakes
        bytes32 kekId1 = adapter.stakeLP(lpToken, liquidity / 3);
        bytes32 kekId2 = adapter.stakeLP(lpToken, liquidity / 3);
        bytes32 kekId3 = adapter.stakeLP(lpToken, liquidity / 3);
        vm.stopPrank();
        
        bytes32[] memory stakeIds = adapter.getStakeIds(lpToken);
        assertEq(stakeIds.length, 3);
        assertEq(stakeIds[0], kekId1);
        assertEq(stakeIds[1], kekId2);
        assertEq(stakeIds[2], kekId3);
    }
    
    function testGetStakeInfoValidKekId() public {
        // Setup: Create a stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Get stake info
        IKodiakFarm.LockedStake memory stake = adapter.getStakeInfo(lpToken, kekId);
        
        assertEq(stake.kek_id, kekId);
        assertEq(stake.liquidity, liquidity);
        assertEq(stake.start_timestamp, block.timestamp);
        assertEq(stake.ending_timestamp, block.timestamp + TEST_LOCK_DURATION);
        assertGe(stake.lock_multiplier, 1e18); // At least 1x
    }
    
    function testGetStakeInfoInvalidKekIdReverts() public {
        bytes32 fakeKekId = keccak256("fake");
        
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__NOT_OUR_STAKE.selector);
        adapter.getStakeInfo(lpToken, fakeKekId);
    }
    
    function testTotalStakedLPAfterMultipleStakes() public {
        // Setup: Create multiple stakes
        uint256 amountA = 3000e18;
        uint256 amountB = 3000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Stake in portions
        adapter.stakeLP(lpToken, 400e18);
        assertEq(adapter.totalStakedLP(lpToken), 400e18);
        
        adapter.stakeLP(lpToken, 300e18);
        assertEq(adapter.totalStakedLP(lpToken), 700e18);
        
        adapter.stakeLP(lpToken, 300e18);
        assertEq(adapter.totalStakedLP(lpToken), 1000e18);
        vm.stopPrank();
    }
    
    function testGetAdapterInfo() public {
        (
            address _yieldManager,
            address _treasury,
            uint256 _totalSwaps,
            uint256 _totalLiquidityOps,
            uint256 _totalRewards
        ) = adapter.getAdapterInfo();
        
        assertEq(_yieldManager, yieldManager);
        assertEq(_treasury, treasury);
        assertEq(_totalSwaps, 0);
        assertEq(_totalLiquidityOps, 0);
        assertEq(_totalRewards, 0);
    }
    
    function testCalculateMinOutput() public {
        uint256 amount = 1000e18;
        uint256 slippage = 50; // 0.5%
        
        uint256 minOutput = adapter.calculateMinOutput(amount, slippage);
        
        assertEq(minOutput, 995e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            9. INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFullCycle() public {
        vm.startPrank(yieldManager);
        
        // 1. Swap HONEY for APIARY
        uint256 swapAmount = 100e18;
        honey.approve(address(adapter), swapAmount);
        adapter.swap(address(honey), address(apiary), swapAmount, 95e18, yieldManager);
        
        // 2. Add liquidity
        uint256 liquidityA = 500e18;
        uint256 liquidityB = 500e18;
        apiary.approve(address(adapter), liquidityA);
        honey.approve(address(adapter), liquidityB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            liquidityA,
            liquidityB,
            400e18,
            yieldManager
        );
        
        // 3. Stake LP (with lock)
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        
        // 4. Set and claim rewards
        uint256[] memory rewardAmounts = new uint256[](2);
        rewardAmounts[0] = 50e18;
        rewardAmounts[1] = 0;
        farm.setEarnedRewards(address(adapter), rewardAmounts);
        adapter.claimLPRewardsTo(lpToken, treasury);
        vm.stopPrank();
        
        // 5. Warp past lock and unstake
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        vm.prank(yieldManager);
        adapter.unstakeLPTo(lpToken, kekId, treasury);
        
        // Verify final state
        assertEq(adapter.totalSwapsExecuted(), 1);
        assertEq(adapter.totalLiquidityOps(), 1);
        assertEq(adapter.totalRewardsClaimed(), 1);
        assertGt(xkdk.balanceOf(treasury), 0);
        assertGt(IERC20(lpToken).balanceOf(treasury), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        10. GAS & EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testManyStakesGasLimit() public {
        // Test with 20 stakes to check gas consumption
        uint256 numStakes = 20;
        uint256 amountA = 50000e18;
        uint256 amountB = 50000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Create many stakes
        uint256 stakeAmount = liquidity / numStakes;
        bytes32[] memory kekIds = new bytes32[](numStakes);
        
        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < numStakes; i++) {
            kekIds[i] = adapter.stakeLP(lpToken, stakeAmount);
        }
        uint256 gasUsedStaking = gasStart - gasleft();
        
        assertEq(adapter.getStakeIds(lpToken).length, numStakes);
        
        // Warp past lock expiration
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        // Measure gas for unstakeAllExpired
        gasStart = gasleft();
        uint256 unstaked = adapter.unstakeAllExpired(lpToken);
        uint256 gasUsedUnstaking = gasStart - gasleft();
        
        vm.stopPrank();
        
        assertGt(unstaked, 0);
        assertEq(adapter.getStakeIds(lpToken).length, 0);
        
        // Log gas usage for benchmarking
        // emit log_named_uint("Gas used for 20 stakes", gasUsedStaking);
        // emit log_named_uint("Gas used for unstakeAllExpired (20)", gasUsedUnstaking);
    }
    
    function testStakeWithMinimumLockDuration() public {
        // Set lock duration to farm minimum (7 days)
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 7 days);
        
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Verify stake with minimum lock
        IKodiakFarm.LockedStake memory stake = adapter.getStakeInfo(lpToken, kekId);
        assertEq(stake.ending_timestamp - stake.start_timestamp, 7 days);
        assertEq(stake.lock_multiplier, 1e18); // 1x multiplier for minimum lock
    }
    
    function testStakeWithMaxLockDuration() public {
        // Set lock duration to farm maximum (365 days)
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 365 days);
        
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Verify stake with maximum lock
        IKodiakFarm.LockedStake memory stake = adapter.getStakeInfo(lpToken, kekId);
        assertEq(stake.ending_timestamp - stake.start_timestamp, 365 days);
        assertEq(stake.lock_multiplier, 3e18); // 3x multiplier for max lock
    }
    
    function testStakeWithZeroLockWhenFarmAllows() public {
        // When farm allows 0 lock time, adapter should allow it too
        farm.setMinLockTime(0);
        
        // Setting 0 lock duration should work when farm allows it
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 0);
        
        // But staking should still fail because lockDuration == 0 check in stakeLP
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // Staking with 0 lock duration reverts due to safety check in stakeLP
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__LOCK_DURATION_NOT_SET.selector);
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
    }
    
    function testStakeWithFarmMinimumZeroButAdapterRequiresNonZero() public {
        // Set farm min lock to 0, but adapter still needs a valid duration
        farm.setMinLockTime(0);
        
        // Setting a valid (non-zero) duration should work
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 1 days);
        
        assertEq(adapter.getLockDuration(lpToken), 1 days);
    }
    
    function testGetCombinedWeight() public {
        // Setup and stake
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        uint256 weight = adapter.getCombinedWeight(lpToken);
        
        // Weight should be liquidity * multiplier / 1e18
        // For 7 day lock, multiplier is 1e18 (1x)
        assertEq(weight, liquidity);
    }
    
    function testUnstakeLPRevertsNonYieldManager() public {
        // Setup a stake first
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        bytes32 kekId = adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Warp past lock
        vm.warp(block.timestamp + TEST_LOCK_DURATION + 1);
        
        // Try to unstake as non-yield-manager
        vm.prank(user);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__ONLY_YIELD_MANAGER.selector);
        adapter.unstakeLP(lpToken, kekId);
    }
    
    function testClaimLPRewardsRevertsNonYieldManager() public {
        vm.prank(user);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__ONLY_YIELD_MANAGER.selector);
        adapter.claimLPRewards(lpToken);
    }
    
    function testPartialExpiredStakes() public {
        // Create stakes with different expiration times
        uint256 amountA = 2000e18;
        uint256 amountB = 2000e18;
        
        vm.startPrank(yieldManager);
        apiary.approve(address(adapter), amountA);
        honey.approve(address(adapter), amountB);
        
        (, , uint256 liquidity) = adapter.addLiquidity(
            address(apiary),
            address(honey),
            amountA,
            amountB,
            100e18,
            yieldManager
        );
        
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        // First stake with 7 day lock
        bytes32 kekId1 = adapter.stakeLP(lpToken, liquidity / 2);
        vm.stopPrank();
        
        // Change lock duration for second stake
        vm.prank(owner);
        adapter.setLockDuration(lpToken, 30 days);
        
        vm.prank(yieldManager);
        bytes32 kekId2 = adapter.stakeLP(lpToken, liquidity / 2);
        
        // Warp 10 days - first stake should be expired, second still locked
        vm.warp(block.timestamp + 10 days);
        
        // Check expired stakes
        (bytes32[] memory expired, uint256 expiredLiquidity) = adapter.getExpiredStakes(lpToken);
        assertEq(expired.length, 1);
        assertEq(expired[0], kekId1);
        assertEq(expiredLiquidity, liquidity / 2);
        
        // Unstake expired
        vm.prank(yieldManager);
        uint256 unstaked = adapter.unstakeAllExpired(lpToken);
        
        assertEq(unstaked, liquidity / 2);
        assertEq(adapter.getStakeIds(lpToken).length, 1); // Only second stake remains
        assertTrue(adapter.isOurStake(kekId2));
        assertFalse(adapter.isOurStake(kekId1));
    }
}
