// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IInfrared
 * @notice Interface for Infrared liquid staking protocol on Berachain
 * @dev This interface is based on standard liquid staking patterns
 * 
 * ⚠️ IMPORTANT: This is a MOCK interface based on common LST patterns
 * TODO: Update with actual Infrared protocol interface once available
 * 
 * Expected Infrared functionality:
 * - Stake iBGT to earn yield
 * - Receive staked position (likely as shares or receipt tokens)
 * - Claim accumulated rewards (BGT, HONEY, or protocol tokens)
 * - Unstake to withdraw original iBGT + accrued rewards
 * 
 * Based on liquid staking standards:
 * - Lido (stETH): deposit(), withdraw(), balanceOf()
 * - Rocket Pool: deposit(), burn(), getBalance()
 * - Standard ERC4626 vaults: deposit(), withdraw(), redeem()
 */
interface IInfrared {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice User staking position information
     * @param amount Total iBGT staked
     * @param shares Internal accounting shares
     * @param lastRewardBlock Last block rewards were claimed
     * @param rewardDebt Accumulated rewards that were already claimed
     */
    struct StakeInfo {
        uint256 amount;
        uint256 shares;
        uint256 lastRewardBlock;
        uint256 rewardDebt;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 indexed amount, uint256 indexed shares);
    event Unstaked(address indexed user, uint256 indexed amount, uint256 indexed shares);
    event RewardsClaimed(address indexed user, uint256 indexed rewardAmount, address indexed rewardToken);
    event RewardAdded(uint256 indexed reward, uint256 indexed rewardPerBlock);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake iBGT to earn yield
     * @param amount Amount of iBGT to stake
     * @return shares Amount of shares minted (internal accounting)
     */
    function stake(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Unstake iBGT and claim accrued rewards
     * @param amount Amount of iBGT to unstake
     * @return withdrawn Amount of iBGT withdrawn
     */
    function unstake(uint256 amount) external returns (uint256 withdrawn);

    /**
     * @notice Claim pending rewards without unstaking
     * @return rewardAmount Amount of rewards claimed
     */
    function claimRewards() external returns (uint256 rewardAmount);

    /**
     * @notice Emergency withdraw without claiming rewards
     * @dev May incur penalty fee
     */
    function emergencyWithdraw() external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending rewards for a user
     * @param user User address
     * @return Amount of pending rewards
     */
    function pendingRewards(address user) external view returns (uint256);

    /**
     * @notice Get staked balance for a user
     * @param user User address
     * @return Amount of iBGT staked
     */
    function stakedBalance(address user) external view returns (uint256);

    /**
     * @notice Get user's share balance
     * @param user User address
     * @return Amount of shares owned
     */
    function sharesOf(address user) external view returns (uint256);

    /**
     * @notice Get stake information for a user
     * @param user User address
     * @return StakeInfo struct with user's staking data
     */
    function getStakeInfo(address user) external view returns (StakeInfo memory);

    /**
     * @notice Get total iBGT staked in protocol
     * @return Total amount staked
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Get total shares in circulation
     * @return Total shares amount
     */
    function totalShares() external view returns (uint256);

    /**
     * @notice Get reward token address
     * @return Address of reward token (BGT, HONEY, or protocol token)
     */
    function rewardToken() external view returns (address);

    /**
     * @notice Get iBGT token address
     * @return Address of iBGT token
     */
    function ibgtToken() external view returns (address);

    /**
     * @notice Check if there's a lockup period
     * @return Lockup duration in seconds (0 if none)
     */
    function lockupPeriod() external view returns (uint256);

    /**
     * @notice Get unstaking fee (if any)
     * @return Fee in basis points (10000 = 100%)
     */
    function unstakeFee() external view returns (uint256);

    /**
     * @notice Get reward rate per block
     * @return Reward amount per block
     */
    function rewardPerBlock() external view returns (uint256);

    /**
     * @notice Convert shares to iBGT amount
     * @param shares Amount of shares
     * @return Amount of iBGT equivalent
     */
    function sharesToAmount(uint256 shares) external view returns (uint256);

    /**
     * @notice Convert iBGT amount to shares
     * @param amount Amount of iBGT
     * @return Amount of shares equivalent
     */
    function amountToShares(uint256 amount) external view returns (uint256);
}

/**
 * @title IInfraredVault
 * @notice Alternative interface if Infrared uses ERC4626 vault standard
 * @dev This follows the ERC4626 tokenized vault standard
 * 
 * ⚠️ Use this interface if Infrared implements ERC4626
 */
interface IInfraredVault {
    // ERC4626 standard functions
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    
    // View functions
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    
    // Asset/share token
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
}
