// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryTreasury } from "../src/ApiaryTreasury.sol";
import { IApiaryTreasury } from "../src/interfaces/IApiaryTreasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApiaryTreasuryTest
 * @notice Comprehensive test suite for treasury contract
 * @dev Tests deposits, reserves, iBGT accounting, and access control
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Deposit Functions
 * 3. Reserve Management
 * 4. Yield Manager Functions
 * 5. iBGT Accounting
 * 6. Admin Functions
 * 7. Access Control
 * 8. View Functions
 */

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 is IERC20 {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 internal _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        _balances[from] -= amount;
        _totalSupply -= amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        return true;
    }
}

contract MockAPIARY is MockERC20 {
    mapping(address => uint256) public allocationLimits;

    constructor() MockERC20("Apiary", "APIARY", 9) {}

    function setAllocationLimit(address minter, uint256 amount) external {
        allocationLimits[minter] = amount;
    }

    function mint(address to, uint256 amount) external override {
        // For treasury testing, just mint without strict allocation checking
        _mint(to, amount);
    }
}

contract ApiaryTreasuryTest is Test {
    ApiaryTreasury public treasury;
    MockAPIARY public apiary;
    MockERC20 public ibgt;
    MockERC20 public honey;
    MockERC20 public lpToken;

    // Test accounts
    address public admin = makeAddr("admin");
    address public reserveDepositor = makeAddr("reserveDepositor");
    address public liquidityDepositor = makeAddr("liquidityDepositor");
    address public reservesManager = makeAddr("reservesManager");
    address public yieldManager = makeAddr("yieldManager");
    address public attacker = makeAddr("attacker");

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount);
    event ReservesRepaid(address indexed token, uint256 amount);
    event IBGTPulledForStaking(uint256 amount, address indexed yieldManager);
    event IBGTReturnedFromStaking(uint256 amount, uint256 rewards);
    event ReservesManagerSet(address indexed manager);
    event YieldManagerSet(address indexed yieldManager);
    event ReserveDepositorSet(address indexed depositor, bool status);
    event LiquidityDepositorSet(address indexed depositor, bool status);
    event ReserveTokenSet(address indexed token, bool status);
    event LiquidityTokenSet(address indexed token, bool status);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mock tokens
        apiary = new MockAPIARY();
        ibgt = new MockERC20("Infrared BGT", "iBGT", 18);
        honey = new MockERC20("Honey", "HONEY", 18);
        lpToken = new MockERC20("Kodiak LP", "KDK-LP", 18);

        // Deploy treasury
        vm.prank(admin);
        treasury = new ApiaryTreasury(
            admin,
            address(apiary),
            address(ibgt),
            address(honey),
            address(lpToken)
        );

        // Setup: Give treasury mint allocation
        apiary.setAllocationLimit(address(treasury), 1_000_000e9);

        // Setup: Set depositors
        vm.startPrank(admin);
        treasury.setReserveDepositor(reserveDepositor, true);
        treasury.setLiquidityDepositor(liquidityDepositor, true);
        treasury.setReservesManager(reservesManager);
        treasury.setYieldManager(yieldManager);
        vm.stopPrank();

        // Give depositors tokens
        ibgt.mint(reserveDepositor, 100_000e18);
        lpToken.mint(liquidityDepositor, 100_000e18);
        ibgt.mint(yieldManager, 100_000e18);

        // Approve treasury
        vm.prank(reserveDepositor);
        ibgt.approve(address(treasury), type(uint256).max);

        vm.prank(liquidityDepositor);
        lpToken.approve(address(treasury), type(uint256).max);

        vm.prank(yieldManager);
        ibgt.approve(address(treasury), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_Owner() public view {
        assertEq(treasury.owner(), admin);
    }

    function test_Deployment_APIARYToken() public view {
        assertEq(address(treasury.APIARY_TOKEN()), address(apiary));
    }

    function test_Deployment_IBGT() public view {
        assertEq(treasury.IBGT(), address(ibgt));
    }

    function test_Deployment_HONEY() public view {
        assertEq(treasury.HONEY(), address(honey));
    }

    function test_Deployment_LPToken() public view {
        assertEq(treasury.APIARY_HONEY_LP(), address(lpToken));
    }

    function test_Deployment_IBGTIsReserveToken() public view {
        assertTrue(treasury.isReserveToken(address(ibgt)));
    }

    function test_Deployment_LPIsLiquidityToken() public view {
        assertTrue(treasury.isLiquidityToken(address(lpToken)));
    }

    function testRevert_Deployment_ZeroAPIARY() public {
        vm.expectRevert(ApiaryTreasury.APIARY__ZERO_ADDRESS.selector);
        new ApiaryTreasury(
            admin,
            address(0),
            address(ibgt),
            address(honey),
            address(lpToken)
        );
    }

    function testRevert_Deployment_ZeroIBGT() public {
        vm.expectRevert(ApiaryTreasury.APIARY__ZERO_ADDRESS.selector);
        new ApiaryTreasury(
            admin,
            address(apiary),
            address(0),
            address(honey),
            address(lpToken)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_ReserveToken() public {
        uint256 depositAmount = 1000e18;
        uint256 apiaryValue = 10_000e9;

        vm.expectEmit(true, true, true, false);
        emit Deposit(address(ibgt), depositAmount, apiaryValue);

        vm.prank(reserveDepositor);
        uint256 minted = treasury.deposit(depositAmount, address(ibgt), apiaryValue);

        assertEq(minted, apiaryValue);
        assertEq(ibgt.balanceOf(address(treasury)), depositAmount);
        assertEq(treasury.totalReserves(address(ibgt)), depositAmount);
    }

    function test_Deposit_LiquidityToken() public {
        uint256 depositAmount = 1000e18;
        uint256 apiaryValue = 10_000e9;

        vm.prank(liquidityDepositor);
        uint256 minted = treasury.deposit(depositAmount, address(lpToken), apiaryValue);

        assertEq(minted, apiaryValue);
        assertEq(lpToken.balanceOf(address(treasury)), depositAmount);
        assertEq(treasury.totalReserves(address(lpToken)), depositAmount);
    }

    function test_Deposit_UpdatesIBGTAccounting() public {
        uint256 depositAmount = 1000e18;
        uint256 apiaryValue = 10_000e9;

        vm.prank(reserveDepositor);
        treasury.deposit(depositAmount, address(ibgt), apiaryValue);

        IApiaryTreasury.IBGTAccounting memory accounting = treasury.getIBGTAccounting();

        assertEq(accounting.totalDeposited, depositAmount);
        assertEq(accounting.availableBalance, depositAmount);
    }

    function test_Deposit_MintsAPIARY() public {
        uint256 depositAmount = 1000e18;
        uint256 apiaryValue = 10_000e9;

        vm.prank(reserveDepositor);
        treasury.deposit(depositAmount, address(ibgt), apiaryValue);

        assertEq(apiary.balanceOf(reserveDepositor), apiaryValue);
    }

    function testRevert_Deposit_InvalidToken() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(reserveDepositor, 1000e18);

        vm.startPrank(reserveDepositor);
        randomToken.approve(address(treasury), 1000e18);

        vm.expectRevert(ApiaryTreasury.APIARY__INVALID_TOKEN.selector);
        treasury.deposit(1000e18, address(randomToken), 10_000e9);
        vm.stopPrank();
    }

    function testRevert_Deposit_InvalidReserveDepositor() public {
        vm.prank(attacker);

        vm.expectRevert(ApiaryTreasury.APIARY__INVALID_RESERVE_DEPOSITOR.selector);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);
    }

    function testRevert_Deposit_InvalidLiquidityDepositor() public {
        vm.prank(attacker);

        vm.expectRevert(ApiaryTreasury.APIARY__INVALID_LIQUIDITY_DEPOSITOR.selector);
        treasury.deposit(1000e18, address(lpToken), 10_000e9);
    }

    /*//////////////////////////////////////////////////////////////
                    RESERVE MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BorrowReserves() public {
        // First deposit
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        uint256 borrowAmount = 500e18;

        vm.expectEmit(true, true, false, false);
        emit Withdrawal(address(ibgt), borrowAmount);

        vm.prank(reservesManager);
        treasury.borrowReserves(borrowAmount, address(ibgt));

        assertEq(ibgt.balanceOf(reservesManager), borrowAmount);
        assertEq(treasury.totalReserves(address(ibgt)), 1000e18 - borrowAmount);
        assertEq(treasury.totalBorrowed(address(ibgt)), borrowAmount);
    }

    function test_RepayReserves() public {
        // First deposit
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        // Borrow
        vm.prank(reservesManager);
        treasury.borrowReserves(500e18, address(ibgt));

        // Repay
        vm.prank(reservesManager);
        ibgt.approve(address(treasury), 500e18);

        vm.expectEmit(true, true, false, false);
        emit ReservesRepaid(address(ibgt), 500e18);

        vm.prank(reservesManager);
        treasury.repayReserves(500e18, address(ibgt));

        assertEq(treasury.totalReserves(address(ibgt)), 1000e18);
        assertEq(treasury.totalBorrowed(address(ibgt)), 0);
    }

    function testRevert_BorrowReserves_NotManager() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        vm.prank(attacker);
        vm.expectRevert(ApiaryTreasury.APIARY__UNAUTHORIZED_RESERVE_MANAGER.selector);
        treasury.borrowReserves(500e18, address(ibgt));
    }

    /*//////////////////////////////////////////////////////////////
                    YIELD MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PullIBGTForStaking() public {
        // First deposit
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        uint256 pullAmount = 500e18;

        vm.expectEmit(true, true, false, false);
        emit IBGTPulledForStaking(pullAmount, yieldManager);

        vm.prank(yieldManager);
        treasury.pullIBGTForStaking(pullAmount);

        assertEq(ibgt.balanceOf(yieldManager), 100_000e18 + pullAmount);

        IApiaryTreasury.IBGTAccounting memory accounting = treasury.getIBGTAccounting();
        assertEq(accounting.availableBalance, 1000e18 - pullAmount);
        assertEq(accounting.totalStaked, pullAmount);
    }

    function test_ReturnIBGTFromStaking() public {
        // First deposit
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        // Pull for staking
        vm.prank(yieldManager);
        treasury.pullIBGTForStaking(500e18);

        // Return with rewards
        uint256 principal = 500e18;
        uint256 rewards = 50e18;
        uint256 totalReturn = principal + rewards;

        vm.expectEmit(true, true, false, false);
        emit IBGTReturnedFromStaking(totalReturn, rewards);

        vm.prank(yieldManager);
        treasury.returnIBGTFromStaking(totalReturn, principal);

        IApiaryTreasury.IBGTAccounting memory accounting = treasury.getIBGTAccounting();
        assertEq(accounting.totalStaked, 0);
        assertEq(accounting.availableBalance, 1000e18 + rewards);
        assertEq(accounting.totalReturned, totalReturn);
    }

    function testRevert_PullIBGTForStaking_InsufficientBalance() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        vm.prank(yieldManager);
        vm.expectRevert(ApiaryTreasury.APIARY__INSUFFICIENT_IBGT_AVAILABLE.selector);
        treasury.pullIBGTForStaking(2000e18);
    }

    function testRevert_ReturnIBGTFromStaking_InsufficientStaked() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        vm.prank(yieldManager);
        treasury.pullIBGTForStaking(500e18);

        vm.prank(yieldManager);
        vm.expectRevert(ApiaryTreasury.APIARY__INSUFFICIENT_IBGT_STAKED.selector);
        treasury.returnIBGTFromStaking(1000e18, 600e18); // principal > staked
    }

    function testRevert_ReturnIBGTFromStaking_InvalidPrincipal() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        vm.prank(yieldManager);
        treasury.pullIBGTForStaking(500e18);

        vm.prank(yieldManager);
        vm.expectRevert(ApiaryTreasury.APIARY__INVALID_PRINCIPAL_AMOUNT.selector);
        treasury.returnIBGTFromStaking(400e18, 500e18); // amount < principal
    }

    function testRevert_PullIBGTForStaking_NotYieldManager() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        vm.prank(attacker);
        vm.expectRevert(ApiaryTreasury.APIARY__UNAUTHORIZED_YIELD_MANAGER.selector);
        treasury.pullIBGTForStaking(500e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetReservesManager() public {
        address newManager = makeAddr("newManager");

        vm.expectEmit(true, false, false, false);
        emit ReservesManagerSet(newManager);

        vm.prank(admin);
        treasury.setReservesManager(newManager);

        assertEq(treasury.reservesManager(), newManager);
    }

    function test_SetYieldManager() public {
        address newYieldManager = makeAddr("newYieldManager");

        vm.expectEmit(true, false, false, false);
        emit YieldManagerSet(newYieldManager);

        vm.prank(admin);
        treasury.setYieldManager(newYieldManager);

        assertEq(treasury.yieldManager(), newYieldManager);
    }

    function test_SetReserveDepositor() public {
        address newDepositor = makeAddr("newDepositor");

        vm.expectEmit(true, true, false, false);
        emit ReserveDepositorSet(newDepositor, true);

        vm.prank(admin);
        treasury.setReserveDepositor(newDepositor, true);

        assertTrue(treasury.isReserveDepositor(newDepositor));
    }

    function test_SetLiquidityDepositor() public {
        address newDepositor = makeAddr("newDepositor");

        vm.expectEmit(true, true, false, false);
        emit LiquidityDepositorSet(newDepositor, true);

        vm.prank(admin);
        treasury.setLiquidityDepositor(newDepositor, true);

        assertTrue(treasury.isLiquidityDepositor(newDepositor));
    }

    function test_SetReserveToken() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);

        vm.expectEmit(true, true, false, false);
        emit ReserveTokenSet(address(newToken), true);

        vm.prank(admin);
        treasury.setReserveToken(address(newToken), true);

        assertTrue(treasury.isReserveToken(address(newToken)));
    }

    function test_SetLiquidityToken() public {
        MockERC20 newToken = new MockERC20("New LP", "NLP", 18);

        vm.expectEmit(true, true, false, false);
        emit LiquidityTokenSet(address(newToken), true);

        vm.prank(admin);
        treasury.setLiquidityToken(address(newToken), true);

        assertTrue(treasury.isLiquidityToken(address(newToken)));
    }

    function testRevert_SetReservesManager_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryTreasury.APIARY__ZERO_ADDRESS.selector);
        treasury.setReservesManager(address(0));
    }

    function testRevert_SetYieldManager_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryTreasury.APIARY__ZERO_ADDRESS.selector);
        treasury.setYieldManager(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_SetReservesManager_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setReservesManager(makeAddr("manager"));
    }

    function testRevert_SetYieldManager_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setYieldManager(makeAddr("manager"));
    }

    function testRevert_SetReserveDepositor_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setReserveDepositor(makeAddr("depositor"), true);
    }

    function testRevert_SetLiquidityDepositor_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setLiquidityDepositor(makeAddr("depositor"), true);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetIBGTBalance() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        assertEq(treasury.getIBGTBalance(), 1000e18);
    }

    function test_GetHONEYBalance() public view {
        assertEq(treasury.getHONEYBalance(), 0);
    }

    function test_GetLPBalance() public {
        vm.prank(liquidityDepositor);
        treasury.deposit(1000e18, address(lpToken), 10_000e9);

        assertEq(treasury.getLPBalance(), 1000e18);
    }

    function test_GetIBGTAccounting() public {
        vm.prank(reserveDepositor);
        treasury.deposit(1000e18, address(ibgt), 10_000e9);

        IApiaryTreasury.IBGTAccounting memory accounting = treasury.getIBGTAccounting();

        assertEq(accounting.totalDeposited, 1000e18);
        assertEq(accounting.totalStaked, 0);
        assertEq(accounting.totalReturned, 0);
        assertEq(accounting.availableBalance, 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit(uint256 amount, uint256 value) public {
        // Bound to reasonable amounts
        amount = bound(amount, 1e18, 100_000e18);
        value = bound(value, 1e9, 1_000_000e9);

        // Make sure depositor has enough
        ibgt.mint(reserveDepositor, amount);

        vm.prank(reserveDepositor);
        uint256 minted = treasury.deposit(amount, address(ibgt), value);

        assertEq(minted, value);
        assertEq(treasury.totalReserves(address(ibgt)), amount);
    }

    function testFuzz_PullAndReturnIBGT(uint256 depositAmount, uint256 pullAmount, uint256 rewards) public {
        depositAmount = bound(depositAmount, 1e18, 100_000e18);
        pullAmount = bound(pullAmount, 1e18, depositAmount);
        rewards = bound(rewards, 0, 10_000e18);

        // Deposit
        ibgt.mint(reserveDepositor, depositAmount);
        vm.prank(reserveDepositor);
        treasury.deposit(depositAmount, address(ibgt), 10_000e9);

        // Pull
        vm.prank(yieldManager);
        treasury.pullIBGTForStaking(pullAmount);

        // Return
        ibgt.mint(yieldManager, rewards); // Mint rewards
        vm.prank(yieldManager);
        treasury.returnIBGTFromStaking(pullAmount + rewards, pullAmount);

        IApiaryTreasury.IBGTAccounting memory accounting = treasury.getIBGTAccounting();
        assertEq(accounting.totalStaked, 0);
        assertEq(accounting.availableBalance, depositAmount + rewards);
    }
}
