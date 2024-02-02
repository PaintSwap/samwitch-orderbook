// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {BokkyPooBahsRedBlackTreeLibrary} from "../BokkyPooBahsRedBlackTreeLibrary.sol";

interface ISamWitchOrderBook is IERC1155Receiver {
  enum OrderSide {
    Buy,
    Sell
  }

  struct TokenInfo {
    uint128 tick;
    uint128 minQuantity;
  }

  struct LimitOrder {
    OrderSide side;
    uint tokenId;
    uint72 price;
    uint24 quantity;
  }

  struct CancelOrder {
    OrderSide side;
    uint tokenId;
    uint72 price;
  }

  struct OrderInfo {
    address maker;
    uint80 claimable;
  }

  struct OrderBookEntryHelper {
    address maker;
    uint24 quantity;
    uint40 id;
  }

  event AddedToBook(address maker, OrderSide side, uint orderId, uint tokenId, uint price, uint quantity);
  event OrdersMatched(address taker, uint[] orderIds, uint[] quantities);
  event OrdersCancelled(address maker, uint[] orderIds);
  event FailedToAddToBook(address maker, OrderSide side, uint tokenId, uint price, uint quantity);
  event ClaimedTokens(address user, uint[] orderIds, uint amount, uint fees);
  event ClaimedNFTs(address user, uint[] orderIds, uint[] tokenIds, uint[] amounts);
  event SetTokenInfos(uint[] tokenIds, TokenInfo[] tokenInfos);
  event SetMaxOrdersPerPriceLevel(uint maxOrdersPerPrice);
  event SetFees(address devAddr, uint devFee, uint burntFee);

  error ZeroAddress();
  error DevFeeNotSet();
  error DevFeeTooHigh();
  error NotERC1155();
  error NoQuantity();
  error OrderNotFound(uint orderId, uint price);
  error OrderNotFoundInTree(uint orderId, uint price);
  error PriceNotMultipleOfTick(uint tick);
  error TokenDoesntExist(uint tokenId);
  error PriceZero();
  error LengthMismatch();
  error NotMaker();
  error NothingToClaim();
  error TooManyOrdersHit();

  error DeadlineExpired(uint deadline);
  error InvalidNonce(uint invalid, uint nonce);
  error InvalidSignature(address sender, address recoveredAddress);

  function limitOrders(LimitOrder[] calldata orders) external;

  function cancelOrders(uint[] calldata orderIds, CancelOrder[] calldata cancelOrderInfos) external;

  function claimTokens(uint[] calldata _orderIds) external;

  function claimNFTs(uint[] calldata orderIds, uint[] calldata tokenIds) external;

  function claimAll(uint[] calldata brushOrderIds, uint[] calldata nftOrderIds, uint[] calldata tokenIds) external;

  function tokensClaimable(uint40[] calldata orderIds, bool takeAwayFees) external view returns (uint amount);

  function nftsClaimable(
    uint40[] calldata orderIds,
    uint[] calldata tokenIds
  ) external view returns (uint[] memory amounts);

  function getHighestBid(uint tokenId) external view returns (uint72);

  function getLowestAsk(uint tokenId) external view returns (uint72);

  function getNode(
    OrderSide side,
    uint tokenId,
    uint72 price
  ) external view returns (BokkyPooBahsRedBlackTreeLibrary.Node memory);

  function nodeExists(OrderSide side, uint tokenId, uint72 price) external view returns (bool);

  function getTokenInfo(uint tokenId) external view returns (TokenInfo memory);

  function getOrderInfo(uint40 _orderId) external view returns (OrderInfo memory);

  function allOrdersAtPrice(
    OrderSide side,
    uint tokenId,
    uint72 price
  ) external view returns (OrderBookEntryHelper[] memory orderBookEntries);
}
