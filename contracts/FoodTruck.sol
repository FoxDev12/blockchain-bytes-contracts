// This is the main staking contract, its where you stake chefs to generate dough. It can be upgraded with ERC1155s 

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/interfaces/IERC721.sol";
import "./deps/interfaces/IERC721Receiver.sol";
import "./deps/interfaces/IERC1155Receiver.sol";
import "./deps/interfaces/IERC1155.sol";
import "./deps/Ownable.sol";
import "./deps/interfaces/IERC20.sol";


 interface IChef is IERC721 {
    function isTiki(uint256 tokenId) external view returns (bool);
}

interface IUpgrade is IERC1155 {
    function getRate(uint256 tokenId) external view returns (uint256);
}

interface IDough is IERC20 {
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}


/** @dev FoodTruck is an NFT staking contract
 *       map each NFT to fungible staking impact
 *
 */
contract FoodTruck is Ownable, IERC721Receiver, IERC1155Receiver {
    mapping(uint256 => uint256) stakeTimes;
    mapping(uint256 => address) prevOwner;
    mapping(uint256 => bool) receivesRewards;
    IDough dough;
    IChef chefs;
    IDough pza;
    IUpgrade upgrades;
    address fermenter;

    mapping(uint256 => mapping(address => uint256)) itemBalance;

    mapping(uint256 => uint256) public unlockTime;

    mapping(address => uint256[]) public chefIds;

    mapping(address => uint256) public walletLimit;     //implicit: x + 20
    mapping(address => uint256) public collFeeReduce;   //implicit: 25% - x treasury, 40% - x total

    uint256[] public priceWalletUpgrade = [20 ether, 20 ether, 20 ether];
    uint256[] public walletUpgradeTier = [1, 5, 10];
    uint256 public priceCollectionUpgrade = 2 ether;
    uint256 earlyUnstakeFee;
    uint256 constant cooldown = 1 days;

    constructor(
        address _chefs,
        address _upgrades,
        address _dough
    ) {
        chefs = IChef(_chefs);
        upgrades = IUpgrade(_upgrades);
        dough = IDough(_dough);
    }

    
    struct StakeInfo {
        uint256 lastUpdate;
        uint256 totalRate;
        uint256 claimable;
        uint256 slots;
        uint256 nrItems;
        uint256 nrChefs;
    }

    mapping(address => StakeInfo) public stakeMap;


    function setFermenter(address _fermenter) external onlyOwner {
        fermenter = _fermenter;
    } 

    function setPizza(address _pza) external onlyOwner {
        // Not confusing at all lol
        pza = IDough(_pza);
    }   
    // -------------------------------------EXTERNAL - BASIC  -------------------------------------------------
    function stake(uint256 tokenId) external {
        require(stakeMap[msg.sender].nrChefs < walletLimit[msg.sender] + 20, "!limit");
        chefs.safeTransferFrom(msg.sender, address(this), tokenId );
        _updateStake(msg.sender);
        StakeInfo storage refUser = stakeMap[msg.sender];
        refUser.nrChefs += 1;
        refUser.totalRate += chefs.isTiki(tokenId) ? 2 ether : 1 ether;
        refUser.slots += chefs.isTiki(tokenId)? 2 : 1;

        chefIds[msg.sender].push(tokenId);
        prevOwner[tokenId] = msg.sender;
        unlockTime[tokenId] = type(uint256).max;
    }
    // Done : Added unstake w no cooldown
    function prepareUnstake(uint256 tokenId, bool isCooldown) external {
        require(prevOwner[tokenId] == msg.sender, "Not your token");
        uint256 deltaslots = chefs.isTiki(tokenId) ? 2 : 1;
        _updateStake(msg.sender);
        StakeInfo storage refUser = stakeMap[msg.sender];
        require(
            refUser.slots - deltaslots >= refUser.nrItems,
            "Cannot unstake Chef with that many items equiped. Unequip items first."
        );
        refUser.nrChefs -= 1;
        refUser.slots -= deltaslots;
        refUser.totalRate -= deltaslots * 1 ether;
        if(isCooldown) {
        unlockTime[tokenId] = block.timestamp + cooldown;
        }
        else{
            chefs.safeTransferFrom(address(this), msg.sender, tokenId);
            // Implemented burnFrom for PZA and DOUGH
            pza.burnFrom(msg.sender, earlyUnstakeFee);
            // pza.transferFrom(msg.sender, address(this), earlyUnstakeFee);
            // pza.burn(earlyUnstakeFee);
            uint256 matchIndex = type(uint256).max;
            uint256 lenny = chefIds[msg.sender].length;
            for(uint256 index = 0; index < lenny; index++) {
                if (chefIds[msg.sender][index] == tokenId) {
                    matchIndex = index;
                }
            }
            require(matchIndex < lenny, "This should never happen, tell the dev");
            chefIds[msg.sender][matchIndex] = chefIds[msg.sender][lenny - 1];
            chefIds[msg.sender].pop();
            prevOwner[tokenId] = address(0);
            }  
        }

    function unstake(uint256 tokenId) external {
        require(prevOwner[tokenId] == msg.sender, "Not your token");
        require(block.timestamp >= unlockTime[tokenId], "Still in cooldown");
        chefs.safeTransferFrom(address(this), msg.sender, tokenId);
        uint256 matchIndex = type(uint256).max;
        uint256 lenny = chefIds[msg.sender].length;
        for(uint256 index = 0; index < lenny; index++) {
            if (chefIds[msg.sender][index] == tokenId) {
                matchIndex = index;
            }
        }
        require(matchIndex < lenny, "This should never happen, tell the dev");
        chefIds[msg.sender][matchIndex] = chefIds[msg.sender][lenny - 1];
        chefIds[msg.sender].pop();
        prevOwner[tokenId] = address(0);
    }

    function withdraw() public {
        _updateStake(msg.sender);
        uint256 reward = stakeMap[msg.sender].claimable;
        stakeMap[msg.sender].claimable = 0;
        uint256 feefermenter = reward * 15 / 100;
        uint256 feeburn = reward * (25 - collFeeReduce[msg.sender]) / 100;
        uint256 payout = reward - feefermenter - feeburn;
        // implicit burn
        dough.mint(fermenter, feefermenter);
        dough.mint(msg.sender, payout);
    }

    // -------------------------------------EXTERNAL - UPGRADES -------------------------------------------------
    //DONE : offer 1, 5, 10
    function increaseChefLimit(uint256 tier) external {
        // Unnecessary checks
        // uint256 approv = pza.allowance(msg.sender, address(this));
        // require( approv >= priceWalletUpgrade, "Insufficient Allowance");
        require(tier < 2, "!tier");
        pza.transferFrom(msg.sender, address(this), priceWalletUpgrade[tier]);
        walletLimit[msg.sender] += walletUpgradeTier[tier];
    }
    // todo tiers too?
    function reduceCollectionFee() external {
        // uint256 approv = pza.allowance(msg.sender, address(this));
        // require( approv >= priceCollectionUpgrade, "Insufficient Allowance");
        pza.transferFrom(msg.sender, address(this), priceCollectionUpgrade);
        collFeeReduce[msg.sender] += 5;
    }
    function equipItem(uint256 itemId) external {
        _updateStake(msg.sender);
        StakeInfo storage refUser = stakeMap[msg.sender];
        require(
            refUser.nrItems + 1 <= refUser.slots,
            "All slots full"
        );
        refUser.nrItems += 1;
        refUser.totalRate += upgrades.getRate(itemId);
        itemBalance[itemId][msg.sender] += 1;
        upgrades.safeTransferFrom(msg.sender, address(this), itemId, 1, "");
    }

    function removeItem(uint256 itemId) external {
        require(itemBalance[itemId][msg.sender] > 0, "Item not equipped");

        _updateStake(msg.sender);
        StakeInfo storage refUser = stakeMap[msg.sender];
        refUser.nrItems -= 1;
        refUser.totalRate -= upgrades.getRate(itemId);
        itemBalance[itemId][msg.sender] -= 1;
        
        upgrades.safeTransferFrom(address(this), msg.sender, itemId, 1, "");
    }
    // -------------------------------------- INTERNAL ---------------------------------------
    function _updateStake(address user) private {
        StakeInfo storage refUser = stakeMap[user];
        uint256 lastTime = refUser.lastUpdate;
        uint256 totalReward = refUser.totalRate * (block.timestamp - lastTime) / 1 minutes;
        refUser.claimable += totalReward;
        refUser.lastUpdate = block.timestamp;
    }



    // ------------------------------------ VIEW -----------------------------------------
    struct ChefInfo {
        uint256 tokenId;
        uint256 unlockTime;
    }
    // DONE address param instead of msg.sender in view functions
    function getChefs(address user) external view returns (ChefInfo[] memory) {
        ChefInfo[] memory result = new ChefInfo[](chefIds[user].length);
        for(uint256 index = 0; index < chefIds[user].length; index++) {
            uint256 tokid = chefIds[user][index];
            result[index] = ChefInfo({tokenId: tokid, unlockTime: unlockTime[tokid]});
        }
        return result;
    }


    function getCollectionFee(address user) public view returns (uint256) {
        return 40 - collFeeReduce[user];
    }

    function getWalletLimit(address user) public view returns (uint256) {
        return walletLimit[user] + 20;
    }

    function getReward(address user) public view returns (uint256) {
        uint256 lastTime = stakeMap[user].lastUpdate;
        uint256 totalReward = stakeMap[user].totalRate * (block.timestamp - lastTime) / 1 minutes;
        return stakeMap[user].claimable + totalReward;
    }

    function getSlots(address user) public view returns (uint256) {
        return stakeMap[user].slots;
    }

    function getUserRate(address user) public view returns (uint256) {
        return stakeMap[user].totalRate;
    }

    function getNrItems(address user) public view returns (uint256) {
        return stakeMap[user].nrItems;
    }

    function getItemBalance(uint256 itemId, address user) public view returns (uint256) {
        return itemBalance[itemId][user];
    }


    // ------------------------------------------------- SPECS REQUIREMENTS -------------------------------------------------------------------------
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
// A bit hacky
    function supportsInterface(bytes4 interfaceID)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}


