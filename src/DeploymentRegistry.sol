// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title DeploymentRegistry
 * @notice Registry contract to store all deployed Apiary protocol addresses
 * @dev Can be deployed after main deployment for easy address lookup
 * 
 * Usage:
 *   forge script script/deployment/DeployRegistry.s.sol:DeployRegistry \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeploymentRegistry {
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    // Core tokens
    address public immutable APIARY;
    address public immutable sAPIARY;
    
    // Staking
    address public immutable STAKING;
    address public immutable WARMUP;
    
    // Treasury
    address public immutable TREASURY;
    
    // Bonds
    address public immutable IBGT_BOND;
    address public immutable LP_BOND;
    address public immutable PRESALE_BOND;
    address public immutable TWAP_ORACLE;
    
    // Yield Management
    address public immutable YIELD_MANAGER;
    address public immutable INFRARED_ADAPTER;
    address public immutable KODIAK_ADAPTER;
    
    // External dependencies
    address public immutable IBGT;
    address public immutable HONEY;
    address public immutable APIARY_HONEY_LP;
    address public immutable INFRARED_STAKING;
    address public immutable KODIAK_ROUTER;
    address public immutable KODIAK_FACTORY;
    
    // Governance
    address public immutable MULTISIG;
    address public immutable DAO;
    
    // Metadata
    uint256 public immutable DEPLOYMENT_BLOCK;
    uint256 public immutable DEPLOYMENT_TIMESTAMP;
    uint256 public immutable CHAIN_ID;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event DeploymentRegistered(
        uint256 indexed chainId,
        uint256 indexed blockNumber,
        uint256 timestamp
    );
    
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _apiary,
        address _sApiary,
        address _staking,
        address _warmup,
        address _treasury,
        address _ibgtBond,
        address _lpBond,
        address _preSaleBond,
        address _twapOracle,
        address _yieldManager,
        address _infraredAdapter,
        address _kodiakAdapter,
        address _ibgt,
        address _honey,
        address _apiaryHoneyLP,
        address _infraredStaking,
        address _kodiakRouter,
        address _kodiakFactory,
        address _multisig,
        address _dao
    ) {
        APIARY = _apiary;
        sAPIARY = _sApiary;
        STAKING = _staking;
        WARMUP = _warmup;
        TREASURY = _treasury;
        IBGT_BOND = _ibgtBond;
        LP_BOND = _lpBond;
        PRESALE_BOND = _preSaleBond;
        TWAP_ORACLE = _twapOracle;
        YIELD_MANAGER = _yieldManager;
        INFRARED_ADAPTER = _infraredAdapter;
        KODIAK_ADAPTER = _kodiakAdapter;
        IBGT = _ibgt;
        HONEY = _honey;
        APIARY_HONEY_LP = _apiaryHoneyLP;
        INFRARED_STAKING = _infraredStaking;
        KODIAK_ROUTER = _kodiakRouter;
        KODIAK_FACTORY = _kodiakFactory;
        MULTISIG = _multisig;
        DAO = _dao;
        
        DEPLOYMENT_BLOCK = block.number;
        DEPLOYMENT_TIMESTAMP = block.timestamp;
        CHAIN_ID = block.chainid;
        
        emit DeploymentRegistered(block.chainid, block.number, block.timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get all core protocol addresses
     * @return Array of [APIARY, sAPIARY, STAKING, WARMUP, TREASURY]
     */
    function getCoreAddresses() external view returns (address[5] memory) {
        return [APIARY, sAPIARY, STAKING, WARMUP, TREASURY];
    }
    
    /**
     * @notice Get all bond-related addresses
     * @return Array of [IBGT_BOND, LP_BOND, PRESALE_BOND, TWAP_ORACLE]
     */
    function getBondAddresses() external view returns (address[4] memory) {
        return [IBGT_BOND, LP_BOND, PRESALE_BOND, TWAP_ORACLE];
    }
    
    /**
     * @notice Get all yield management addresses
     * @return Array of [YIELD_MANAGER, INFRARED_ADAPTER, KODIAK_ADAPTER]
     */
    function getYieldAddresses() external view returns (address[3] memory) {
        return [YIELD_MANAGER, INFRARED_ADAPTER, KODIAK_ADAPTER];
    }
    
    /**
     * @notice Get all external dependency addresses
     * @return Array of [IBGT, HONEY, APIARY_HONEY_LP, INFRARED_STAKING, KODIAK_ROUTER, KODIAK_FACTORY]
     */
    function getExternalAddresses() external view returns (address[6] memory) {
        return [IBGT, HONEY, APIARY_HONEY_LP, INFRARED_STAKING, KODIAK_ROUTER, KODIAK_FACTORY];
    }
    
    /**
     * @notice Get governance addresses
     * @return Array of [MULTISIG, DAO]
     */
    function getGovernanceAddresses() external view returns (address[2] memory) {
        return [MULTISIG, DAO];
    }
    
    /**
     * @notice Get deployment metadata
     * @return block Block number of deployment
     * @return timestamp Timestamp of deployment
     * @return chainId Chain ID of deployment
     */
    function getDeploymentMetadata() external view returns (uint256 block, uint256 timestamp, uint256 chainId) {
        return (DEPLOYMENT_BLOCK, DEPLOYMENT_TIMESTAMP, CHAIN_ID);
    }
}
