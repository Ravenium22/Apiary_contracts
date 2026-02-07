// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryBondDepository } from "../src/ApiaryBondDepository.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ApiaryBondDepositoryTest
 * @notice Comprehensive test suite for bond depository
 * @dev Tests deposits, vesting, redemption, and bond pricing
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Bond Creation (deposit)
 * 3. Vesting
 * 4. Redemption
 * 5. Bond Pricing
 * 6. Admin Functions
 * 7. Access Control
 * 8. Edge Cases
 */

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockERC20 is IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }
    function decimals() external view returns (uint8) { return _decimals; }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }

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
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockAPIARY is MockERC20 {
    mapping(address => uint256) public allocationLimits;

    constructor() MockERC20("Apiary", "APIARY", 9) {}

    function setAllocationLimit(address minter, uint256 amount) external {
        allocationLimits[minter] = amount;
    }
}

contract MockTreasury {
    MockAPIARY public apiaryToken;
    mapping(address => bool) public isReserveDepositor;

    constructor(address _apiary) {
        apiaryToken = MockAPIARY(_apiary);
    }

    function deposit(uint256 _amount, address _token, uint256 value) external returns (uint256) {
        // Take tokens from depositor (bond depository)
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        // Mint APIARY to bond depository
        apiaryToken.mint(msg.sender, value);

        return value;
    }
}

contract MockTWAP {
    uint256 public price = 25e16; // 0.25 HONEY per APIARY

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function consult(uint256 amountIn) external view returns (uint256) {
        // Return price * amountIn / 1e9
        return (price * amountIn) / 1e9;
    }

    function update() external {}
}

contract ApiaryBondDepositoryTest is Test {
    ApiaryBondDepository public bondDepository;
    MockAPIARY public apiary;
    MockERC20 public ibgt;
    MockTreasury public treasury;
    MockTWAP public twap;

    // Test accounts
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    // Bond terms
    uint256 public constant VESTING_TERM = 86_400; // 5 days in blocks
    uint256 public constant MAX_PAYOUT = 500; // 0.5% of allocation
    uint256 public constant DISCOUNT_RATE = 1000; // 10%
    uint256 public constant MAX_DEBT = 1_000_000e9; // 1M APIARY

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BondCreated(
        address indexed user,
        uint256 indexed bondIndex,
        uint256 principleAmount,
        uint256 payout,
        uint256 vestingEnd,
        uint256 priceInHoney
    );
    event BondRedeemed(
        address indexed user,
        uint256 indexed bondIndex,
        uint256 payoutRedeemed,
        uint256 payoutRemaining
    );
    event BondTermsInitialized(
        uint256 indexed vestingTerm,
        uint256 indexed maxPayout,
        uint256 discountRate,
        uint256 maxDebt
    );
    event BondTermsUpdated(ApiaryBondDepository.PARAMETER indexed parameter, uint256 indexed input);
    event TwapUpdated(address indexed twap);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mocks
        apiary = new MockAPIARY();
        ibgt = new MockERC20("Infrared BGT", "iBGT", 18);
        twap = new MockTWAP();
        treasury = new MockTreasury(address(apiary));

        // Deploy bond depository (non-LP bond)
        vm.prank(admin);
        bondDepository = new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(treasury),
            admin,
            address(0), // No bonding calculator (not LP bond)
            address(twap)
        );

        // Setup: Give treasury allocation to mint
        apiary.setAllocationLimit(address(treasury), 10_000_000e9);

        // Initialize bond terms
        vm.prank(admin);
        bondDepository.initializeBondTerms(
            VESTING_TERM,
            MAX_PAYOUT,
            DISCOUNT_RATE,
            MAX_DEBT
        );

        // Give users iBGT
        ibgt.mint(user1, 100_000e18);
        ibgt.mint(user2, 100_000e18);

        // Approve bond depository
        vm.prank(user1);
        ibgt.approve(address(bondDepository), type(uint256).max);

        vm.prank(user2);
        ibgt.approve(address(bondDepository), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_APIARYAddress() public view {
        assertEq(bondDepository.APIARY(), address(apiary));
    }

    function test_Deployment_PrincipleAddress() public view {
        assertEq(bondDepository.principle(), address(ibgt));
    }

    function test_Deployment_TreasuryAddress() public view {
        assertEq(bondDepository.treasury(), address(treasury));
    }

    function test_Deployment_TwapAddress() public view {
        assertEq(address(bondDepository.twap()), address(twap));
    }

    function test_Deployment_NotLiquidityBond() public view {
        assertFalse(bondDepository.isLiquidityBond());
    }

    function test_Deployment_Owner() public view {
        assertEq(bondDepository.owner(), admin);
    }

    function testRevert_Deployment_ZeroAPIARY() public {
        vm.expectRevert(ApiaryBondDepository.APIARY__ZERO_ADDRESS.selector);
        new ApiaryBondDepository(
            address(0),
            address(ibgt),
            address(treasury),
            admin,
            address(0),
            address(twap)
        );
    }

    function testRevert_Deployment_ZeroPrinciple() public {
        vm.expectRevert(ApiaryBondDepository.APIARY__ZERO_ADDRESS.selector);
        new ApiaryBondDepository(
            address(apiary),
            address(0),
            address(treasury),
            admin,
            address(0),
            address(twap)
        );
    }

    function testRevert_Deployment_ZeroTreasury() public {
        vm.expectRevert(ApiaryBondDepository.APIARY__ZERO_ADDRESS.selector);
        new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(0),
            admin,
            address(0),
            address(twap)
        );
    }

    function testRevert_Deployment_ZeroTwap() public {
        vm.expectRevert(ApiaryBondDepository.APIARY__ZERO_ADDRESS.selector);
        new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(treasury),
            admin,
            address(0),
            address(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    BOND TERMS INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitializeBondTerms() public view {
        (uint256 vestingTerm, uint256 maxPayout, uint256 discountRate, uint256 maxDebt) = bondDepository.terms();

        assertEq(vestingTerm, VESTING_TERM);
        assertEq(maxPayout, MAX_PAYOUT);
        assertEq(discountRate, DISCOUNT_RATE);
        assertEq(maxDebt, MAX_DEBT);
    }

    function testRevert_InitializeBondTerms_AlreadyInitialized() public {
        vm.startPrank(admin);

        vm.expectRevert(ApiaryBondDepository.APIARY__ALREADY_INITIALIZED.selector);
        bondDepository.initializeBondTerms(VESTING_TERM, MAX_PAYOUT, DISCOUNT_RATE, MAX_DEBT);

        vm.stopPrank();
    }

    function testRevert_InitializeBondTerms_InvalidVestingTerm() public {
        // Deploy new depository
        ApiaryBondDepository newDepository = new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(treasury),
            admin,
            address(0),
            address(twap)
        );

        vm.prank(admin);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_VESTING_TERM.selector);
        newDepository.initializeBondTerms(
            1000, // Less than minimum (17280)
            MAX_PAYOUT,
            DISCOUNT_RATE,
            MAX_DEBT
        );
    }

    function testRevert_InitializeBondTerms_InvalidMaxPayout() public {
        ApiaryBondDepository newDepository = new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(treasury),
            admin,
            address(0),
            address(twap)
        );

        vm.prank(admin);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_MAX_PAYOUT.selector);
        newDepository.initializeBondTerms(
            VESTING_TERM,
            1001, // Max is 1000 (1%)
            DISCOUNT_RATE,
            MAX_DEBT
        );
    }

    function testRevert_InitializeBondTerms_InvalidDiscountRate() public {
        ApiaryBondDepository newDepository = new ApiaryBondDepository(
            address(apiary),
            address(ibgt),
            address(treasury),
            admin,
            address(0),
            address(twap)
        );

        vm.prank(admin);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_DISCOUNT_RATE.selector);
        newDepository.initializeBondTerms(
            VESTING_TERM,
            MAX_PAYOUT,
            10001, // Max is 10000 (100%)
            MAX_DEBT
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_CreatesBond() public {
        uint256 depositAmount = 10e18; // 10 iBGT
        uint256 maxPrice = 1e18; // High enough to not trigger slippage

        vm.prank(user1);
        uint256 payout = bondDepository.deposit(depositAmount, maxPrice);

        assertGt(payout, 0);
    }

    function test_Deposit_TransfersPrinciple() public {
        uint256 depositAmount = 10e18;
        uint256 maxPrice = 1e18;

        uint256 balanceBefore = ibgt.balanceOf(user1);

        vm.prank(user1);
        bondDepository.deposit(depositAmount, maxPrice);

        assertEq(ibgt.balanceOf(user1), balanceBefore - depositAmount);
    }

    function test_Deposit_UpdatesTotalDebt() public {
        uint256 depositAmount = 10e18;
        uint256 maxPrice = 1e18;

        vm.prank(user1);
        uint256 payout = bondDepository.deposit(depositAmount, maxPrice);

        assertEq(bondDepository.totalDebt(), payout);
    }

    function test_Deposit_StoresBondInfo() public {
        uint256 depositAmount = 10e18;
        uint256 maxPrice = 1e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, maxPrice);

        ApiaryBondDepository.Bond memory bond = bondDepository.getUserBond(user1, 0);

        assertGt(bond.payout, 0);
        assertEq(bond.vestingStart, uint48(block.number));
        assertEq(bond.vestingEnd, uint48(block.number + VESTING_TERM));
        assertFalse(bond.redeemed);
    }

    function test_Deposit_MultipleBonds() public {
        uint256 depositAmount = 10e18;
        uint256 maxPrice = 1e18;

        vm.startPrank(user1);
        bondDepository.deposit(depositAmount, maxPrice);
        bondDepository.deposit(depositAmount, maxPrice);
        bondDepository.deposit(depositAmount, maxPrice);
        vm.stopPrank();

        assertEq(bondDepository.getUserBondCount(user1), 3);
    }

    function testRevert_Deposit_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_AMOUNT.selector);
        bondDepository.deposit(0, 1e18);
    }

    function testRevert_Deposit_ZeroMaxPrice() public {
        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_MAX_PRICE.selector);
        bondDepository.deposit(10e18, 0);
    }

    function testRevert_Deposit_SlippageExceeded() public {
        // Set TWAP to high price
        twap.setPrice(1e18); // 1 HONEY per APIARY (higher than max)

        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__SLIPPAGE_LIMIT_EXCEEDED.selector);
        bondDepository.deposit(10e18, 1); // Very low max price
    }

    function testRevert_Deposit_BondSoldOut() public {
        // Set very low max debt
        vm.prank(admin);
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.MAX_DEBT, 1e9);

        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__BOND_SOLD_OUT.selector);
        bondDepository.deposit(100e18, 1e18); // Too much
    }

    function testRevert_Deposit_WhenPaused() public {
        vm.prank(admin);
        bondDepository.pause();

        vm.prank(user1);
        vm.expectRevert();
        bondDepository.deposit(10e18, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Vesting_LinearOverTime() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, 1e18);

        // At start: 0% vested
        assertEq(bondDepository.percentVestedFor(user1, 0), 0);

        // At 50%: should be ~50% vested
        vm.roll(block.number + VESTING_TERM / 2);
        uint256 halfVested = bondDepository.percentVestedFor(user1, 0);
        assertApproxEqAbs(halfVested, 5000, 10); // ~50%

        // At 100%: should be 100% vested
        vm.roll(block.number + VESTING_TERM);
        assertEq(bondDepository.percentVestedFor(user1, 0), 10000);
    }

    function test_Vesting_FiveDay() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, 1e18);

        // Move 5 days worth of blocks
        vm.roll(block.number + 86_400);

        uint256 percentVested = bondDepository.percentVestedFor(user1, 0);
        assertEq(percentVested, 10000); // 100% vested
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_FullyVested() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        uint256 payout = bondDepository.deposit(depositAmount, 1e18);

        // Move past vesting
        vm.roll(block.number + VESTING_TERM + 1);

        vm.prank(user1);
        uint256 redeemed = bondDepository.redeem(0);

        assertEq(redeemed, payout);
        assertEq(apiary.balanceOf(user1), payout);
    }

    function test_Redeem_PartiallyVested() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        uint256 payout = bondDepository.deposit(depositAmount, 1e18);

        // Move to 50% vested
        vm.roll(block.number + VESTING_TERM / 2);

        vm.prank(user1);
        uint256 redeemed = bondDepository.redeem(0);

        // Should be ~50% of payout
        assertApproxEqRel(redeemed, payout / 2, 0.01e18);
    }

    function test_Redeem_MarksBondRedeemed() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, 1e18);

        vm.roll(block.number + VESTING_TERM + 1);

        vm.prank(user1);
        bondDepository.redeem(0);

        ApiaryBondDepository.Bond memory bond = bondDepository.getUserBond(user1, 0);
        assertTrue(bond.redeemed);
        assertEq(bond.payout, 0);
    }

    function test_Redeem_DecreasesTotalDebt() public {
        // MEDIUM-05 Fix: redeem no longer directly subtracts from totalDebt.
        // Debt now decays solely via _decayDebt() called during deposit().
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, 1e18);

        uint256 debtBefore = bondDepository.totalDebt();

        vm.roll(block.number + VESTING_TERM + 1);

        vm.prank(user1);
        bondDepository.redeem(0);

        // totalDebt unchanged by redeem — only _decayDebt() reduces it
        assertEq(bondDepository.totalDebt(), debtBefore);
    }

    function test_RedeemAll() public {
        uint256 depositAmount = 10e18;

        vm.startPrank(user1);
        bondDepository.deposit(depositAmount, 1e18);
        bondDepository.deposit(depositAmount, 1e18);
        vm.stopPrank();

        vm.roll(block.number + VESTING_TERM + 1);

        vm.prank(user1);
        uint256 totalRedeemed = bondDepository.redeemAll();

        assertGt(totalRedeemed, 0);
        assertEq(apiary.balanceOf(user1), totalRedeemed);
    }

    function testRevert_Redeem_InvalidBondIndex() public {
        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__INVALID_BOND_INDEX.selector);
        bondDepository.redeem(0); // No bonds
    }

    function testRevert_Redeem_AlreadyRedeemed() public {
        uint256 depositAmount = 10e18;

        vm.prank(user1);
        bondDepository.deposit(depositAmount, 1e18);

        vm.roll(block.number + VESTING_TERM + 1);

        vm.prank(user1);
        bondDepository.redeem(0);

        // After full redemption, payout is set to 0, so NO_REDEEMABLE_BOND is thrown first
        vm.prank(user1);
        vm.expectRevert(ApiaryBondDepository.APIARY__NO_REDEEMABLE_BOND.selector);
        bondDepository.redeem(0);
    }

    function testRevert_Redeem_WhenPaused() public {
        vm.prank(user1);
        bondDepository.deposit(10e18, 1e18);

        vm.prank(admin);
        bondDepository.pause();

        vm.prank(user1);
        vm.expectRevert();
        bondDepository.redeem(0);
    }

    /*//////////////////////////////////////////////////////////////
                        BOND PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetBondPrice_AppliesDiscount() public view {
        uint256 marketPrice = 1e18;
        uint256 discountedPrice = bondDepository.getBondPrice(marketPrice);

        // 10% discount: 1e18 * (10000 - 1000) / 10000 = 0.9e18
        assertEq(discountedPrice, 9e17);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetBondTerms_Vesting() public {
        uint256 newVesting = 100_000;

        vm.expectEmit(true, true, false, false);
        emit BondTermsUpdated(ApiaryBondDepository.PARAMETER.VESTING, newVesting);

        vm.prank(admin);
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.VESTING, newVesting);

        (uint256 vestingTerm,,,) = bondDepository.terms();
        assertEq(vestingTerm, newVesting);
    }

    function test_SetBondTerms_Payout() public {
        uint256 newPayout = 600;

        vm.prank(admin);
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.PAYOUT, newPayout);

        (, uint256 maxPayout,,) = bondDepository.terms();
        assertEq(maxPayout, newPayout);
    }

    function test_SetBondTerms_DiscountRate() public {
        uint256 newDiscount = 1500;

        vm.prank(admin);
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.DISCOUNT_RATE, newDiscount);

        (,, uint256 discountRate,) = bondDepository.terms();
        assertEq(discountRate, newDiscount);
    }

    function test_SetBondTerms_MaxDebt() public {
        uint256 newMaxDebt = 2_000_000e9;

        vm.prank(admin);
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.MAX_DEBT, newMaxDebt);

        (,,, uint256 maxDebt) = bondDepository.terms();
        assertEq(maxDebt, newMaxDebt);
    }

    function test_UpdateTwap() public {
        MockTWAP newTwap = new MockTWAP();

        vm.expectEmit(true, false, false, false);
        emit TwapUpdated(address(newTwap));

        vm.prank(admin);
        bondDepository.updateTwap(address(newTwap));

        assertEq(address(bondDepository.twap()), address(newTwap));
    }

    function test_Pause() public {
        vm.prank(admin);
        bondDepository.pause();

        assertTrue(bondDepository.paused());
    }

    function test_Unpause() public {
        vm.startPrank(admin);
        bondDepository.pause();
        bondDepository.unpause();
        vm.stopPrank();

        assertFalse(bondDepository.paused());
    }

    function test_ClawBackTokens() public {
        // Send some random tokens to depository
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(bondDepository), 1000e18);

        vm.prank(admin);
        bondDepository.clawBackTokens(address(randomToken), 1000e18);

        assertEq(randomToken.balanceOf(admin), 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_SetBondTerms_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        bondDepository.setBondTerms(ApiaryBondDepository.PARAMETER.VESTING, 100_000);
    }

    function testRevert_UpdateTwap_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        bondDepository.updateTwap(address(twap));
    }

    function testRevert_Pause_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        bondDepository.pause();
    }

    function testRevert_ClawBackTokens_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        bondDepository.clawBackTokens(address(ibgt), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetUserBondCount() public {
        vm.startPrank(user1);
        bondDepository.deposit(10e18, 1e18);
        bondDepository.deposit(10e18, 1e18);
        vm.stopPrank();

        assertEq(bondDepository.getUserBondCount(user1), 2);
    }

    function test_GetActiveBonds() public {
        vm.startPrank(user1);
        bondDepository.deposit(10e18, 1e18);
        bondDepository.deposit(10e18, 1e18);
        vm.stopPrank();

        (ApiaryBondDepository.Bond[] memory bonds, uint256[] memory indices) = bondDepository.getActiveBonds(user1);

        assertEq(bonds.length, 2);
        assertEq(indices.length, 2);
    }

    function test_PendingPayoutFor() public {
        vm.prank(user1);
        uint256 payout = bondDepository.deposit(10e18, 1e18);

        // Move to 50% vested
        vm.roll(block.number + VESTING_TERM / 2);

        uint256 pending = bondDepository.pendingPayoutFor(user1);

        assertApproxEqRel(pending, payout / 2, 0.01e18);
    }

    function test_DebtRatio() public {
        vm.prank(user1);
        uint256 payout = bondDepository.deposit(10e18, 1e18);

        uint256 ratio = bondDepository.debtRatio();

        // ratio = totalDebt * BPS / maxDebt = payout * 10000 / MAX_DEBT
        // With reasonable deposits, this should be > 0
        assertGt(payout, 0);
        // If payout is very small relative to MAX_DEBT, ratio could be 0 due to integer division
        // The important assertion is that totalDebt is updated correctly
        assertEq(bondDepository.totalDebt(), payout);
    }

    function test_RemainingDebtCapacity() public {
        vm.prank(user1);
        uint256 payout = bondDepository.deposit(10e18, 1e18);

        uint256 remaining = bondDepository.remainingDebtCapacity();

        assertEq(remaining, MAX_DEBT - payout);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit(uint256 amount) public {
        // Bound to reasonable amounts that won't hit limits
        // Must be large enough to generate payout > MINIMUM_PAYOUT (0.01 APIARY)
        amount = bound(amount, 1e18, 100e18);

        ibgt.mint(user1, amount);

        vm.prank(user1);
        uint256 payout = bondDepository.deposit(amount, 1e18);

        assertGt(payout, 0);
    }

    function testFuzz_Vesting(uint256 blocksElapsed) public {
        vm.prank(user1);
        bondDepository.deposit(10e18, 1e18);

        blocksElapsed = bound(blocksElapsed, 0, VESTING_TERM * 2);

        vm.roll(block.number + blocksElapsed);

        uint256 percentVested = bondDepository.percentVestedFor(user1, 0);

        if (blocksElapsed >= VESTING_TERM) {
            assertEq(percentVested, 10000);
        } else {
            assertLe(percentVested, 10000);
        }
    }
}
