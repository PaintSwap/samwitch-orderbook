// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBrushToken} from "../interfaces/IBrushToken.sol";

contract MockBrushToken is ERC20("PaintSwap Token", "BRUSH"), IBrushToken {
  uint256 public amountBurnt;

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function burn(uint256 _amount) external {
    amountBurnt += _amount;
    _burn(msg.sender, _amount);
  }
}
