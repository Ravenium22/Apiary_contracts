// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

enum MemberType {
    TEAM,
    MARKETING,
    SEED_ROUND
}

struct VestingSchedule {
    MemberType memberType;
    uint128 totalAmount;
    uint256 amountUnlockedAtTGE;
    uint128 amountClaimed;
    uint32 start;
    uint32 cliff;
    uint32 duration;
}

struct TreasuryValueData {
    uint256 fee; // Final fee to be charged
    uint256 treasuryPercentage; // Percentage of fee directed to treasury
    uint256 burnPercentage; // Percentage of fee to be burned
    bool isSliding; // Boolean to check if the fee is sliding or normal
}

enum PreSaleBondState {
    NotStarted,
    Live,
    Ended
}

struct InvestorBondInfo {
    uint128 totalAmount;
    uint128 unlockedAmount;
    uint48 start;
    uint48 duration;
}
