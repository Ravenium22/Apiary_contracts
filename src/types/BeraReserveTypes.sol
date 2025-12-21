// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title BeraReserveTypes
 * @notice Shared type definitions for Apiary Protocol
 */

/// @notice Pre-sale bond state machine
enum PreSaleBondState {
    NotStarted,  // Initial state, purchases not allowed
    Live,        // Pre-sale active, whitelisted users can purchase
    Ended        // Pre-sale concluded, no further purchases
}

/// @notice Investor bond information for pre-sale vesting
struct InvestorBondInfo {
    uint128 totalAmount;      // Total APIARY allocated to investor
    uint128 unlockedAmount;   // Amount already claimed/unlocked
    uint48 duration;          // Vesting duration in seconds
}
