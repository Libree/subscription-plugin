// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestUSDC is ERC20 {
    uint public INITIAL_SUPPLY = 100000000000000000000000;

    constructor() ERC20("TestUSDC", "TUSDC") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
