// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestSetup
 * @notice Base test setup with mock contracts and utilities
 * @dev Updated to match refactored adapter contracts with pull pattern
 */
contract TestSetup is Test {
    /*//////////////////////////////////////////////////////////////
                            MOCK TOKENS
    //////////////////////////////////////////////////////////////*/

    MockERC20 public apiaryToken;
    MockERC20 public honeyToken;
    MockERC20 public ibgtToken;
    MockERC20 public bgtToken;
    MocksAPIARY public sApiaryToken;
    MockUniswapV2Pair public apiaryHoneyPair;
    MockUniswapV2Router public kodiakRouter;
    MockKodiakFactory public kodiakFactory;
    MockInfrared public infraredProtocol;
    MockKodiakGauge public kodiakGauge;

    /*//////////////////////////////////////////////////////////////
                            TEST ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public yieldManagerAddr = makeAddr("yieldManager");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public keeper = makeAddr("keeper");
    address public attacker = makeAddr("attacker");

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant INITIAL_APIARY_SUPPLY = 200_000e18;
    uint256 public constant INITIAL_HONEY_LIQUIDITY = 100_000e18;
    uint256 public constant INITIAL_IBGT_STAKE = 50_000e18;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant VESTING_PERIOD = 5 days;

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.label(owner, "Owner");
        vm.label(treasury, "Treasury");
        vm.label(yieldManagerAddr, "YieldManager");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(keeper, "Keeper");
        vm.label(attacker, "Attacker");

        // Deploy mock tokens
        apiaryToken = new MockERC20("Apiary", "APIARY", 18);
        honeyToken = new MockERC20("Honey", "HONEY", 18);
        ibgtToken = new MockERC20("Infrared BGT", "iBGT", 18);
        bgtToken = new MockERC20("Berachain Governance Token", "BGT", 18);
        sApiaryToken = new MocksAPIARY();

        // Deploy mock infrastructure
        kodiakFactory = new MockKodiakFactory();
        apiaryHoneyPair = new MockUniswapV2Pair(address(apiaryToken), address(honeyToken));
        kodiakFactory.setPair(address(apiaryToken), address(honeyToken), address(apiaryHoneyPair));
        kodiakRouter = new MockUniswapV2Router(address(apiaryHoneyPair), address(kodiakFactory));
        infraredProtocol = new MockInfrared(address(ibgtToken), address(bgtToken));
        kodiakGauge = new MockKodiakGauge(address(apiaryHoneyPair));

        // Setup initial balances
        _setupInitialBalances();
    }

    function _setupInitialBalances() internal {
        // Mint tokens to test accounts
        apiaryToken.mint(owner, INITIAL_APIARY_SUPPLY);
        honeyToken.mint(owner, INITIAL_HONEY_LIQUIDITY);
        honeyToken.mint(user1, 10_000e18);
        honeyToken.mint(user2, 10_000e18);
        honeyToken.mint(user3, 10_000e18);

        ibgtToken.mint(treasury, INITIAL_IBGT_STAKE);
        ibgtToken.mint(user1, 1000e18);
        ibgtToken.mint(user2, 1000e18);

        bgtToken.mint(address(infraredProtocol), 100_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _increaseTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function _increaseBlocks(uint256 blocks_) internal {
        vm.roll(block.number + blocks_);
    }

    function _setupLiquidity(uint256 apiaryAmount, uint256 honeyAmount) internal {
        vm.startPrank(owner);
        apiaryToken.approve(address(kodiakRouter), apiaryAmount);
        honeyToken.approve(address(kodiakRouter), honeyAmount);
        kodiakRouter.addLiquidity(
            address(apiaryToken), address(honeyToken), apiaryAmount, honeyAmount, 0, 0, owner, block.timestamp
        );
        vm.stopPrank();
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MocksAPIARY {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
    uint256 public index = 1e18; // Rebase index

    function balanceForGons(uint256 gons) public view returns (uint256) {
        return (gons * index) / 1e18;
    }

    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return (amount * 1e18) / index;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function rebase(uint256 profit) external {
        if (totalSupply == 0) return;
        index = index + ((profit * 1e18) / totalSupply);
    }

    function circulatingSupply() external view returns (uint256) {
        return totalSupply;
    }
}

contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function mint(address to) external returns (uint256 liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1);
        } else {
            liquidity = _min((amount0 * totalSupply) / reserve0, (amount1 * totalSupply) / reserve1);
        }

        balanceOf[to] += liquidity;
        totalSupply += liquidity;

        reserve0 = balance0;
        reserve1 = balance1;

        return liquidity;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (uint112(reserve0), uint112(reserve1), uint32(block.timestamp));
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MockUniswapV2Router {
    address public pair;
    address public factory;
    bool public shouldFail;
    uint256 public slippagePercent; // in BPS (100 = 1%)

    constructor(address _pair, address _factory) {
        pair = _pair;
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(!shouldFail, "Mock: addLiquidity failed");
        IERC20(tokenA).transferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountBDesired);

        liquidity = MockUniswapV2Pair(pair).mint(to);

        return (amountADesired, amountBDesired, liquidity);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        require(!shouldFail, "Mock: swap failed");
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        // Apply slippage (default 1% if not set)
        uint256 slippage = slippagePercent > 0 ? slippagePercent : 100;
        amounts[1] = (amountIn * (10000 - slippage)) / 10000;

        require(amounts[1] >= amountOutMin, "Slippage too high");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(path[1]).mint(to, amounts[1]);

        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata)
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        uint256 slippage = slippagePercent > 0 ? slippagePercent : 100;
        amounts[1] = (amountIn * (10000 - slippage)) / 10000;
        return amounts;
    }

    // Test helpers
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setSlippage(uint256 _slippage) external {
        slippagePercent = _slippage;
    }
}

contract MockInfrared {
    address public ibgt;
    address public bgt;
    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public pendingRewards;
    bool public shouldFail;

    constructor(address _ibgt, address _bgt) {
        ibgt = _ibgt;
        bgt = _bgt;
    }

    function stake(uint256 amount) external returns (uint256) {
        require(!shouldFail, "Mock: stake failed");
        IERC20(ibgt).transferFrom(msg.sender, address(this), amount);
        stakedAmount[msg.sender] += amount;
        return amount; // Return staked amount
    }

    function unstake(uint256 amount) external returns (uint256) {
        require(!shouldFail, "Mock: unstake failed");
        require(stakedAmount[msg.sender] >= amount, "Insufficient stake");
        stakedAmount[msg.sender] -= amount;
        IERC20(ibgt).transfer(msg.sender, amount);
        return amount; // Return unstaked amount
    }

    function claimRewards() external returns (uint256) {
        require(!shouldFail, "Mock: claimRewards failed");
        uint256 rewards = pendingRewards[msg.sender];
        pendingRewards[msg.sender] = 0;
        if (rewards > 0) {
            IERC20(ibgt).transfer(msg.sender, rewards);
        }
        return rewards;
    }

    function addRewards(address user, uint256 amount) external {
        pendingRewards[user] += amount;
        // Mint iBGT to this contract to cover the rewards
        MockERC20(ibgt).mint(address(this), amount);
    }

    function getPendingRewards(address user) external view returns (uint256) {
        return pendingRewards[user];
    }

    function balanceOf(address user) external view returns (uint256) {
        return stakedAmount[user];
    }

    function rewardToken() external view returns (address) {
        return ibgt;
    }

    // Test helpers
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
}

contract MockKodiakFactory {
    mapping(address => mapping(address => address)) public pairs;

    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}

contract MockKodiakGauge {
    address public lpToken;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public rewards;

    constructor(address _lpToken) {
        lpToken = _lpToken;
    }

    function deposit(uint256 amount) external {
        IERC20(lpToken).transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        IERC20(lpToken).transfer(msg.sender, amount);
    }

    function getReward() external returns (uint256) {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        return reward;
    }

    function addReward(address user, uint256 amount) external {
        rewards[user] += amount;
    }
}
