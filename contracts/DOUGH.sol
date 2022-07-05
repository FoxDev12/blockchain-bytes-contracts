// This is an ERC20 token, illiquid, its main purpose is to be turned into PZA through the oven or staked in the Fermenter for more dough. It can also buy upgrades? 

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/ERC20.sol";

contract DOUGH is Ownable, ERC20 {
    uint256 tax = 20;
    address foodtruck;
    address projectwallet;
    mapping(address => bool) taxfree;

    constructor() ERC20("Dough", "DOUGH") {}

    function setCtrs(address _foodtruck, address _projectwallet) external onlyOwner {
        foodtruck = _foodtruck;
        projectwallet = _projectwallet;
    }

    function changeTaxStatus(address addr, bool _tax) external onlyOwner {
        taxfree[addr] = _tax;
    }

    function mint(address receiver, uint256 amount) external {
        require(msg.sender == foodtruck, "Not allowed to mint more");
        _mint(receiver, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }


    function reduceTax(uint256 newtax) external onlyOwner {
        require(newtax < tax, "Can only lower token tax");
        tax = newtax;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {

        if (taxfree[from] || taxfree[to]) {
            ERC20._transfer(from, to, amount);
        } else {
            uint256 totaltax = (amount * tax) / 100;
            uint256 nextamount = amount - totaltax;
            ERC20._transfer(from, to, nextamount);
            ERC20._transfer(from, projectwallet, totaltax);
        }
    }
}