// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HEX is ERC20 {
    constructor(address account, uint256 initialSupply)
        public
        ERC20("TST-HEX", "TST-HEX")
    {
        _setupDecimals(8);
        _mint(account, initialSupply);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
