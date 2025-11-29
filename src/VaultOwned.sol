// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IOwnable {
    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner_) external;
}

contract Ownable is IOwnable {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual override onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner_) public virtual override onlyOwner {
        require(newOwner_ != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner_);
        _owner = newOwner_;
    }
}

contract VaultOwned is Ownable {
    address internal _vault;
    address internal _staking;
    address internal _lockUp;

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
