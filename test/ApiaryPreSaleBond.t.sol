// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { ApiaryPreSaleBond } from "../src/ApiaryPreSaleBond.sol";
import { IApiaryPreSaleBond } from "../src/interfaces/IApiaryPreSaleBond.sol";
import { PreSaleBondState, InvestorBondInfo } from "../src/types/BeraReserveTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ApiaryPreSaleBondTest
 * @notice Comprehensive test suite for pre-sale bond contract
 * @dev Tests merkle proof verification, whitelist, vesting, and state transitions
 * 
 * Test Categories:
 * 1. Deployment & Initialization
 * 2. Merkle Proof / Whitelist Verification
 * 3. Purchase (purchaseApiary)
 * 4. Vesting
 * 5. State Transitions
 * 6. Admin Functions
 * 7. Access Control
 * 8. Edge Cases
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

    function mint(address to, uint256 amount) external override {
        // For presale contract to call
        _mint(to, amount);
    }
}

contract ApiaryPreSaleBondTest is Test {
    ApiaryPreSaleBond public preSaleBond;
    MockAPIARY public apiary;
    MockERC20 public honey;

    // Test accounts
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public attacker = makeAddr("attacker");

    // Constants from contract
    uint256 public constant PRE_SALE_TOTAL_APIARY = 110_000e9;
    uint256 public constant TOKEN_PRICE = 25e16; // 0.25 HONEY per APIARY
    uint256 public constant BOND_PURCHASE_LIMIT = 500e9; // 500 APIARY
    uint48 public constant VESTING_DURATION = 5 days;

    // Merkle tree data (simple 3-address tree)
    bytes32 public merkleRoot;
    bytes32[] public user1Proof;
    bytes32[] public user2Proof;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ApiaryPurchased(address indexed user, uint128 indexed apiaryAmount, uint128 indexed honeyAmount);
    event PreSaleBondStarted(PreSaleBondState indexed state);
    event PreSaleBondEnded(PreSaleBondState indexed state);
    event TotalApiaryMinted(uint256 indexed amount);
    event TokenPriceSet(uint128 indexed price);
    event ApiaryUnlocked(address indexed user, uint256 indexed amount);
    event TreasurySet(address indexed treasury);
    event MerkleRootSet(bytes32 indexed merkleRoot);
    event TgeStarted(uint48 indexed tgeStartTime);
    event BondPurchaseLimitSet(uint128 indexed bondPurchaseLimit);
    event WhitelistEnabled(bool indexed isEnabled);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Create merkle tree for user1 and user2
        // Leaf format: keccak256(bytes.concat(keccak256(abi.encode(address))))
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(user1))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(user2))));
        bytes32 leaf3 = keccak256(bytes.concat(keccak256(abi.encode(user3))));

        // Simple merkle tree with 3 leaves
        // For simplicity, we'll use a 2-level tree: [leaf1, leaf2] -> root
        // In production, you'd use a proper merkle tree library
        if (leaf1 < leaf2) {
            merkleRoot = keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            merkleRoot = keccak256(abi.encodePacked(leaf2, leaf1));
        }

        // Create simple proofs for the 2-address tree
        user1Proof = new bytes32[](1);
        user1Proof[0] = leaf2;

        user2Proof = new bytes32[](1);
        user2Proof[0] = leaf1;

        // Deploy mocks
        apiary = new MockAPIARY();
        honey = new MockERC20("Honey", "HONEY", 18);

        // Deploy pre-sale bond
        vm.prank(admin);
        preSaleBond = new ApiaryPreSaleBond(
            address(honey),
            treasury,
            admin,
            merkleRoot
        );

        // Set APIARY token
        vm.prank(admin);
        preSaleBond.setApiaryToken(address(apiary));

        // Give users HONEY
        honey.mint(user1, 1_000_000e18);
        honey.mint(user2, 1_000_000e18);
        honey.mint(user3, 1_000_000e18);
        honey.mint(attacker, 1_000_000e18);

        // Approve pre-sale contract
        vm.prank(user1);
        honey.approve(address(preSaleBond), type(uint256).max);

        vm.prank(user2);
        honey.approve(address(preSaleBond), type(uint256).max);

        vm.prank(user3);
        honey.approve(address(preSaleBond), type(uint256).max);

        vm.prank(attacker);
        honey.approve(address(preSaleBond), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_Owner() public view {
        assertEq(preSaleBond.owner(), admin);
    }

    function test_Deployment_HoneyToken() public view {
        assertEq(address(preSaleBond.honey()), address(honey));
    }

    function test_Deployment_Treasury() public view {
        assertEq(preSaleBond.treasury(), treasury);
    }

    function test_Deployment_MerkleRoot() public view {
        assertEq(preSaleBond.merkleRoot(), merkleRoot);
    }

    function test_Deployment_DefaultTokenPrice() public view {
        assertEq(preSaleBond.tokenPrice(), TOKEN_PRICE);
    }

    function test_Deployment_DefaultBondPurchaseLimit() public view {
        assertEq(preSaleBond.bondPurchaseLimit(), BOND_PURCHASE_LIMIT);
    }

    function test_Deployment_WhitelistEnabled() public view {
        assertTrue(preSaleBond.isWhitelistEnabled());
    }

    function test_Deployment_StateNotStarted() public view {
        assertEq(uint256(preSaleBond.currentPreSaleBondState()), uint256(PreSaleBondState.NotStarted));
    }

    function testRevert_Deployment_ZeroHoney() public {
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_ADDRESS.selector);
        new ApiaryPreSaleBond(
            address(0),
            treasury,
            admin,
            merkleRoot
        );
    }

    function testRevert_Deployment_ZeroTreasury() public {
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_ADDRESS.selector);
        new ApiaryPreSaleBond(
            address(honey),
            address(0),
            admin,
            merkleRoot
        );
    }

    function testRevert_Deployment_ZeroMerkleRoot() public {
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_MERKLE_ROOT.selector);
        new ApiaryPreSaleBond(
            address(honey),
            treasury,
            admin,
            bytes32(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    MERKLE PROOF / WHITELIST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsWhitelisted_ValidProof() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        assertTrue(preSaleBond.isWhitelisted(user1, user1Proof));
        assertTrue(preSaleBond.isWhitelisted(user2, user2Proof));
    }

    function test_IsWhitelisted_InvalidProof() public view {
        bytes32[] memory emptyProof = new bytes32[](0);

        assertFalse(preSaleBond.isWhitelisted(user1, emptyProof));
    }

    function test_IsWhitelisted_WrongAddress() public view {
        // User3's proof is for user3, but we check if attacker is whitelisted
        assertFalse(preSaleBond.isWhitelisted(attacker, user1Proof));
    }

    function test_IsWhitelisted_WhitelistDisabled() public {
        vm.prank(admin);
        preSaleBond.setWhitelistEnabled(false);

        bytes32[] memory emptyProof = new bytes32[](0);

        // When whitelist is disabled, anyone is "whitelisted"
        assertTrue(preSaleBond.isWhitelisted(attacker, emptyProof));
    }

    /*//////////////////////////////////////////////////////////////
                        PURCHASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PurchaseApiary_Success() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        uint256 honeyAmount = 125e18; // $125 = 500 APIARY at $0.25
        uint256 expectedApiary = 500e9;

        vm.expectEmit(true, true, true, false);
        emit ApiaryPurchased(user1, uint128(expectedApiary), uint128(honeyAmount));

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        InvestorBondInfo memory info = preSaleBond.investorAllocations(user1);
        assertEq(info.totalAmount, expectedApiary);
    }

    function test_PurchaseApiary_TransfersHoneyToTreasury() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        uint256 honeyAmount = 125e18;
        uint256 treasuryBalanceBefore = honey.balanceOf(treasury);

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        assertEq(honey.balanceOf(treasury), treasuryBalanceBefore + honeyAmount);
    }

    function test_PurchaseApiary_UpdatesTotalBondsSold() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        uint256 honeyAmount = 125e18;
        uint256 expectedApiary = 500e9;

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        assertEq(preSaleBond.totalBondsSold(), expectedApiary);
    }

    function test_PurchaseApiary_UpdatesTotalHoneyRaised() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        uint256 honeyAmount = 125e18;

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        assertEq(preSaleBond.totalHoneyRaised(), honeyAmount);
    }

    function test_PurchaseApiary_RefundsExcessWhenLimitReached() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        uint256 honeyAmount = 200e18; // More than needed for 500 APIARY
        uint256 user1HoneyBefore = honey.balanceOf(user1);

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        // User should have been refunded excess
        // 500 APIARY * 0.25 = 125 HONEY used
        uint256 expectedUsed = 125e18;
        assertEq(honey.balanceOf(user1), user1HoneyBefore - expectedUsed);
    }

    function test_PurchaseApiary_WhitelistDisabled() public {
        vm.startPrank(admin);
        preSaleBond.setWhitelistEnabled(false);
        preSaleBond.startPreSaleBond();
        vm.stopPrank();

        bytes32[] memory emptyProof = new bytes32[](0);

        // Attacker (not whitelisted) can now purchase
        vm.prank(attacker);
        preSaleBond.purchaseApiary(25e18, emptyProof, 0); // 100 APIARY

        InvestorBondInfo memory info = preSaleBond.investorAllocations(attacker);
        assertEq(info.totalAmount, 100e9);
    }

    function testRevert_PurchaseApiary_NotLive() public {
        // Still in NotStarted state
        vm.prank(user1);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__PRE_SALE_NOT_LIVE.selector);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);
    }

    function testRevert_PurchaseApiary_InvalidProof() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        bytes32[] memory emptyProof = new bytes32[](0);

        vm.prank(attacker);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_PROOF.selector);
        preSaleBond.purchaseApiary(125e18, emptyProof, 0);
    }

    function testRevert_PurchaseApiary_MaxBondReached() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        // First purchase to max
        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        // Second purchase should fail
        vm.prank(user1);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__MAX_BOND_REACHED.selector);
        preSaleBond.purchaseApiary(25e18, user1Proof, 0);
    }

    function testRevert_PurchaseApiary_SlippageExceeded() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__SLIPPAGE_EXCEEDED.selector);
        preSaleBond.purchaseApiary(25e18, user1Proof, 1000e9); // Expect 1000 APIARY but only get 100
    }

    function testRevert_PurchaseApiary_WhenPaused() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(admin);
        preSaleBond.pause();

        vm.prank(user1);
        vm.expectRevert();
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Vesting_BeforeTGE() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        // Before TGE, vested amount should be 0
        assertEq(preSaleBond.vestedAmount(user1), 0);
        assertEq(preSaleBond.unlockedAmount(user1), 0);
    }

    function test_Vesting_LinearAfterTGE() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        // End pre-sale and start TGE
        vm.startPrank(admin);
        preSaleBond.endPreSaleBond();
        preSaleBond.mintApiary();
        preSaleBond.setTgeStartTime();
        vm.stopPrank();

        // Move to 50% of vesting
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 vested = preSaleBond.vestedAmount(user1);
        assertApproxEqRel(vested, 250e9, 0.01e18); // ~50% of 500 APIARY
    }

    function test_Vesting_FullyVestedAfterDuration() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        vm.startPrank(admin);
        preSaleBond.endPreSaleBond();
        preSaleBond.mintApiary();
        preSaleBond.setTgeStartTime();
        vm.stopPrank();

        // Move past vesting duration
        vm.warp(block.timestamp + VESTING_DURATION + 1);

        uint256 vested = preSaleBond.vestedAmount(user1);
        assertEq(vested, 500e9); // Fully vested
    }

    function test_UnlockApiary() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        vm.startPrank(admin);
        preSaleBond.endPreSaleBond();
        preSaleBond.mintApiary();
        preSaleBond.setTgeStartTime();
        vm.stopPrank();

        // Move past vesting
        vm.warp(block.timestamp + VESTING_DURATION + 1);

        vm.expectEmit(true, true, false, false);
        emit ApiaryUnlocked(user1, 500e9);

        vm.prank(user1);
        preSaleBond.unlockApiary();

        assertEq(apiary.balanceOf(user1), 500e9);
    }

    function testRevert_UnlockApiary_NoVestingSchedule() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        // User hasn't purchased anything
        vm.prank(user1);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__NO_VESTING_SCHEDULE.selector);
        preSaleBond.unlockApiary();
    }

    /*//////////////////////////////////////////////////////////////
                    STATE TRANSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartPreSaleBond() public {
        vm.expectEmit(true, false, false, false);
        emit PreSaleBondStarted(PreSaleBondState.Live);

        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        assertEq(uint256(preSaleBond.currentPreSaleBondState()), uint256(PreSaleBondState.Live));
    }

    function test_EndPreSaleBond() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.expectEmit(true, false, false, false);
        emit PreSaleBondEnded(PreSaleBondState.Ended);

        vm.prank(admin);
        preSaleBond.endPreSaleBond();

        assertEq(uint256(preSaleBond.currentPreSaleBondState()), uint256(PreSaleBondState.Ended));
    }

    function testRevert_StartPreSaleBond_InvalidTransition() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        // Already live, can't start again
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_STATE_TRANSITION.selector);
        preSaleBond.startPreSaleBond();
    }

    function testRevert_EndPreSaleBond_InvalidTransition() public {
        // Still in NotStarted, can't end
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_STATE_TRANSITION.selector);
        preSaleBond.endPreSaleBond();
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintApiary() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        vm.prank(admin);
        preSaleBond.endPreSaleBond();

        vm.expectEmit(true, false, false, false);
        emit TotalApiaryMinted(500e9);

        vm.prank(admin);
        preSaleBond.mintApiary();

        assertEq(apiary.balanceOf(address(preSaleBond)), 500e9);
    }

    function test_SetTgeStartTime() public {
        vm.expectEmit(true, false, false, false);
        emit TgeStarted(uint48(block.timestamp));

        vm.prank(admin);
        preSaleBond.setTgeStartTime();

        assertTrue(preSaleBond.tgeStarted());
        assertEq(preSaleBond.tgeStartTime(), uint48(block.timestamp));
    }

    function testRevert_SetTgeStartTime_AlreadyStarted() public {
        vm.prank(admin);
        preSaleBond.setTgeStartTime();

        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__TGE_ALREADY_STARTED.selector);
        preSaleBond.setTgeStartTime();
    }

    function test_SetTokenPrice() public {
        uint128 newPrice = 50e16; // 0.50 HONEY

        vm.expectEmit(true, false, false, false);
        emit TokenPriceSet(newPrice);

        vm.prank(admin);
        preSaleBond.setTokenPrice(newPrice);

        assertEq(preSaleBond.tokenPrice(), newPrice);
    }

    function testRevert_SetTokenPrice_Zero() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_AMOUNT.selector);
        preSaleBond.setTokenPrice(0);
    }

    function test_SetBondPurchaseLimit() public {
        uint128 newLimit = 1000e9;

        vm.expectEmit(true, false, false, false);
        emit BondPurchaseLimitSet(newLimit);

        vm.prank(admin);
        preSaleBond.setBondPurchaseLimit(newLimit);

        assertEq(preSaleBond.bondPurchaseLimit(), newLimit);
    }

    function testRevert_SetBondPurchaseLimit_Zero() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_AMOUNT.selector);
        preSaleBond.setBondPurchaseLimit(0);
    }

    function test_SetMerkleRoot() public {
        bytes32 newRoot = keccak256("new root");

        vm.expectEmit(true, false, false, false);
        emit MerkleRootSet(newRoot);

        vm.prank(admin);
        preSaleBond.setMerkleRoot(newRoot);

        assertEq(preSaleBond.merkleRoot(), newRoot);
    }

    function testRevert_SetMerkleRoot_Zero() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_MERKLE_ROOT.selector);
        preSaleBond.setMerkleRoot(bytes32(0));
    }

    function test_SetWhitelistEnabled() public {
        vm.expectEmit(true, false, false, false);
        emit WhitelistEnabled(false);

        vm.prank(admin);
        preSaleBond.setWhitelistEnabled(false);

        assertFalse(preSaleBond.isWhitelistEnabled());
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, false, false, false);
        emit TreasurySet(newTreasury);

        vm.prank(admin);
        preSaleBond.setTreasury(newTreasury);

        assertEq(preSaleBond.treasury(), newTreasury);
    }

    function testRevert_SetTreasury_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ApiaryPreSaleBond.APIARY__INVALID_ADDRESS.selector);
        preSaleBond.setTreasury(address(0));
    }

    function test_Pause() public {
        vm.prank(admin);
        preSaleBond.pause();

        assertTrue(preSaleBond.paused());
    }

    function test_Unpause() public {
        vm.startPrank(admin);
        preSaleBond.pause();
        preSaleBond.unpause();
        vm.stopPrank();

        assertFalse(preSaleBond.paused());
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_StartPreSaleBond_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        preSaleBond.startPreSaleBond();
    }

    function testRevert_EndPreSaleBond_NotOwner() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(attacker);
        vm.expectRevert();
        preSaleBond.endPreSaleBond();
    }

    function testRevert_MintApiary_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        preSaleBond.mintApiary();
    }

    function testRevert_SetTokenPrice_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        preSaleBond.setTokenPrice(50e16);
    }

    function testRevert_SetMerkleRoot_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        preSaleBond.setMerkleRoot(keccak256("new"));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ApiaryTokensAvailable() public view {
        assertEq(preSaleBond.apiaryTokensAvailable(), PRE_SALE_TOTAL_APIARY);
    }

    function test_ApiaryTokensAvailable_DecreasesAfterPurchase() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        assertEq(preSaleBond.apiaryTokensAvailable(), PRE_SALE_TOTAL_APIARY - 500e9);
    }

    function test_InvestorAllocations() public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        InvestorBondInfo memory info = preSaleBond.investorAllocations(user1);

        assertEq(info.totalAmount, 500e9);
        assertEq(info.unlockedAmount, 0);
        assertEq(info.duration, VESTING_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_PurchaseApiary(uint256 honeyAmount) public {
        // Bound to reasonable amounts
        honeyAmount = bound(honeyAmount, 1e18, 125e18); // Max is the purchase limit

        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(honeyAmount, user1Proof, 0);

        InvestorBondInfo memory info = preSaleBond.investorAllocations(user1);
        assertGt(info.totalAmount, 0);
        assertLe(info.totalAmount, BOND_PURCHASE_LIMIT);
    }

    function testFuzz_Vesting(uint256 timePassed) public {
        vm.prank(admin);
        preSaleBond.startPreSaleBond();

        vm.prank(user1);
        preSaleBond.purchaseApiary(125e18, user1Proof, 0);

        vm.startPrank(admin);
        preSaleBond.endPreSaleBond();
        preSaleBond.mintApiary();
        preSaleBond.setTgeStartTime();
        vm.stopPrank();

        // Bound time to reasonable range
        timePassed = bound(timePassed, 0, VESTING_DURATION * 2);

        vm.warp(block.timestamp + timePassed);

        uint256 vested = preSaleBond.vestedAmount(user1);

        if (timePassed >= VESTING_DURATION) {
            assertEq(vested, 500e9);
        } else {
            assertLe(vested, 500e9);
        }
    }
}
