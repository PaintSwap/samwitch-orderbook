//SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBrushToken is IERC20 {
  function burn(uint _amount) external;
}
