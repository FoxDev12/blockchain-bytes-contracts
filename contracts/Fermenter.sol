// This is a Dough => Dough staking contract, epoch based

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/interfaces/IERC20.sol";
// TODO  dont hardcode taxes
interface IDough is IERC20 {
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount) external;
}

contract Fermenter is Ownable {

    uint256 constant EPOCHDUR =  6 hours;

    uint256 constant rewardPrecision = 10**18;
    // Contains stake
    struct MetaStake {
        // Last time claimed
        uint256 lastIndex;
        // Total claimable (update?)
        uint256 claimable;
        // amount staked (not compounding)
        uint256 staked;
    }

    struct DelayPayout {
        // timestamp when unlocks
        uint256 time;
        // To  claim
        uint256 amount;
    }
    // Whole thing
    struct StakeSnapshot {
        // Timestamp   
        uint256 time;
        // to claim for 1 ether staked
        uint256 perShare;
    }
    // Ref dough
    IDough public token;
    // Total value staked
    uint256 public tvs;
    // Total rewards - claimed?
    uint256 paidOut;
    // Total rewards
    uint256 accumReward;

    mapping(address => MetaStake) public stakeMap;
   
    StakeSnapshot[] public snapshots;

    mapping(address => DelayPayout) public delayed;

    constructor(address tokaddress) {
        token = IDough(tokaddress);
         StakeSnapshot memory snap = StakeSnapshot({
            time: block.timestamp,
            perShare: 0
        });
        snapshots.push(snap);
    }

// global Functions affecting the state of all users
    // Last 
    function getIndex() public view returns (uint256){
        return snapshots.length - 1;
    }
    // Current end time
    function getEndTime() public view returns (uint256) {
        return snapshots[getIndex()].time + EPOCHDUR;
    }
    // Total staked for user
    function getStake(address user) public view returns (uint256) {
        return stakeMap[user].staked;
    }
    // Incentivize? 
    function advanceEpoch() public {
        // Check
        require(block.timestamp - snapshots[getIndex()].time >= EPOCHDUR, "Staker: Epoch has not passed");
        //  Full rewards
        uint256 epochRewards = token.balanceOf(address(this)) + paidOut - tvs - accumReward;
        uint256 perShare;
        
        if (tvs > 0) {
            //distribute epoch reward via shares
            accumReward += epochRewards;
            perShare = epochRewards * rewardPrecision / tvs + snapshots[getIndex()].perShare;
        } else {
            //forward epoch reward to next epoch
            perShare = snapshots[getIndex()].perShare /* + 0*/;
        }
        StakeSnapshot memory snap = StakeSnapshot({
            time: block.timestamp,
            perShare: perShare
        });
        snapshots.push(snap);
    }

    modifier optionalAdvance() {
        if ( block.timestamp - snapshots[getIndex()].time >= EPOCHDUR) {
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

    function getClaimable(address user) external view returns (uint256) {
        return stakeMap[user].claimable;
    }

    function getEstimate(address user) external view returns (uint256) {
        if (tvs > 0 && stakeMap[user].staked > 0) {
            uint256 epochRewards = token.balanceOf(address(this)) + paidOut - tvs - accumReward;
            return epochRewards * stakeMap[user].staked / tvs;
        } else {
            return 0;
        }
    }

    function stake(uint256 amount) optionalAdvance external {
        // uint256 spendable = token.allowance(msg.sender, address(this));
        // require(spendable >= amount, "Allowance insufficient");
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Staker: Token deposit reverted");
        _updateStake(msg.sender);
        stakeMap[msg.sender].staked += amount;
        tvs += amount;
    }

    function withdraw() optionalAdvance external {
        _updateStake(msg.sender);
        uint256 amount = stakeMap[msg.sender].claimable;
        stakeMap[msg.sender].claimable = 0;
        paidOut += amount;
        token.transfer(msg.sender, amount);
    }

    function unstakeNow(uint256 amount) optionalAdvance external {
        require(stakeMap[msg.sender].staked >= amount, "Staker: Insufficient Funds staked");
        _updateStake(msg.sender);
        stakeMap[msg.sender].staked -= amount;
        tvs -= amount;
        uint256 halfTax = amount * 375 / 1000;
        uint256 topay = amount - 2*halfTax;
        //implicit self deposit of halTax (through balance)
        token.burn(halfTax);
        token.transfer(msg.sender, topay);
    }

    function unstakeDelay(uint256 amount, uint256 lvl) optionalAdvance external {
        uint256[3] memory halfTaxRate = [uint256(250), uint256(125), uint256(0)];
        require(lvl <= 2, "Staker: Invalid Delay choice");
        require(stakeMap[msg.sender].staked >= amount, "Staker: Insufficient Funds staked");
        // TODO Should we allow mulitple delays? 
        require(delayed[msg.sender].amount == 0, "Staker: Time Delay Slot already full");
        _updateStake(msg.sender);
        // Stop earning on unstaked tokens
        stakeMap[msg.sender].staked -= amount;
        tvs -= amount;
        uint256 halfTax = amount * halfTaxRate[lvl] / 1000;
        uint256 topay = amount - 2*halfTax;
        //implicit self deposit of halTax (through balance)
        token.burn(halfTax);
        delayed[msg.sender].amount = topay;
        // 2, 4 or 6 days / 25, 12.5, 0 % Taxes
        delayed[msg.sender].time = block.timestamp + (1 days)*(lvl + 1);
        //token.transfer(msg.sender, topay);
    }

    function getDelayedAmount(address user) external view returns (uint256) {
        return delayed[user].amount;
    }

    function getDelayedTime(address user) external view returns (uint256) {
        return delayed[user].time;
    }

    function withdrawDelayed() external {
        uint256 amount = delayed[msg.sender].amount;
        require(amount > 0, "Fermenter: No delayed funds to withdraw");
        require(block.timestamp >= delayed[msg.sender].time, "Fermenter: Delay has not passed");
        delayed[msg.sender].amount = 0;
        token.transfer(msg.sender, amount);
    }
}