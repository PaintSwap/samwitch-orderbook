// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract MockERC1155 is ERC1155, IERC2981 {
  address public immutable royaltyRecipient;
  uint64 public nextId = 1;
  uint64 public royaltyFee; // Base 10000

  constructor(address _royaltyRecipient) ERC1155("") {
    royaltyRecipient = _royaltyRecipient;
  }

  function mint(uint256 _quantity) external {
    _mint(_msgSender(), nextId++, _quantity, "");
  }

  function mintSpecificId(uint256 _id, uint256 _quantity) external {
    _mint(_msgSender(), _id, _quantity, "");
  }

  function mintBatch(uint256[] memory _amounts) external {
    uint256[] memory ids = new uint256[](_amounts.length);
    for (uint256 i = 0; i < _amounts.length; ++i) {
      ids[i] = nextId++;
    }
    _mintBatch(_msgSender(), ids, _amounts, "");
  }

  function royaltyInfo(
    uint256 /*_tokenId*/,
    uint256 _salePrice
  ) external view override returns (address receiver, uint256 royaltyAmount) {
    uint256 amount = (_salePrice * royaltyFee) / 10000;
    return (royaltyRecipient, amount);
  }

  function setRoyaltyFee(uint64 _fee) external {
    royaltyFee = _fee;
  }

  function supportsInterface(bytes4 _interfaceId) public view override(ERC1155, IERC165) returns (bool) {
    return _interfaceId == type(IERC2981).interfaceId || super.supportsInterface(_interfaceId);
  }
}
