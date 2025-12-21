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

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function setVault(address vault_) external onlyOwner returns (bool) {
        _vault = vault_;
        return true;
    }

    function setLockUp(address lockUp_) external onlyOwner returns (bool) {
        _lockUp = lockUp_;
        return true;
    }

    function setStaking(address staking_) external onlyOwner returns (bool) {
        _staking = staking_;
        return true;
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

    modifier onlyVaultOrLockUp() {
        require((_vault == msg.sender || _lockUp == msg.sender), "VaultOwned: caller is not the Vault or LockUp");
        _;
    }

    modifier onlyStaking() {
        require(_staking == msg.sender, "VaultOwned: caller is not the Staking");
        _;
    }
}
