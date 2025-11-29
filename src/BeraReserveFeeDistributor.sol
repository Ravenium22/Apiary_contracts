// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBeraReserveFeeDistributor } from "./interfaces/IBeraReserveFeeDistributor.sol";

contract BeraReserveFeeDistributor is IBeraReserveFeeDistributor, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    using SafeERC20 for IERC20;

    uint16 public constant BPS_DIVISOR = 10_000;
    IERC20 public beraReserveToken;

    address public treasury;
    address public pol;
    address public team;

    uint256 public accumulatedBeraReserveTokenPerContract;
    uint256 public lastBalance;
    uint48 public lastUpdatedTimestamp;
    uint16 public teamShare = 3_300; // 33%
    uint16 public polShare = 3_300; // 33%
    uint16 public treasuryShare = 3_400; // 34%

    mapping(address => int256) public shareDebt;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeDistributed(uint256 indexed toTeam, uint256 indexed toPOL, uint256 indexed toTreasury);
    event AddressesUpdated(address indexed team, address indexed poL, address indexed treasury);
    event SharesUpdated(uint16 indexed teamShare, uint16 indexed polShare, uint16 indexed treasuryShare);
    event TreasuryAddressUpdated(address indexed previousTreasury, address indexed newTreasury);
    event TeamAddressUpdated(address indexed previousTeam, address indexed newTeam);
    event PolAddressUpdated(address indexed previousPol, address indexed newPol);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BERA_RESERVE__INVALID_ADDRESS();

    constructor(address admin, address _treasury, address _pol, address _team, address _beraReserveToken)
        Ownable(admin)
    {
        if (_treasury == address(0) || _pol == address(0) || _team == address(0) || _beraReserveToken == address(0)) {
            revert BERA_RESERVE__INVALID_ADDRESS();
        }

        treasury = _treasury;
        pol = _pol;
        team = _team;
        beraReserveToken = IERC20(_beraReserveToken);
    }

    function updateAllocations() public override {
        if (uint48(block.timestamp) > lastUpdatedTimestamp) {
            uint256 contractBalance = beraReserveToken.balanceOf(address(this));

            uint256 diff = contractBalance - lastBalance;

            if (diff != 0) {
                accumulatedBeraReserveTokenPerContract += diff / BPS_DIVISOR;
            }
            lastUpdatedTimestamp = uint48(block.timestamp);
        }
    }

    function _allocate(address _receiver, uint16 receiverShare) internal returns (uint256 pendingTypeBeraReserve) {
        updateAllocations();

        int256 accumulatedTypeBeraReserve = int256(receiverShare * accumulatedBeraReserveTokenPerContract);
        pendingTypeBeraReserve = uint256(accumulatedTypeBeraReserve - shareDebt[_receiver]);

        if (pendingTypeBeraReserve != 0) {
            shareDebt[_receiver] = accumulatedTypeBeraReserve;
            lastBalance = beraReserveToken.balanceOf(address(this)) - pendingTypeBeraReserve;

            beraReserveToken.safeTransfer(_receiver, pendingTypeBeraReserve);
        }
    }

    ///@dev allocate fees to team
    function allocateTeam() public override onlyOwner returns (uint256) {
        return _allocate(team, teamShare);
    }

    ///@dev allocate fees to pol
    function allocatePOL() public override onlyOwner returns (uint256) {
        return _allocate(pol, polShare);
    }

    ///@dev allocate fees to treasury
    function allocateTreasury() public override onlyOwner returns (uint256) {
        return _allocate(treasury, treasuryShare);
    }

    function allocateToAll() public override {
        updateAllocations();

        int256 accumulatedTeamBeraReserve = int256(teamShare * accumulatedBeraReserveTokenPerContract);
        uint256 pendingTeamBeraReserve = uint256(accumulatedTeamBeraReserve - shareDebt[team]);

        int256 accumulatedPolBeraReserve = int256(polShare * accumulatedBeraReserveTokenPerContract);
        uint256 pendingPolBeraReserve = uint256(accumulatedPolBeraReserve - shareDebt[pol]);

        int256 accumulatedTreasuryAccBeraReserve = int256(treasuryShare * accumulatedBeraReserveTokenPerContract);
        uint256 pendingTreasuryAccBeraReserve = uint256(accumulatedTreasuryAccBeraReserve - shareDebt[treasury]);

        if (pendingTeamBeraReserve != 0) {
            shareDebt[team] = accumulatedTeamBeraReserve;
            lastBalance = beraReserveToken.balanceOf(address(this)) - pendingTeamBeraReserve;

            beraReserveToken.safeTransfer(team, pendingTeamBeraReserve);
        }
        if (pendingPolBeraReserve != 0) {
            shareDebt[pol] = accumulatedPolBeraReserve;
            lastBalance = beraReserveToken.balanceOf(address(this)) - pendingPolBeraReserve;

            beraReserveToken.safeTransfer(pol, pendingPolBeraReserve);
        }
        if (pendingTreasuryAccBeraReserve != 0) {
            shareDebt[treasury] = accumulatedTreasuryAccBeraReserve;
            lastBalance = beraReserveToken.balanceOf(address(this)) - pendingTreasuryAccBeraReserve;

            beraReserveToken.safeTransfer(treasury, pendingTreasuryAccBeraReserve);
        }

        emit FeeDistributed(pendingTeamBeraReserve, pendingPolBeraReserve, pendingTreasuryAccBeraReserve);
    }

    function updateAddresses(address _team, address _pol, address _treasury) external override onlyOwner {
        if (_treasury != address(0)) {
            int256 treasuryShareDebt = shareDebt[treasury];

            address previousTreasury = treasury;

            treasury = _treasury;

            shareDebt[_treasury] = treasuryShareDebt;

            emit TreasuryAddressUpdated(previousTreasury, _treasury);
        }
        if (_team != address(0)) {
            int256 teamShareDebt = shareDebt[team];

            address previousTeam = team;

            team = _team;

            shareDebt[_team] = teamShareDebt;

            emit TeamAddressUpdated(previousTeam, _team);
        }
        if (_pol != address(0)) {
            int256 polShareDebt = shareDebt[pol];

            address previousPol = pol;

            pol = _pol;

            shareDebt[_pol] = polShareDebt;

            emit PolAddressUpdated(previousPol, _pol);
        }
    }

    function updateBeraReserveToken(address _beraReserveToken) external onlyOwner {
        require(_beraReserveToken != address(0), "BeraReserveFeeDistributor: Invalid BeraReserveToken");
        beraReserveToken = IERC20(_beraReserveToken);
    }

    function updateShares(uint16 _teamShare, uint16 _polShare, uint16 _treasuryShare) external override onlyOwner {
        require(_teamShare + _polShare + _treasuryShare == BPS_DIVISOR, "BeraReserveFeeDistributor: Invalid Shares");

        allocateToAll(); //essential to allocate to all in one timestamp before changing shares

        teamShare = _teamShare;

        shareDebt[team] = int256(_teamShare * accumulatedBeraReserveTokenPerContract);

        polShare = _polShare;
        shareDebt[pol] = int256(_polShare * accumulatedBeraReserveTokenPerContract);

        treasuryShare = _treasuryShare;
        shareDebt[treasury] = int256(_treasuryShare * accumulatedBeraReserveTokenPerContract);

        emit SharesUpdated(_teamShare, _polShare, _treasuryShare);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getShareDebt(address _contract) external view override returns (int256) {
        return shareDebt[_contract];
    }

    function getContractShares() external view override returns (uint16, uint16, uint16) {
        return (teamShare, polShare, treasuryShare);
    }

    function getContractAddresses() external view override returns (address, address, address) {
        return (team, pol, treasury);
    }

    function getLastBalance() external view override returns (uint256) {
        return lastBalance;
    }

    function getAccumulatedBeraReserveTokenPerContract() external view override returns (uint256) {
        return accumulatedBeraReserveTokenPerContract;
    }

    function getLastUpdatedTimestamp() external view override returns (uint48) {
        return lastUpdatedTimestamp;
    }
}
