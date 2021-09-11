// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract XToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("XToken", "XTKN") {
        _mint(msg.sender, initialSupply);
    }
}