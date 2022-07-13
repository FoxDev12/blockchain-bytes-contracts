// This is the PZA token. Liquid, main ecosystem token, taxable, 

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/ERC20.sol";

contract PZA is Ownable, ERC20 {
    uint256 tax = 20;
    address oven;
    address projectwallet;
    mapping(address => bool) taxfree;
    mapping(address => bool) allowed;

    constructor() ERC20("Pizza", "PZA") {
        allowed[msg.sender] = true;
    }
    modifier onlyAllowed() { 
        require(allowed[msg.sender], "!allowed");
        _;
    }
    function setAllowed(address to, bool allow) external onlyOwner{
        allowed[to] = allow;
    }

    function setCtrs(address _oven, address _projectwallet) external onlyOwner {
        oven = _oven;
        projectwallet = _projectwallet;
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
        uint256 totaltax = (amount * tax) / 100;
        uint256 nextamount = amount - totaltax;
        if (taxfree[from] || taxfree[to]) {
            ERC20._transfer(from, to, amount);
        } else {
            ERC20._transfer(from, to, nextamount);
            ERC20._transfer(from, projectwallet, totaltax);
        }
    }
}