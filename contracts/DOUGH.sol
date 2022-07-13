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

    mapping(address => bool) allowed;

    constructor() ERC20("Dough", "DOUGH") {
        allowed[msg.sender] = true;
    }

    function setCtrs(address _foodtruck, address _projectwallet) external onlyOwner {
        foodtruck = _foodtruck;
        allowed[foodtruck] = true;
        projectwallet = _projectwallet;
    }
    modifier onlyAllowed() { 
        require(allowed[msg.sender], "!allowed");
        _;
    }
    function setAllowed(address to, bool allow) external onlyOwner{
        allowed[to] = allow;
    }

    function changeTaxStatus(address addr, bool _tax) external onlyOwner {
        taxfree[addr] = _tax;
    }

    function mint(address receiver, uint256 amount) external onlyAllowed {
        _mint(receiver, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    function burnFrom(address from, uint256 amount) external {
        uint current = allowance(from, msg.sender);
        require(current >= amount, "!allowance");
        _approve(from, msg.sender, current - amount);
        _burn(from, amount);
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