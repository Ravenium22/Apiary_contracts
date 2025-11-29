// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ERC20Permit } from "./libs/ERC20Permit.sol";
import { ERC20 } from "./libs/ERC20.sol";
import { VaultOwned } from "./VaultOwned.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { TreasuryValueData } from "./types/BeraReserveTypes.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { BeraReserveTokenUtils } from "./utils/BeraReserveTokenUtils.sol";

contract BeraReserveToken is ERC20Permit, VaultOwned, AccessControl {
    using Math for uint256;
    using Math for uint48;

    /**
     * BeraReserve Tokenomics Overview:
     *
     * - **Total Supply**: 200_000 BRR
     * - **Initial Market Cap**: $200,000
     * - **Token Price**: $1.01
     *
     * **Allocations:**
     * - **Team** (20%) - 40,000 BRR (Staked 🟢🟢)
     *   - Linearly vested over 1 year with a 3-month cliff.
     *
     * - **Marketing** (5%) - 10,000 BRR (Staked 🟢🟢)
     *   - Linearly vested over 1 year.
     *
     * - **Treasury** (20%) - 40,000 BRR
     *
     * - **Liquidity** (5%) - 10,000 BRR
     *
     * - **Seed Round** (20%) - 40,000 BRR (Staked 🟢🟢)
     *   - 30% TGE (12,000 BRR available for minting).
     *   - 70% (28,000 BRR) vested over 6 months.
     *
     * - **Pre-Bonds** (5%) - 10,000 BRR ($10,000)
     *
     * - **Airdrop** (12%) - 24,000 BRR
     *
     * - **Rewards & Incentives** (13%) - 26,000 BRR
     */

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS AND IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    uint256 internal constant BPS = 10_000; // Total basis points
    uint256 internal constant LIQUIDITY_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint256 internal constant AIRDROP_TOTAL_BRR_AMOUNT = 24_000e9; //24,000 (12% of total supply)
    uint256 internal constant REWARDS_TOTAL_BRR_AMOUNT = 26_000e9; // 26,000 BRR (13% of total supply)
    uint256 public constant INITIAL_BRR_SUPPLY = 160_000e9; // 160,000 BRR
    address internal constant LIQUIDITY_WALLET = 0x8a25AB76278FA62979Eb40D7Aa1e569447CA68c0;
    address internal immutable REWARDS_WALLET;
    address internal immutable AIRDROP_WALLET;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IUniswapV2Router02 internal uniswapV2Router;

    address public uniswapV2Pair;
    uint256 public buyFee;
    uint256 public sellFee;
    bool public isFeeDisabled;
    address public feeDistributor;
    uint256 public decayRatio; // Decay ratio ex: 20% is 2_000
    uint256 public decayInterval; // Configurable decay interval in seconds
    uint256 public treasuryValue;
    uint256 public marketCap;

    address public protocolTreasuryAddress;
    uint256 public twentyFivePercentBelowFees;
    uint256 public tenPercentBelowFees;
    uint256 public belowTreasuryValueFees;
    uint256 public treasuryAllocation;
    uint256 public totalTreasuryMinted;
    uint256 public totalMintedSupply;

    mapping(address user => uint48 timestamp) public lastTimeBurnt;
    mapping(address user => uint48 timestamp) public lastTimeStaked;
    mapping(address user => uint48 timestamp) public lastTimeReceived;
    mapping(address user => bool feeFlag) public isExcludedAccountsFromFees;
    mapping(address user => bool decayFlag) public isExcludedAccountsFromDecay;
    mapping(address user => uint256 amount) public allocationLimits;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ExcludeAccountsFromFees(address indexed account, bool indexed isExcluded);
    event ExcludeAccountsFromDecay(address indexed account, bool indexed isExcluded);
    event MultipleAccountsExcludedFromFees(address[] indexed accounts);
    event MultipleAccountsExcludedFromDecay(address[] indexed accounts);
    event DecayRatioUpdated(uint256 indexed decayRatio);
    event BuyFeeUpdated(uint256 indexed buyFee);
    event SellFeeUpdated(uint256 indexed sellFee);
    event TwentyFivePercentBelowFeesSet(uint256 indexed fees);
    event BelowTreasuryValueFeesSet(uint256 indexed _fees);
    event TenPercentBelowFeesSet(uint256 indexed fees);
    event FeeDistributorUpdated(address indexed feeDistributor);
    event FeeDisabledUpdated(bool indexed isFeeDisabled);
    event UniswapRouterUpdated(address indexed router);
    event DecayIntervalUpdated(uint256 indexed decayInterval);
    event MinterAllocationSet(address indexed minter, uint256 indexed maxNumberOfTokens);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BERA_RESERVE__ONLY_MINTER();
    error BERA_RESERVE__ONLY_BURNER();
    error BERA_RESERVE__FEE_TOO_HIGH();
    error BERA_RESERVE__DECAY_TOO_HIGH();
    error BERA_RESERVE__BURN_AMOUNT_EXCEEDS_ALLOWANCE();
    error BERA_RESERVE__INVALID_ADDRESS();
    error BERA_RESERVE__TRANSFER_AMOUNT_EXCEEDS_BALANCE();
    error BERA_RESERVE__TOTAL_SUPPLY_EXCEEDED();
    error BERA_RESERVE__ALLOCATION_LIMIT_ALREADY_SET();
    error BERA_RESERVE__ONLY_ADMIN();
    error BERA_RESERVE__MAX_MINT_ALLOC_EXCEEDED();
    error BERA_RESERVE__NOT_TREASURY();
    error BERA_RESERVE__DECAY_INTERVAL_TOO_LOW();

    constructor(address protocolAdmin, address rewardWallet, address airdropWallet) ERC20("Bera Reserve", "BRR", 9) {
        if (protocolAdmin == address(0) || rewardWallet == address(0) || airdropWallet == address(0)) {
            revert BERA_RESERVE__INVALID_ADDRESS();
        }

        REWARDS_WALLET = rewardWallet;
        AIRDROP_WALLET = airdropWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, protocolAdmin);

        buyFee = sellFee = 300;
        decayRatio = 2_000;
        decayInterval = 28_800; // Default decay interval to 8 hours

        //addresses excluded from fees and decay
        isExcludedAccountsFromFees[LIQUIDITY_WALLET] = true;
        isExcludedAccountsFromFees[REWARDS_WALLET] = true;

        isExcludedAccountsFromDecay[LIQUIDITY_WALLET] = true;
        isExcludedAccountsFromDecay[REWARDS_WALLET] = true;

        _mint(LIQUIDITY_WALLET, LIQUIDITY_TOTAL_BRR_AMOUNT);
        _mint(REWARDS_WALLET, REWARDS_TOTAL_BRR_AMOUNT);
        _mint(AIRDROP_WALLET, AIRDROP_TOTAL_BRR_AMOUNT);
    }

    function setAllocationLimit(address minter, uint256 maxNumberOfTokens) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (allocationLimits[minter] != 0) {
            revert BERA_RESERVE__ALLOCATION_LIMIT_ALREADY_SET();
        }
        /**
         * Grant the minter role to the address if it doesn't have it
         */
        if (!hasRole(MINTER_ROLE, minter)) {
            _grantRole(MINTER_ROLE, minter);
        }

        allocationLimits[minter] = maxNumberOfTokens;

        emit MinterAllocationSet(minter, maxNumberOfTokens);
    }

    function setTreasuryAllocation(uint256 _treasuryAllocation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryAllocation += _treasuryAllocation;
    }

    /**
     * @notice Mints new tokens to a specified account.
     * @param account_ The address of the account to receive the newly minted tokens.
     * @param amount_ The amount of tokens to be minted.
     * @dev This function checks if the caller has the `MINTER_ROLE` role, if the total supply cap will be exceeded,
     *       and if the caller's mint allocation limit will be exceeded. It then mints the tokens and updates the
     *      `lastTimeReceived` timestamp for the receiving account.
     */
    function mint(address account_, uint256 amount_) external onlyRole(MINTER_ROLE) {
        if (totalMintedSupply + amount_ > INITIAL_BRR_SUPPLY) revert BERA_RESERVE__TOTAL_SUPPLY_EXCEEDED();

        if (amount_ > allocationLimits[_msgSender()]) revert BERA_RESERVE__MAX_MINT_ALLOC_EXCEEDED();

        allocationLimits[_msgSender()] -= amount_;

        _mint(account_, amount_);

        totalMintedSupply += amount_;

        lastTimeReceived[account_] = uint48(block.timestamp);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external {
        _burnFrom(account_, amount_);
    }

    /**
     * @notice Function to update the last staked time.
     * Can be called whenever a stake is made.
     */
    function updateLastStakedTime(address _staker) external onlyStaking {
        lastTimeStaked[_staker] = uint48(block.timestamp);
    }

    function setProtocolTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolTreasuryAddress = _treasury;
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 count = accounts.length;
        for (uint256 i; i < count; i++) {
            isExcludedAccountsFromFees[accounts[i]] = excluded;
        }

        emit MultipleAccountsExcludedFromFees(accounts);
    }

    function excludeMultipleAccountsFromDecay(address[] calldata accounts, bool excluded)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 count = accounts.length;
        for (uint256 i; i < count; i++) {
            isExcludedAccountsFromDecay[accounts[i]] = excluded;
        }

        emit MultipleAccountsExcludedFromDecay(accounts);
    }

    function excludeAccountFromFeesAndDecay(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isExcludedAccountsFromFees[account] = excluded;
        isExcludedAccountsFromDecay[account] = excluded;
    }

    function setBuyFee(uint256 _buyFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_buyFee > BPS) revert BERA_RESERVE__FEE_TOO_HIGH();

        buyFee = _buyFee;

        emit BuyFeeUpdated(_buyFee);
    }

    function setSellFee(uint256 _sellFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_sellFee > BPS) revert BERA_RESERVE__FEE_TOO_HIGH();

        sellFee = _sellFee;

        emit SellFeeUpdated(_sellFee);
    }

    function setTwentyFivePercentBelowFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fees > BPS) revert BERA_RESERVE__FEE_TOO_HIGH();

        twentyFivePercentBelowFees = _fees;

        emit TwentyFivePercentBelowFeesSet(_fees);
    }

    function setTenPercentBelowFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fees > BPS) revert BERA_RESERVE__FEE_TOO_HIGH();

        tenPercentBelowFees = _fees;

        emit TenPercentBelowFeesSet(_fees);
    }

    function setBelowTreasuryValueFees(uint256 _fees) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fees > BPS) revert BERA_RESERVE__FEE_TOO_HIGH();

        belowTreasuryValueFees = _fees;

        emit BelowTreasuryValueFeesSet(_fees);
    }

    function setFeeDisabled(bool _isFeeDisabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isFeeDisabled = _isFeeDisabled;

        emit FeeDisabledUpdated(_isFeeDisabled);
    }

    function setFeeDistributor(address _feeDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeDistributor == address(0)) revert BERA_RESERVE__INVALID_ADDRESS();

        feeDistributor = _feeDistributor;

        emit FeeDistributorUpdated(_feeDistributor);
    }

    function setDecayRatio(uint256 _decayRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_decayRatio > BPS) revert BERA_RESERVE__DECAY_TOO_HIGH();

        decayRatio = _decayRatio;

        emit DecayRatioUpdated(_decayRatio);
    }

    function setDecayInterval(uint256 _decayInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_decayInterval == 0) revert BERA_RESERVE__DECAY_INTERVAL_TOO_LOW();
        decayInterval = _decayInterval;

        emit DecayIntervalUpdated(_decayInterval);
    }

    function setTreasuryValue(uint256 _treasuryValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryValue = _treasuryValue;
    }

    function getTreasuryValue() external view returns (uint256) {
        return treasuryValue;
    }

    function getMarketCap() public view virtual returns (uint256 marketCapValue) {
        return marketCap;
    }

    function setMarketCap(uint256 _marketCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        marketCap = _marketCap;
    }

    /**
     * @param from_ The address of the sender.
     * @dev This function applies a decay mechanism to the sender's balance if they are not excluded from decay.
     *      It calculates the amount of tokens to be burned based on the decay ratio and the last interaction times.
     *      The total supply is updated to reflect the burned tokens, and the sender's balance is adjusted accordingly.
     */
    function _beforeTokenTransfer(address from_, address, /*to_*/ uint256 /*amount_*/ ) internal override {
        if (_balances[from_] != 0 && !isExcludedAccountsFromDecay[from_]) {
            uint256 tokensToBurn = BeraReserveTokenUtils.applyDecay(
                decayRatio,
                _balances[from_],
                lastTimeBurnt[from_],
                lastTimeReceived[from_],
                lastTimeStaked[from_],
                decayInterval
            );

            // Calculate the remaining sender balance after burning tokens
            uint256 balanceRemaining = balanceOf(from_);

            // Update the total supply by subtracting the burned tokens
            _totalSupply -= tokensToBurn;

            lastTimeBurnt[from_] = uint48(block.timestamp);

            _balances[from_] = balanceRemaining;

            emit Transfer(from_, address(0), tokensToBurn);
        }
    }

    /**
     * @notice Handles the internal token transfer mechanism, including decay and fees.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     *  @dev This function decays the sender's balance before transfer, checks for sufficient balance,
     *     and applies fees if applicable. It also updates the recipient's balance
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (sender == address(0) || recipient == address(0)) revert BERA_RESERVE__INVALID_ADDRESS();

        //decay the sender's balance
        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];

        if (senderBalance < amount) revert BERA_RESERVE__TRANSFER_AMOUNT_EXCEEDS_BALANCE();

        _balances[sender] -= amount;

        if (!isExcludedAccountsFromFees[sender] || !isExcludedAccountsFromFees[recipient] || !isFeeDisabled) {
            if (sender == uniswapV2Pair) {
                // Apply buy fee
                amount = _applyFee(sender, amount, buyFee);
            } else if (recipient == uniswapV2Pair) {
                // Calculate and apply sliding scale sell fee.
                TreasuryValueData memory rvfData = BeraReserveTokenUtils.calculateSlidingScaleFee(
                    marketCap,
                    treasuryValue,
                    sellFee,
                    tenPercentBelowFees,
                    twentyFivePercentBelowFees,
                    belowTreasuryValueFees
                );

                if (rvfData.treasuryPercentage == 0) {
                    // Apply standard sell fee
                    amount = _applyFee(sender, amount, rvfData.fee);
                } else {
                    // Apply sliding scale fee, splitting between treasury and burn
                    (uint256 fee, uint256 treasuryFee, uint256 burnFee) = BeraReserveTokenUtils.applySlidingScaleFee(
                        marketCap,
                        treasuryValue,
                        sellFee,
                        tenPercentBelowFees,
                        twentyFivePercentBelowFees,
                        belowTreasuryValueFees
                    );

                    if (treasuryFee != 0) {
                        _balances[protocolTreasuryAddress] += treasuryFee;

                        emit Transfer(sender, recipient, treasuryFee);
                    }
                    if (burnFee != 0) {
                        _totalSupply -= burnFee;

                        emit Transfer(sender, address(0), burnFee);
                    }

                    amount -= fee;
                }
            }
        }

        _balances[recipient] += amount;
        lastTimeReceived[recipient] = uint48(block.timestamp);

        emit Transfer(sender, recipient, amount);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        if (allowance(account_, msg.sender) < amount_) revert BERA_RESERVE__BURN_AMOUNT_EXCEEDS_ALLOWANCE();

        uint256 decreasedAllowance_ = allowance(account_, msg.sender) - amount_;

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_balances[account] != 0 && !isExcludedAccountsFromDecay[account]) {
            uint256 tokensToBurn = BeraReserveTokenUtils.applyDecay(
                decayRatio,
                _balances[account],
                lastTimeBurnt[account],
                lastTimeReceived[account],
                lastTimeStaked[account],
                decayInterval
            );

            if (tokensToBurn > _balances[account]) {
                return 0;
            }

            return _balances[account] - tokensToBurn;
        }
        return _balances[account];
    }

    function _applyFee(address payer, uint256 amount, uint256 fee) internal returns (uint256) {
        uint256 feeAmount = amount.mulDiv(fee, BPS);

        _balances[feeDistributor] += feeAmount;

        emit Transfer(payer, feeDistributor, feeAmount);

        return amount - feeAmount;
    }

    function updateUniswapV2Pair(address newPair) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPair == address(0)) revert BERA_RESERVE__INVALID_ADDRESS();
        uniswapV2Pair = newPair;
    }
}
