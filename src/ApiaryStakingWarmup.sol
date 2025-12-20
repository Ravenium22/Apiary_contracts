// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import { IERC20 as OZIERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApiaryStakingWarmup
 * @notice Holds sAPIARY tokens during the warmup period before stakers can claim
 * @dev Tokens are transferred here when users stake, and released after warmup completes
 */
contract ApiaryStakingWarmup {
    address public immutable staking;
    OZIERC20 public immutable sAPIARY;

    constructor(address _staking, address _sAPIARY) {
        require(_staking != address(0), "ApiaryStakingWarmup: _staking cannot be address(0)");
        staking = _staking;
        require(_sAPIARY != address(0), "ApiaryStakingWarmup: _sAPIARY cannot be address(0)");
        sAPIARY = OZIERC20(_sAPIARY);
    }

    /**
     * @notice Retrieves sAPIARY tokens for a staker after warmup period ends
     * @param _staker The address to receive the tokens
     * @param _amount The amount of sAPIARY to transfer
     * @dev Only callable by the staking contract
     */
    function retrieve(address _staker, uint256 _amount) external {
        require(msg.sender == staking, "ApiaryStakingWarmup: only staking");
        sAPIARY.transfer(_staker, _amount);
    }
}
