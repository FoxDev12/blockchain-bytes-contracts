// This contract turns Dough into PZA, can be upgraded with ERC1155s

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/interfaces/IERC20.sol";


interface IDough is IERC20 {
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount) external;
}

contract Oven is Ownable {
    IDough dough;
    IDough pza;
    address projectwallet;

    uint256 constant WAITTIME = 6 hours;

    uint256[] public burnRates = [40, 25, 15, 10];
    uint256[] public burnPrices = [1 ether, 5 ether, 10 ether, 50 ether];
    uint256[] public conversionRates = [1000, 900, 800, 500];
    uint256[] public conversionPrices = [2 ether, 8 ether, 16 ether, 32 ether];

    mapping(address => uint256) public depositTime;
    mapping(address => uint256) public doughDeposit;
    mapping(address => uint256) public burnUpgrade;
    mapping(address => uint256) public conversionUpgrade;

    constructor(address _dough, address _pza, address _projectwallet) {
        dough = IDough(_dough);
        pza = IDough(_pza);
        projectwallet = _projectwallet;
    }

    function getBurnUpPrice(address user) external view returns (uint256) {
        return burnPrices[burnUpgrade[msg.sender]];
    }

    function getConversionUpPrice(address user) external view returns (uint256) {
        return conversionPrices[conversionUpgrade[msg.sender]];
    }

    function getBurnUpgradeLevel(address user) external view returns (uint256) {
        return burnUpgrade[msg.sender];
    }

    function getConversionUpgradeLevel(address user) external view returns (uint256) {
        return conversionUpgrade[msg.sender];
    }

    function buyBurnUpgrade() external {
        require(burnUpgrade[msg.sender] < burnRates.length - 1, "Oven: Max burn upgrade reached");
        
        uint256 price = burnPrices[burnUpgrade[msg.sender]];
        uint256 approv = pza.allowance(msg.sender, address(this));
        require( approv >= price, "Oven: Insufficient Allowance");
        pza.transferFrom(msg.sender, address(this), price);

        burnUpgrade[msg.sender] += 1;
    }

    function buyConversionUpgrade() external {
        require(conversionUpgrade[msg.sender] < conversionRates.length - 1, "Oven: Max Conversion upgrade reached");

        uint256 price = conversionPrices[conversionUpgrade[msg.sender]];
        uint256 approv = pza.allowance(msg.sender, address(this));
        require( approv >= price, "Oven: Insufficient Allowance");
        pza.transferFrom(msg.sender, address(this), price);

        conversionUpgrade[msg.sender] += 1;
    }

    function getDoughDeposit(address user) external view returns (uint256) {
        return doughDeposit[user];
    }

    function getPizzaReady(address user) external view returns (uint256) {
        return depositTime[user] + WAITTIME;
    }


    /// @dev Put dough into oven to receive pizza, amount depends on upgrade status
    /// @param amount Amount of Tokens to add to pizza oven
    function bake(uint256 amount) external {
        require(doughDeposit[msg.sender] == 0, "Oven still in use");
        uint256 spendable = dough.allowance(msg.sender, address(this));
        require(spendable >= amount, "Allowance insufficient");
        dough.transferFrom(msg.sender, address(this), amount);
        dough.burn(amount);
        doughDeposit[msg.sender] = amount;
        depositTime[msg.sender] = block.timestamp;
    }

    function getPizzaAmount(address user) external view returns (uint256) {
        uint256 totalPZA = doughDeposit[user] / conversionRates[conversionUpgrade[user]];
        uint256 halfBurn = totalPZA * burnRates[burnUpgrade[user]] / 200;
        uint256 pizzaout = totalPZA - 2*halfBurn;
        return pizzaout;
    }


    function withdraw() external {
        require(doughDeposit[msg.sender] > 0, "Oven: Empty oven, cannot withdraw");
        require(block.timestamp - depositTime[msg.sender] >= WAITTIME, "Oven: Pizza is not ready");
        uint256 totalPZA = doughDeposit[msg.sender] / conversionRates[conversionUpgrade[msg.sender]];
        uint256 halfBurn = totalPZA * burnRates[burnUpgrade[msg.sender]] / 200;
        uint256 pizzaout = totalPZA - 2*halfBurn;
        doughDeposit[msg.sender] = 0;
        //implicit burn half
        pza.mint(projectwallet, halfBurn);
        pza.mint(msg.sender, pizzaout);
    }


}