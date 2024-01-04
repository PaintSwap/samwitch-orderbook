// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract MockERC1155 is ERC1155, IERC2981 {
  address public immutable owner = msg.sender;
  uint64 public nextId = 1;

  constructor() ERC1155("") {}

  function mint(uint _quantity) external {
    _mint(_msgSender(), nextId++, _quantity, "");
  }

  function mintBatch(uint[] memory _amounts) external {
    uint[] memory ids = new uint[](_amounts.length);
    for (uint i = 0; i < _amounts.length; ++i) {
      ids[i] = nextId++;
    }
    _mintBatch(_msgSender(), ids, _amounts, "");
  }

  function royaltyInfo(
    uint /*_tokenId*/,
    uint _salePrice
  ) external view override returns (address receiver, uint royaltyAmount) {
    uint royaltyFee = 250; // 2.5%
    uint amount = (_salePrice * royaltyFee) / 1000;
    return (owner, amount);
  }

  function supportsInterface(bytes4 _interfaceId) public view override(ERC1155, IERC165) returns (bool) {
    return _interfaceId == type(IERC2981).interfaceId || super.supportsInterface(_interfaceId);
  }
}
