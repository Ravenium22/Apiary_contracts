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
import { IKodiakGauge } from "../src/interfaces/IKodiakGauge.sol";
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

contract MockKodiakGauge is IKodiakGauge {
    address public stakingTokenAddress;
    address[] public rewardTokensArray;
    
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public earnedRewards;
    uint256 public totalStaked;
    
    constructor(address _stakingToken, address[] memory _rewardTokens) {
        stakingTokenAddress = _stakingToken;
        rewardTokensArray = _rewardTokens;
    }
    
    function stake(uint256 amount) external {
        IERC20(stakingTokenAddress).transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }
    
    function stakeFor(uint256 amount, address recipient) external {
        IERC20(stakingTokenAddress).transferFrom(msg.sender, address(this), amount);
        balances[recipient] += amount;
        totalStaked += amount;
        emit Staked(recipient, amount);
    }
    
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        totalStaked -= amount;
        IERC20(stakingTokenAddress).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }
    
    function getReward() external {
        for (uint256 i = 0; i < rewardTokensArray.length; i++) {
            uint256 reward = earnedRewards[msg.sender][rewardTokensArray[i]];
            if (reward > 0) {
                earnedRewards[msg.sender][rewardTokensArray[i]] = 0;
                IERC20(rewardTokensArray[i]).transfer(msg.sender, reward);
                emit RewardPaid(msg.sender, rewardTokensArray[i], reward);
            }
        }
    }
    
    function getReward(address account) external {
        for (uint256 i = 0; i < rewardTokensArray.length; i++) {
            uint256 reward = earnedRewards[account][rewardTokensArray[i]];
            if (reward > 0) {
                earnedRewards[account][rewardTokensArray[i]] = 0;
                IERC20(rewardTokensArray[i]).transfer(account, reward);
                emit RewardPaid(account, rewardTokensArray[i], reward);
            }
        }
    }
    
    function exit() external {
        this.getReward();
        this.withdraw(balances[msg.sender]);
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
    
    function totalSupply() external view returns (uint256) {
        return totalStaked;
    }
    
    function earned(address account, address rewardToken) external view returns (uint256) {
        return earnedRewards[account][rewardToken];
    }
    
    function stakingToken() external view returns (address) {
        return stakingTokenAddress;
    }
    
    function rewardTokens(uint256 index) external view returns (address) {
        return rewardTokensArray[index];
    }
    
    function rewardTokensLength() external view returns (uint256) {
        return rewardTokensArray.length;
    }
    
    function rewardRate(address) external pure returns (uint256) {
        return 1e18;
    }
    
    function rewardsDuration() external pure returns (uint256) {
        return 7 days;
    }
    
    function lastUpdateTime() external view returns (uint256) {
        return block.timestamp;
    }
    
    function periodFinish() external view returns (uint256) {
        return block.timestamp + 7 days;
    }
    
    // Test helper
    function setEarnedRewards(address account, address rewardToken, uint256 amount) external {
        earnedRewards[account][rewardToken] = amount;
    }
}

/*//////////////////////////////////////////////////////////////
                            MAIN TEST CONTRACT
//////////////////////////////////////////////////////////////*/

contract ApiaryKodiakAdapterTest is Test {
    ApiaryKodiakAdapter public adapter;
    MockKodiakRouter public router;
    MockKodiakFactory public factory;
    MockKodiakGauge public gauge;
    MockERC20 public honey;
    MockERC20 public apiary;
    MockERC20 public xkdk;
    MockERC20 public bgt;
    
    address public owner = address(1);
    address public yieldManager = address(2);
    address public treasury = address(3);
    address public user = address(4);
    
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
        address pairAddress = factory.getPair(address(apiary), address(honey));
        
        // Setup gauge with rewards
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(xkdk);
        rewardTokens[1] = address(bgt);
        gauge = new MockKodiakGauge(pairAddress, rewardTokens);
        
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
        xkdk.mint(address(gauge), 10000e18);
        bgt.mint(address(gauge), 10000e18);
        
        // Setup pair reserves
        MockKodiakPair(pairAddress).setReserves(50000e18, 50000e18);
        
        // Register gauge
        vm.prank(owner);
        adapter.registerGauge(pairAddress, address(gauge));
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
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        assertEq(adapter.totalStakedLP(lpToken), liquidity);
        assertEq(gauge.balanceOf(address(adapter)), liquidity);
    }
    
    function testStakeLPRevertsGaugeNotRegistered() public {
        MockERC20 fakeLpToken = new MockERC20("FAKE-LP", "FAKE-LP", 18);
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__GAUGE_NOT_REGISTERED.selector);
        adapter.stakeLP(address(fakeLpToken), 100e18);
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
        
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // Unstake
        adapter.unstakeLPTo(lpToken, liquidity, treasury);
        vm.stopPrank();
        
        assertEq(adapter.totalStakedLP(lpToken), 0);
        assertEq(IERC20(lpToken).balanceOf(treasury), liquidity);
    }
    
    function testUnstakeLPRevertsInsufficientStaked() public {
        address lpToken = factory.getPair(address(apiary), address(honey));
        
        vm.prank(yieldManager);
        vm.expectRevert(ApiaryKodiakAdapter.APIARY__INSUFFICIENT_LP_STAKED.selector);
        adapter.unstakeLPTo(lpToken, 1000e18, treasury);
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
        
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // Set rewards
        gauge.setEarnedRewards(address(adapter), address(xkdk), 100e18);
        gauge.setEarnedRewards(address(adapter), address(bgt), 50e18);
        
        // Claim rewards
        (address[] memory rewardTokens, uint256[] memory rewardAmounts) = adapter.claimLPRewardsTo(lpToken, treasury);
        vm.stopPrank();
        
        assertEq(rewardTokens.length, 2);
        assertEq(rewardAmounts[0], 100e18); // xKDK
        assertEq(rewardAmounts[1], 50e18); // BGT
        assertEq(xkdk.balanceOf(treasury), 100e18);
        assertEq(bgt.balanceOf(treasury), 50e18);
        assertEq(adapter.totalRewardsClaimed(), 1);
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
    
    function testRegisterGauge() public {
        MockERC20 newLpToken = new MockERC20("NEW-LP", "NEW-LP", 18);
        address[] memory rewards = new address[](1);
        rewards[0] = address(xkdk);
        MockKodiakGauge newGauge = new MockKodiakGauge(address(newLpToken), rewards);
        
        vm.prank(owner);
        adapter.registerGauge(address(newLpToken), address(newGauge));
        
        assertEq(adapter.lpToGauge(address(newLpToken)), address(newGauge));
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
        
        address lpToken = factory.getPair(address(apiary), address(honey));
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
        
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        vm.stopPrank();
        
        // Set rewards
        gauge.setEarnedRewards(address(adapter), address(xkdk), 100e18);
        gauge.setEarnedRewards(address(adapter), address(bgt), 50e18);
        
        (address[] memory rewardTokens, uint256[] memory rewardAmounts) = adapter.getPendingRewards(lpToken);
        
        assertEq(rewardTokens.length, 2);
        assertEq(rewardAmounts[0], 100e18);
        assertEq(rewardAmounts[1], 50e18);
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
        
        // 3. Stake LP
        address lpToken = factory.getPair(address(apiary), address(honey));
        IERC20(lpToken).approve(address(adapter), liquidity);
        adapter.stakeLP(lpToken, liquidity);
        
        // 4. Set and claim rewards
        gauge.setEarnedRewards(address(adapter), address(xkdk), 50e18);
        adapter.claimLPRewardsTo(lpToken, treasury);
        
        // 5. Unstake LP
        adapter.unstakeLPTo(lpToken, liquidity / 2, treasury);
        
        vm.stopPrank();
        
        // Verify final state
        assertEq(adapter.totalSwapsExecuted(), 1);
        assertEq(adapter.totalLiquidityOps(), 1);
        assertEq(adapter.totalRewardsClaimed(), 1);
        assertGt(xkdk.balanceOf(treasury), 0);
    }
}
