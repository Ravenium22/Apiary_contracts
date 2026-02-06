// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title VaultOwned
 * @notice Extends Ownable2Step with vault, staking, and lockup address management
 * @dev Provides modifiers for restricted access to vault, lockup, and staking contracts
 */
contract VaultOwned is Ownable2Step {
    address internal _vault;
    address internal _staking;
    address internal _lockUp;

    // L-06 Fix: Pending addresses for two-step confirmation
    address public pendingVault;
    address public pendingStaking;
    address public pendingLockUp;

    // M-03 Fix: Add events for address changes
    event VaultSet(address indexed vault);
    event StakingSet(address indexed staking);
    event LockUpSet(address indexed lockUp);

    // M-NEW-01 Fix: Error for zero address validation
    error VAULT_OWNED__ZERO_ADDRESS();
    // L-06 Fix: Error for unauthorized acceptance
    error VAULT_OWNED__NOT_PENDING();
    // LOW-02 Fix: Custom errors for modifiers (gas-efficient, consistent with codebase)
    error VAULT_OWNED__NOT_VAULT_OR_LOCKUP();
    error VAULT_OWNED__NOT_STAKING();

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    // L-06 Fix: Two-step pattern for vault
    function setVault(address vault_) external onlyOwner returns (bool) {
        if (vault_ == address(0)) revert VAULT_OWNED__ZERO_ADDRESS();
        pendingVault = vault_;
        return true;
    }

    function acceptVault() external {
        if (msg.sender != pendingVault) revert VAULT_OWNED__NOT_PENDING();
        _vault = pendingVault;
        pendingVault = address(0);
        emit VaultSet(_vault);
    }

    // L-06 Fix: Two-step pattern for lockUp
    function setLockUp(address lockUp_) external onlyOwner returns (bool) {
        if (lockUp_ == address(0)) revert VAULT_OWNED__ZERO_ADDRESS();
        pendingLockUp = lockUp_;
        return true;
    }

    function acceptLockUp() external {
        if (msg.sender != pendingLockUp) revert VAULT_OWNED__NOT_PENDING();
        _lockUp = pendingLockUp;
        pendingLockUp = address(0);
        emit LockUpSet(_lockUp);
    }

    // L-06 Fix: Two-step pattern for staking
    function setStaking(address staking_) external onlyOwner returns (bool) {
        if (staking_ == address(0)) revert VAULT_OWNED__ZERO_ADDRESS();
        pendingStaking = staking_;
        return true;
    }

    function acceptStaking() external {
        if (msg.sender != pendingStaking) revert VAULT_OWNED__NOT_PENDING();
        _staking = pendingStaking;
        pendingStaking = address(0);
        emit StakingSet(_staking);
    }

    function vault() public view returns (address) {
        return _vault;
    }

    function staking() public view returns (address) {
        return _staking;
    }

    function lockUp() public view returns (address) {
        return _lockUp;
    }

    // LOW-02 Fix: Use custom errors instead of require strings
    modifier onlyVaultOrLockUp() {
        if (_vault != msg.sender && _lockUp != msg.sender) revert VAULT_OWNED__NOT_VAULT_OR_LOCKUP();
        _;
    }

    modifier onlyStaking() {
        if (_staking != msg.sender) revert VAULT_OWNED__NOT_STAKING();
        _;
    }
}
