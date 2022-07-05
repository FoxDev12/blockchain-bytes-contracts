// SPDX-License-Identifier: MIT
// This is the ERC1155 contract that handles the upgrades.
pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/ERC1155Pausable.sol";
import "./deps/interfaces/IERC20.sol";


contract Upgrade is Ownable, ERC1155Pausable {
    IERC20 dough;

    mapping(uint256 => uint256) public mintPrices;

    mapping(uint256 => uint256) public doughRate;
    mapping(uint256 => uint256) public currentSupply;
    mapping(uint256 => uint256) public maxSupply;

    constructor() ERC1155("testURI/{id}.json") {
        mintPrices[1] = 5 ether;
        mintPrices[2] = 10 ether;
        mintPrices[3] = 50 ether;
        maxSupply[1] = 1000;
        maxSupply[2] = 500;
        maxSupply[3] = 300;
        doughRate[1] = 1 ;
        doughRate[2] = 2;
        doughRate[3] = 4;
    }

    function getRate(uint256 itemId) external view returns (uint256) {
        return doughRate[itemId];
    }

    function setCtr(address _dough) external onlyOwner {
        dough = IERC20(_dough);
    }

    function mint(uint256 id, uint256 amount) external {
        require(id > 0, "Cannot mint id 0");
        require(currentSupply[id] + amount <=  maxSupply[id], "All minted");
        uint256 total = mintPrices[id] * amount;

        uint256 approv = dough.allowance(msg.sender, address(this));

        require( approv>= total, "Insufficient Allowance");

        dough.transferFrom(msg.sender, address(this), total);
        currentSupply[id] += amount;
        _mint(msg.sender, id, amount, "");
    }
}
