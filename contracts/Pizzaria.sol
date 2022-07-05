// Staking, PZA for more PZA, epoch based

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/interfaces/IERC20.sol";


interface IPZA is IERC20 {
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount) external;
}

contract Pizzaria is Ownable {

    uint256 constant EPOCHDUR = 6 hours;

    uint256 constant rewardPrecision = 10**18;

    uint256 constant fee = 5;

    struct MetaStake {
        uint256 lastIndex;
        uint256 claimable;
        uint256 staked;
    }

    struct DelayPayout {
        uint256 time;
        uint256 amount;
    }

    struct StakeSnapshot {
        uint256 time;
        uint256 perShare;
    }

    IPZA public token;
    address projectwallet;
    uint256 tvs;
    uint256 paidOut;
    uint256 accumReward;
    mapping(address => MetaStake) public stakeMap;
    StakeSnapshot[] public snapshots;

    mapping(address => DelayPayout) public delayed;

    constructor(address tokaddress, address _projectwallet) {
        token = IPZA(tokaddress);
        projectwallet = _projectwallet;
         StakeSnapshot memory snap = StakeSnapshot({
            time: block.timestamp,
            perShare: 0
        });
        snapshots.push(snap);
    }

// global Functions affecting the state of all users

    function getIndex() public view returns (uint256){
        return snapshots.length - 1;
    }

    function advanceEpoch() public {
        require(block.timestamp - snapshots[getIndex()].time >= EPOCHDUR, "Staker: Epoch has not passed");
        uint256 epochRewards = token.balanceOf(address(this)) + paidOut - tvs - accumReward;
        uint256 perShare = 0;
        if (tvs > 0) {
            //distribute epoch reward via shares
            accumReward += epochRewards;
            perShare = epochRewards * rewardPrecision / tvs + snapshots[getIndex()].perShare;
        } else {
            //forward epoch reward to next epoch
            perShare = snapshots[getIndex()].perShare;
        }
        StakeSnapshot memory snap = StakeSnapshot({
            time: block.timestamp,
            perShare: perShare
        });
        snapshots.push(snap);
    }

    modifier optionalAdvance() {
        if ( block.timestamp - snapshots[getIndex()].time >= EPOCHDUR ) {
            advanceEpoch();
        }
        _;
    }


// functions affecting individual users


    /**
    * @dev Must be called before updating staked value
    *
    */
    function _updateStake(address user) private {
        MetaStake storage refUser = stakeMap[user];
        uint256 lastIndex = refUser.lastIndex;
        uint256 rewardPer = snapshots[getIndex()].perShare - snapshots[lastIndex].perShare;
        uint256 totalReward = rewardPer * refUser.staked / rewardPrecision;
        refUser.claimable += totalReward;
        refUser.lastIndex = getIndex();
    }

    function stake(uint256 amount) optionalAdvance external {
        uint256 spendable = token.allowance(msg.sender, address(this));
        require(spendable >= amount, "Allowance insufficient");
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Staker: Token deposit reverted");
        _updateStake(msg.sender);
        uint256 tax = amount * fee / 1000;
        uint256 payto = amount - tax;
        stakeMap[msg.sender].staked += payto;
        tvs += payto;
        token.transfer(projectwallet, tax);
    }

    function withdraw() optionalAdvance external {
        _updateStake(msg.sender);
        uint256 amount = stakeMap[msg.sender].claimable;
        stakeMap[msg.sender].claimable = 0;
        uint256 tax = amount * fee / 1000;
        uint256 payto = amount - tax;
        paidOut += amount;
        token.transfer(projectwallet, tax);
        token.transfer(msg.sender, payto);
    }

    function unstakeNow(uint256 amount) optionalAdvance external {
        require(stakeMap[msg.sender].staked >= amount, "Staker: Insufficient Funds staked");
        _updateStake(msg.sender);
        stakeMap[msg.sender].staked -= amount;
        tvs -= amount;
        uint256 tax = amount * fee / 1000;
        uint256 payto = amount - tax;
        token.transfer(projectwallet, tax);
        token.transfer(msg.sender, payto);
    }

}