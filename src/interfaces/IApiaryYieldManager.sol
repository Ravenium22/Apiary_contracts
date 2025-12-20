// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IApiaryYieldManager
 * @notice Interface for Apiary Yield Manager contract
 */
interface IApiaryYieldManager {
    /*//////////////////////////////////////////////////////////////
                            TYPE DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    enum Strategy {
        PHASE1_LP_BURN, // 25% HONEY, 25% burn, 50% LP+stake
        PHASE2_CONDITIONAL, // MC/TV based distribution
        PHASE3_VBGT // vBGT accumulation
    }

    struct SplitConfig {
        uint256 toHoney; // % swapped to HONEY
        uint256 toApiaryLP; // % swapped to APIARY for LP
        uint256 toBurn; // % swapped to APIARY and burned
        uint256 toStakers; // % distributed to stakers (Phase 2+)
        uint256 toCompound; // % kept as iBGT compound (Phase 2+)
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event YieldExecuted(
        Strategy indexed strategy,
        uint256 totalYield,
        uint256 honeySwapped,
        uint256 apiaryBurned,
        uint256 lpCreated,
        uint256 compounded
    );

    event StrategyChanged(Strategy indexed oldStrategy, Strategy indexed newStrategy);

    event SplitConfigUpdated(
        uint256 toHoney, uint256 toApiaryLP, uint256 toBurn, uint256 toStakers, uint256 toCompound
    );

    event AdapterUpdated(string indexed adapterType, address indexed oldAdapter, address indexed newAdapter);

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);

    event EmergencyModeToggled(bool enabled);

    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed recipient);

    event PartialExecutionFailure(string reason, uint256 failedAmount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error APIARY__ZERO_ADDRESS();
    error APIARY__INVALID_SPLIT_CONFIG();
    error APIARY__INSUFFICIENT_YIELD();
    error APIARY__EXECUTION_AMOUNT_TOO_HIGH();
    error APIARY__SLIPPAGE_TOO_HIGH();
    error APIARY__NO_PENDING_YIELD();
    error APIARY__SWAP_FAILED(string reason);
    error APIARY__LP_CREATION_FAILED();
    error APIARY__BURN_FAILED();
    error APIARY__EMERGENCY_MODE_ACTIVE();
    error APIARY__ADAPTER_NOT_SET();

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute yield strategy
     * @return totalYield Total yield processed
     * @return honeySwapped Amount swapped to HONEY
     * @return apiaryBurned Amount of APIARY burned
     * @return lpCreated Amount of LP tokens created
     * @return compounded Amount kept as iBGT
     */
    function executeYield()
        external
        returns (uint256 totalYield, uint256 honeySwapped, uint256 apiaryBurned, uint256 lpCreated, uint256 compounded);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pendingYield() external view returns (uint256 pendingAmount);

    function getSplitPercentages() external view returns (SplitConfig memory);

    function canExecuteYield() external view returns (bool canExecute, uint256 pending);

    function getStatistics()
        external
        view
        returns (
            uint256 totalYieldProcessed,
            uint256 totalApiaryBurned,
            uint256 totalLPCreated,
            uint256 lastExecutionTime,
            uint256 lastExecutionBlock
        );

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setStrategy(Strategy _strategy) external;

    function setSplitPercentages(
        uint256 toHoney,
        uint256 toApiaryLP,
        uint256 toBurn,
        uint256 toStakers,
        uint256 toCompound
    ) external;

    function setSlippageTolerance(uint256 _slippage) external;

    function setTreasury(address _treasury) external;

    function setInfraredAdapter(address _adapter) external;

    function setKodiakAdapter(address _adapter) external;

    function setStakingContract(address _staking) external;

    function setMinYieldAmount(uint256 _minAmount) external;

    function setMaxExecutionAmount(uint256 _maxAmount) external;

    function setMCThresholdMultiplier(uint256 _multiplier) external;

    function setEmergencyMode(bool _enabled) external;

    function pause() external;

    function unpause() external;

    function emergencyWithdraw(address token, uint256 amount, address recipient) external;
}
