// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IBeraReserveLockUp } from "./interfaces/IBeraReserveLockUp.sol";
import { IBeraReserveStaking } from "./interfaces/IBeraReserveStaking.sol";
import { IBeraReserveToken } from "./interfaces/IBeraReserveToken.sol";
import { VestingSchedule, MemberType } from "./types/BeraReserveTypes.sol";

/**
 * Vesting Schedules
 * 20% team (linearly vested over 1 year, 3 months cliff) 🟢 🟢
 * 5% marketing (linearly vested over 1 year) 🟢 🟢
 * 20% seed round (30% TGE, 6 months vesting) 🟢 🟢
 *
 * | Team Vesting Schedule            |
 * |----------------------------------|
 * | 0 months | Cliff (no release)    |
 * | 3 months | Linear release begins |
 * | 12 months| Fully vested          |
 *
 * | Marketing Vesting Schedule       |
 * |----------------------------------|
 * | 0 months | Linear release begins |
 * | 12 months| Fully vested          |
 *
 * | Seed Round Vesting Schedule      |
 * |----------------------------------|
 * | TGE (0 months) | 30% immediate   |
 * | 6 months       | Linear release  |
 * |                | Fully vested    |
 * @author 0xm00k
 */
contract BeraReserveLockUp is IBeraReserveLockUp, Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeraReserveToken;

    uint32 public constant TEAM_VESTING_DURATION = 365 * 24 * 60 * 60 seconds; // 1 year
    uint32 public constant TEAM_VESTING_CLIFF = 90 * 24 * 60 * 60 seconds; // 3 months
    uint32 public constant MARKETING_VESTING_DURATION = 365 * 24 * 60 * 60 seconds; // 1 year
    uint32 public constant SEED_ROUND_VESTING_DURATION = 180 * 24 * 60 * 60 seconds; // 6 months

    uint128 public constant TOTAL_BPS = 10_000; // 100%
    uint128 public constant SEED_ROUND_BPS = 3_000; // 30%

    uint128 public constant TEAM_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    uint128 public constant MARKETING_TOTAL_BRR_AMOUNT = 10_000e9; // 10,000 BRR (5% of total supply)
    uint128 public constant SEED_ROUND_TOTAL_BRR_AMOUNT = 40_000e9; // 40,000 BRR (20% of total supply)
    /**
     * @notice VESTING TOTAL BRR AMOUNT DETAILS:
     * TEAM ALLOCATION : 40,000 BRR.
     * MARKETING ALLOCATION : 10,000 BRR.
     * SEED ALLOCATION : 40,000 BRR.
     */
    uint128 public constant VESTING_TOTAL_BRR_AMOUNT = 90_000e9;
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address user => VestingSchedule) public teamsSchedules;
    mapping(address user => VestingSchedule) public marketingSchedules;
    mapping(address user => VestingSchedule) public seedRoundSchedules;

    IBeraReserveStaking public beraStaking;
    IBeraReserveToken public brrToken;
    IERC20 public sBrrToken;

    uint128 public totalTeamBRRAllocated;
    uint128 public totalMarketingBRRAllocated;
    uint128 public totalSeedRoundBRRAllocated;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SbrrUnlocked(address indexed user, uint256 indexed amount);
    event TeamMemberAdded(address indexed user, uint256 indexed totalAmount);
    event MarketingMemberAdded(address indexed user, uint256 indexed totalAmount);
    event SeedRoundMemberAdded(address indexed user, uint256 indexed totalAmount);
    event SeedRoundBrrUnlocked(address indexed user, uint256 indexed amount);
    event TotalBrrMintedAndStaked(uint256 indexed totalAmountMinted, uint256 indexed totalAmountStaked);
    event SbrrClaimed();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BRR__NO_VESTING_SCHEDULE_FOUND();
    error BRR__NO_BRR_TO_UNLOCK();
    error BERA_RESERVE_LENGTH_MISMATCH();
    error BRR_INVALID_AMOUNT();
    error BRR__INVALID_ADDRESS();
    error BRR_INVALID_ADDRESS_OR_AMOUNT();
    error BRR_TRANSFER_FAILED();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier validAddressAndAmount(address user, uint128 amount) {
        if (user == address(0) || amount == 0) {
            revert BRR_INVALID_ADDRESS_OR_AMOUNT();
        }
        _;
    }

    constructor(address protocolAdmin, address _brrToken, address _sBrrToken, address _staking)
        Ownable(protocolAdmin)
    {
        if (
            protocolAdmin == address(0) || _staking == address(0) || _brrToken == address(0) || _sBrrToken == address(0)
        ) {
            revert BRR__INVALID_ADDRESS();
        }

        beraStaking = IBeraReserveStaking(_staking);
        brrToken = IBeraReserveToken(_brrToken);
        sBrrToken = IERC20(_sBrrToken);
    }

    function mintAndStakeBRR() external override onlyOwner {
        brrToken.mint(address(this), VESTING_TOTAL_BRR_AMOUNT);

        uint256 totalAmountToStake =
            TEAM_TOTAL_BRR_AMOUNT + MARKETING_TOTAL_BRR_AMOUNT + ((7_000 * SEED_ROUND_TOTAL_BRR_AMOUNT) / 10_000);

        _autoStake(totalAmountToStake);

        emit TotalBrrMintedAndStaked(VESTING_TOTAL_BRR_AMOUNT, totalAmountToStake);
    }

    function claimSbrr() external onlyOwner {
        beraStaking.claim(address(this));

        emit SbrrClaimed();
    }

    function addMultipleTeamMembers(address[] calldata members, uint128[] calldata totalAmounts)
        external
        override
        onlyOwner
    {
        if (members.length != totalAmounts.length) revert BERA_RESERVE_LENGTH_MISMATCH();

        uint256 numOfMembers = members.length;
        for (uint256 i; i < numOfMembers; i++) {
            addTeamMember(members[i], totalAmounts[i]);
        }
    }

    function addMultipleMarketingMembers(address[] calldata members, uint128[] calldata totalAmounts)
        external
        override
        onlyOwner
    {
        if (members.length != totalAmounts.length) revert BERA_RESERVE_LENGTH_MISMATCH();

        uint256 numOfMembers = members.length;
        for (uint256 i; i < numOfMembers; i++) {
            addMarketingMember(members[i], totalAmounts[i]);
        }
    }

    function addMultipleSeedRoundMembers(address[] calldata members, uint128[] calldata totalAmounts)
        external
        override
        onlyOwner
    {
        if (members.length != totalAmounts.length) revert BERA_RESERVE_LENGTH_MISMATCH();

        uint256 numOfMembers = members.length;
        for (uint256 i; i < numOfMembers; i++) {
            addSeedRoundMember(members[i], totalAmounts[i]);
        }
    }

    /**
     * @notice Initiates the TGE unlock for the seed round investor.
     * @dev Transfers the BRR tokens unlocked at TGE to the investor and marks the amount as claimed.
     * @dev If the investor has no unlocked amount, the function does nothing.
     */
    function initiateTGEUnlock() external override {
        uint256 brrAvailableAtTGE = seedRoundSchedules[msg.sender].amountUnlockedAtTGE;

        if (brrAvailableAtTGE != 0) {
            //transfer Brr to user
            brrToken.safeTransfer(msg.sender, brrAvailableAtTGE);

            seedRoundSchedules[msg.sender].amountUnlockedAtTGE = 0;
        }

        emit SeedRoundBrrUnlocked(msg.sender, brrAvailableAtTGE);
    }

    function unlockSbrr(MemberType memberType) public override {
        uint256 releasableBRR = _unlockSbrr(msg.sender, memberType);

        VestingSchedule storage schedule;

        if (memberType == MemberType.TEAM) {
            schedule = teamsSchedules[msg.sender];
        } else if (memberType == MemberType.MARKETING) {
            schedule = marketingSchedules[msg.sender];
        } else {
            schedule = seedRoundSchedules[msg.sender];
        }

        schedule.amountClaimed += uint128(releasableBRR);

        if (releasableBRR != 0) {
            //transfer sBrr to user
            sBrrToken.safeTransfer(msg.sender, releasableBRR);
        }

        emit SbrrUnlocked(msg.sender, releasableBRR);
    }

    function getSeedRoundSchedules(address user) external view override returns (VestingSchedule memory schedule) {
        return seedRoundSchedules[user];
    }

    function getTeamSchedules(address user) external view override returns (VestingSchedule memory schedule) {
        return teamsSchedules[user];
    }

    function getMarketSchedules(address user) external view override returns (VestingSchedule memory schedule) {
        return marketingSchedules[user];
    }

    /**
     * @notice Adds a team member to the vesting schedule.
     * @dev Adds a new team member and initializes their vesting schedule. The total amount allocated to the member
     * is limited by the remaining available tokens for the team. The function automatically stakes the allocated amount.
     * @param _member The address of the team member to add.
     * @param totalAmount The total amount of tokens to allocate to the team member.
     */
    function addTeamMember(address _member, uint128 totalAmount)
        public
        override
        validAddressAndAmount(_member, totalAmount)
        onlyOwner
    {
        if (totalTeamBRRAllocated + totalAmount > TEAM_TOTAL_BRR_AMOUNT) {
            totalAmount = TEAM_TOTAL_BRR_AMOUNT - totalTeamBRRAllocated;
        }

        if (totalAmount == 0) revert BRR_INVALID_AMOUNT();

        VestingSchedule memory userSchedule = teamsSchedules[_member];

        if (block.timestamp >= userSchedule.cliff + userSchedule.duration) {
            unlockSbrr(MemberType.TEAM);
            teamsSchedules[_member].memberType = MemberType.TEAM;
            teamsSchedules[_member].start = uint32(block.timestamp);
            teamsSchedules[_member].cliff = uint32(block.timestamp) + TEAM_VESTING_CLIFF;
            teamsSchedules[_member].duration = TEAM_VESTING_DURATION;
            teamsSchedules[_member].amountClaimed = 0;
            teamsSchedules[_member].totalAmount = totalAmount;
        } else {
            teamsSchedules[_member].totalAmount += totalAmount;
        }

        totalTeamBRRAllocated += totalAmount;

        emit TeamMemberAdded(_member, totalAmount);
    }

    /**
     * @notice Adds a marketing member to the vesting schedule.
     * @dev Adds a new marketing member and initializes their vesting schedule. The total amount allocated to the member
     * is limited by the remaining available tokens for the marketing team. The function automatically stakes the allocated amount.
     * @param _member The address of the marketing member to add.
     * @param totalAmount The total amount of tokens to allocate to the marketing member.
     */
    function addMarketingMember(address _member, uint128 totalAmount)
        public
        override
        validAddressAndAmount(_member, totalAmount)
        onlyOwner
    {
        if (totalMarketingBRRAllocated + totalAmount > MARKETING_TOTAL_BRR_AMOUNT) {
            totalAmount = MARKETING_TOTAL_BRR_AMOUNT - totalMarketingBRRAllocated;
        }

        if (totalAmount == 0) revert BRR_INVALID_AMOUNT();

        if (block.timestamp >= marketingSchedules[_member].start + marketingSchedules[_member].duration) {
            //unlock existing brr from existing allocation.
            unlockSbrr(MemberType.MARKETING);

            marketingSchedules[_member].memberType = MemberType.MARKETING;
            marketingSchedules[_member].start = uint32(block.timestamp);
            marketingSchedules[_member].duration = MARKETING_VESTING_DURATION;
            marketingSchedules[_member].amountClaimed = 0;
            marketingSchedules[_member].totalAmount = totalAmount;
        } else {
            marketingSchedules[_member].totalAmount += totalAmount;
        }

        totalMarketingBRRAllocated += totalAmount;

        emit MarketingMemberAdded(_member, totalAmount);
    }

    /**
     * @notice Adds a seed round member to the vesting schedule.
     * @dev Adds a new seed round member and initializes their vesting schedule. The total amount allocated to the member
     * is limited by the remaining available tokens for the seed round. The function automatically stakes the allocated amount.
     * @param _member The address of the seed round member to add.
     * @param totalAmount The total amount of tokens to allocate to the seed round member.
     */
    function addSeedRoundMember(address _member, uint128 totalAmount)
        public
        override
        validAddressAndAmount(_member, totalAmount)
        onlyOwner
    {
        if (totalSeedRoundBRRAllocated + totalAmount > SEED_ROUND_TOTAL_BRR_AMOUNT) {
            totalAmount = SEED_ROUND_TOTAL_BRR_AMOUNT - totalSeedRoundBRRAllocated;
        }

        if (totalAmount == 0) revert BRR_INVALID_AMOUNT();

        /**
         * @notice Describes the vesting schedule for allocated BRR tokens.
         * @dev The vesting schedule consists of two parts:
         *      1. 30% of the total allocated amount is immediately available for use.
         *      2. The remaining 70% of the total allocated amount is vested linearly over a period of 6 months.
         *
         * Example:
         * - If Alice is allocated 10,000 BRR tokens:
         *   - 30% of 10,000 BRR (3,000 BRR) is immediately available upon allocation.
         *   - 70% of 10,000 BRR (7,000 BRR) is vested linearly over 6 months.
         *
         * This means that Alice can access 3,000 BRR tokens right away, and the remaining 7,000 BRR tokens
         *       will become available gradually over the next 6 months.
         */
        uint256 amountUnlocked = uint256(totalAmount).mulDiv(SEED_ROUND_BPS, TOTAL_BPS, Math.Rounding.Floor);

        uint128 amountToLock = totalAmount - uint128(amountUnlocked);

        if (block.timestamp >= seedRoundSchedules[_member].start + seedRoundSchedules[_member].duration) {
            unlockSbrr(MemberType.SEED_ROUND);
            seedRoundSchedules[_member].memberType = MemberType.SEED_ROUND;
            seedRoundSchedules[_member].start = uint32(block.timestamp);
            seedRoundSchedules[_member].duration = SEED_ROUND_VESTING_DURATION;
            seedRoundSchedules[_member].amountClaimed = 0;
            seedRoundSchedules[_member].totalAmount = amountToLock;
            seedRoundSchedules[_member].amountUnlockedAtTGE = uint256(amountUnlocked);
        } else {
            seedRoundSchedules[_member].totalAmount += amountToLock;
        }

        totalSeedRoundBRRAllocated += totalAmount;

        emit SeedRoundMemberAdded(_member, amountToLock);
    }

    /**
     * @notice Calculates the amount of unlocked BRR tokens in a given vesting schedule.
     * @param member the address of the member
     * @param memberType either TEAM, MARKETING or SEED ROUND.
     * @return unlocked The amount of unlocked BRR tokens.
     */
    function unlockedAmount(address member, MemberType memberType) public view override returns (uint256 unlocked) {
        VestingSchedule memory schedule = getSchedule(member, memberType);

        if (schedule.totalAmount == 0 || block.timestamp < schedule.cliff) {
            return 0;
        }

        uint256 vested = vestedAmount(member, memberType);
        unlocked = vested - schedule.amountClaimed;
    }

    /**
     * @notice Calculates the amount of vested BRR tokens in a given vesting schedule.
     * @param member the address of the member
     * @param memberType either TEAM, MARKETING or SEED ROUND.
     * @return The amount of vested BRR tokens.
     */
    function vestedAmount(address member, MemberType memberType) public view override returns (uint256) {
        VestingSchedule memory schedule = getSchedule(member, memberType);

        uint32 vestStart = schedule.cliff > 0 ? schedule.cliff : schedule.start;

        if (block.timestamp < vestStart) {
            return 0;
        } else if (block.timestamp >= vestStart + schedule.duration) {
            return schedule.totalAmount;
        } else {
            uint256 durationPassed = block.timestamp - vestStart;

            uint256 totalVested =
                uint256(schedule.totalAmount).mulDiv(durationPassed, schedule.duration, Math.Rounding.Floor);

            return totalVested;
        }
    }

    /**
     * @notice Internal function to unlock releasable BRR tokens based on the vesting schedule.
     * @dev Calculates the releasable BRR tokens and updates the vesting schedule.
     * Claims and un-stakes the unlocked BRR tokens from the staking contract.
     * @param member the address of the member
     * @param memberType either TEAM, MARKETING or SEED ROUND.
     * @return releasableSbRR The amount of BRR tokens that were unlocked.
     */
    function _unlockSbrr(address member, MemberType memberType) internal view returns (uint256 releasableSbRR) {
        releasableSbRR = unlockedAmount(member, memberType);
    }

    function _autoStake(uint256 totalAmount) internal {
        //auto stake
        brrToken.approve(address(beraStaking), totalAmount);
        beraStaking.stake(totalAmount, address(this));
    }

    function getSchedule(address member, MemberType memberType)
        internal
        view
        returns (VestingSchedule memory schedule)
    {
        if (memberType == MemberType.TEAM) {
            schedule = teamsSchedules[member];
        } else if (memberType == MemberType.MARKETING) {
            schedule = marketingSchedules[member];
        } else {
            schedule = seedRoundSchedules[member];
        }
    }

    function retrieve(address token, uint256 amount) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance != 0) {
            (bool success,) = payable(msg.sender).call{ value: balance }("");
            if (!success) revert BRR_TRANSFER_FAILED();
        }

        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
