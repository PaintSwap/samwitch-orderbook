// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {UnsafeMath} from "@0xdoublesharp/unsafe-math/contracts/UnsafeMath.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {BokkyPooBahsRedBlackTreeLibrary} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

import {IBrushToken} from "./interfaces/IBrushToken.sol";
import {ISamWitchOrderBook} from "./interfaces/ISamWitchOrderBook.sol";

/// @title SamWitchOrderBook (SWOB)
/// @author Sam Witch (PaintSwap, Estfor Kingdom) & 0xDoubleSharp
/// @notice This efficient ERC1155 order book is an upgradeable UUPS proxy contract. It has functions for bulk placing
///         limit orders, cancelling limit orders, and claiming NFTs and tokens from filled or partially filled orders.
///         It suppports ERC2981 royalties, and optional dev & burn fees on successful trades.
contract SamWitchOrderBook is ISamWitchOrderBook, ERC1155Holder, UUPSUpgradeable, OwnableUpgradeable {
  using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;
  using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Node;
  using UnsafeMath for uint256;
  using UnsafeMath for uint40;
  using UnsafeMath for uint24;
  using UnsafeMath for uint8;
  using SafeERC20 for IBrushToken;

  // constants
  uint16 private constant MAX_ORDERS_HIT = 500;
  uint8 private constant NUM_ORDERS_PER_SEGMENT = 4;

  uint private constant MAX_ORDER_ID = 1_099_511_627_776;

  uint private constant MAX_CLAIMABLE_ORDERS = 200;

  // slot_0
  IERC1155 private nft;

  // slot_1
  IBrushToken private token;

  // slot_2
  address private devAddr;
  uint16 private devFee; // Base 10000
  uint8 private burntFee;
  uint16 private royaltyFee;
  uint16 private maxOrdersPerPrice;
  uint40 private nextOrderId;

  // slot_3
  address private royaltyRecipient;

  // mappings
  mapping(uint tokenId => TokenIdInfo tokenIdInfo) private tokenIdInfo;
  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private asks;
  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private bids;
  // token id => price => ask(quantity (uint24), id (uint40)) x 4
  mapping(uint tokenId => mapping(uint price => bytes32[] segments)) private asksAtPrice;
  // token id => price => bid(quantity (uint24), id (uint40)) x 4
  mapping(uint tokenId => mapping(uint price => bytes32[] segments)) private bidsAtPrice;
  // token id => order id => amount claimable, 3 per slot
  mapping(uint tokenId => uint80[MAX_ORDER_ID]) private amountClaimableForTokenId;
  // order id => (maker, amount claimable)
  ClaimableTokenInfo[MAX_ORDER_ID] private tokenClaimable;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the contract as part of the proxy contract deployment
  /// @param _nft Address of the nft
  /// @param _token The quote token
  /// @param _devAddr The address to receive trade fees
  /// @param _devFee The fee to send to the dev address (max 10%)
  /// @param _burntFee The fee to burn (max 2.55%)
  /// @param _maxOrdersPerPrice The maximum number of orders allowed at each price level
  function initialize(
    IERC1155 _nft,
    address _token,
    address _devAddr,
    uint16 _devFee,
    uint8 _burntFee,
    uint16 _maxOrdersPerPrice
  ) external payable initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(_msgSender());

    setFees(_devAddr, _devFee, _burntFee);
    // nft must be an ERC1155 via ERC165
    if (!_nft.supportsInterface(type(IERC1155).interfaceId)) {
      revert NotERC1155();
    }

    nft = _nft;
    token = IBrushToken(_token);
    updateRoyaltyFee();

    // The max orders spans segments, so num segments = maxOrdersPrice / NUM_ORDERS_PER_SEGMENT
    setMaxOrdersPerPrice(_maxOrdersPerPrice);
    nextOrderId = 1;
  }

  /// @notice Place multiple limit orders in the order book
  /// @param _orders Array of limit orders to be placed
  function limitOrders(LimitOrder[] calldata _orders) public override {
    uint royalty;
    uint dev;
    uint burn;
    uint brushToUs;
    uint brushFromUs;
    uint nftsToUs;
    uint[] memory nftIdsToUs = new uint[](_orders.length);
    uint[] memory nftAmountsToUs = new uint[](_orders.length);
    uint lengthFromUs;
    uint[] memory nftIdsFromUs = new uint[](_orders.length);
    uint[] memory nftAmountsFromUs = new uint[](_orders.length);
    address sender = _msgSender();

    // This is done here so that it can be used in many limit orders without wasting too much space
    uint[] memory orderIdsPool = new uint[](MAX_ORDERS_HIT);
    uint[] memory quantitiesPool = new uint[](MAX_ORDERS_HIT);

    // read the next order ID so we can increment in memory
    uint40 currentOrderId = nextOrderId;
    for (uint i = 0; i < _orders.length; ++i) {
      LimitOrder calldata limitOrder = _orders[i];
      (uint24 quantityAddedToBook, uint24 failedQuantity, uint cost) = _makeLimitOrder(
        currentOrderId,
        limitOrder,
        orderIdsPool,
        quantitiesPool
      );
      if (quantityAddedToBook != 0) {
        currentOrderId = uint40(currentOrderId.inc());
      }

      if (limitOrder.side == OrderSide.Buy) {
        brushToUs += cost + uint(limitOrder.price) * quantityAddedToBook;
        if (cost != 0) {
          (uint _royalty, uint _dev, uint _burn) = _calcFees(cost);
          royalty = royalty.add(_royalty);
          dev = dev.add(_dev);
          burn = burn.add(_burn);

          // Transfer the NFTs taken from the order book straight to the taker
          nftIdsFromUs[lengthFromUs] = limitOrder.tokenId;
          nftAmountsFromUs[lengthFromUs] = uint(limitOrder.quantity).sub(quantityAddedToBook);
          lengthFromUs = lengthFromUs.inc();
        }
      } else {
        // Selling, transfer all NFTs to us
        uint amount = limitOrder.quantity.sub(failedQuantity);
        if (amount != 0) {
          nftIdsToUs[nftsToUs] = limitOrder.tokenId;
          nftAmountsToUs[nftsToUs] = amount;
          nftsToUs = nftsToUs.inc();
        }

        // Transfer tokens to the seller if any have sold
        if (cost != 0) {
          (uint _royalty, uint _dev, uint _burn) = _calcFees(cost);
          royalty = royalty.add(_royalty);
          dev = dev.add(_dev);
          burn = burn.add(_burn);

          uint fees = _royalty.add(_dev).add(_burn);
          brushFromUs = brushFromUs.add(cost).sub(fees);
        }
      }
    }
    // update the state if any orders were added to the book
    if (currentOrderId != nextOrderId) {
      nextOrderId = currentOrderId;
    }

    if (brushToUs != 0) {
      token.safeTransferFrom(sender, address(this), brushToUs);
    }

    if (brushFromUs != 0) {
      token.safeTransfer(sender, brushFromUs);
    }

    if (nftsToUs != 0) {
      assembly ("memory-safe") {
        mstore(nftIdsToUs, nftsToUs)
        mstore(nftAmountsToUs, nftsToUs)
      }
      _safeBatchTransferNFTsToUs(sender, nftIdsToUs, nftAmountsToUs);
    }

    if (lengthFromUs != 0) {
      assembly ("memory-safe") {
        mstore(nftIdsFromUs, lengthFromUs)
        mstore(nftAmountsFromUs, lengthFromUs)
      }
      _safeBatchTransferNFTsFromUs(sender, nftIdsFromUs, nftAmountsFromUs);
    }

    _sendFees(royalty, dev, burn);
  }

  /// @notice Cancel multiple orders in the order book
  /// @param _orderIds Array of order IDs to be cancelled
  /// @param _orders Information about the orders so that they can be found in the order book
  function cancelOrders(uint[] calldata _orderIds, CancelOrder[] calldata _orders) public override {
    if (_orderIds.length != _orders.length) {
      revert LengthMismatch();
    }

    address sender = _msgSender();

    uint brushFromUs = 0;
    uint nftsFromUs = 0;
    uint numberOfOrders = _orderIds.length;
    uint[] memory nftIdsFromUs = new uint[](numberOfOrders);
    uint[] memory nftAmountsFromUs = new uint[](numberOfOrders);
    for (uint i = 0; i < numberOfOrders; ++i) {
      CancelOrder calldata cancelOrder = _orders[i];
      (OrderSide side, uint tokenId, uint72 price) = (cancelOrder.side, cancelOrder.tokenId, cancelOrder.price);

      if (side == OrderSide.Buy) {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, bidsAtPrice[tokenId][price], bids[tokenId]);
        // Send the remaining token back to them
        brushFromUs += quantity * price;
      } else {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, asksAtPrice[tokenId][price], asks[tokenId]);
        // Send the remaining NFTs back to them
        nftIdsFromUs[nftsFromUs] = tokenId;
        nftAmountsFromUs[nftsFromUs] = quantity;
        nftsFromUs = nftsFromUs.inc();
      }
    }

    emit OrdersCancelled(sender, _orderIds);

    // Transfer tokens if there are any to send
    if (brushFromUs != 0) {
      token.safeTransfer(sender, brushFromUs);
    }

    // Send the NFTs
    if (nftsFromUs != 0) {
      // shrink the size
      assembly ("memory-safe") {
        mstore(nftIdsFromUs, nftsFromUs)
        mstore(nftAmountsFromUs, nftsFromUs)
      }
      _safeBatchTransferNFTsFromUs(sender, nftIdsFromUs, nftAmountsFromUs);
    }
  }

  /// @notice Cancel multiple orders and place multiple limit orders in the order book. Can be used to replace orders
  /// @param _orderIds Array of order IDs to be cancelled
  /// @param _orders Information about the orders so that they can be found in the order book
  /// @param _newOrders Array of limit orders to be placed
  function cancelAndMakeLimitOrders(
    uint[] calldata _orderIds,
    CancelOrder[] calldata _orders,
    LimitOrder[] calldata _newOrders
  ) external override {
    cancelOrders(_orderIds, _orders);
    limitOrders(_newOrders);
  }

  /// @notice Claim tokens associated with filled or partially filled orders.
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  function claimTokens(uint[] calldata _orderIds) public override {
    if (_orderIds.length > MAX_CLAIMABLE_ORDERS) {
      revert ClaimingTooManyOrders();
    }
    uint amount;
    for (uint i = 0; i < _orderIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      ClaimableTokenInfo storage claimableTokenInfo = tokenClaimable[orderId];
      uint80 claimableAmount = claimableTokenInfo.amount;
      if (claimableAmount == 0) {
        revert NothingToClaim();
      }

      if (claimableTokenInfo.maker != _msgSender()) {
        revert NotMaker();
      }

      claimableTokenInfo.amount = 0;
      amount += claimableAmount;
    }

    if (amount == 0) {
      revert NothingToClaim();
    }
    (uint royalty, uint dev, uint burn) = _calcFees(amount);
    uint fees = royalty.add(dev).add(burn);
    token.safeTransfer(_msgSender(), amount.sub(fees));
    emit ClaimedTokens(_msgSender(), _orderIds, amount, fees);
  }

  /// @notice Claim NFTs associated with filled or partially filled orders
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  /// @param _tokenIds Array of token IDs to claim NFTs for
  function claimNFTs(uint[] calldata _orderIds, uint[] calldata _tokenIds) public override {
    if (_orderIds.length > MAX_CLAIMABLE_ORDERS) {
      revert ClaimingTooManyOrders();
    }

    if (_orderIds.length != _tokenIds.length) {
      revert LengthMismatch();
    }

    if (_tokenIds.length == 0) {
      revert NothingToClaim();
    }

    uint[] memory nftAmountsFromUs = new uint[](_tokenIds.length);
    for (uint i = 0; i < _tokenIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      uint tokenId = _tokenIds[i];
      uint amount = amountClaimableForTokenId[tokenId][orderId];
      if (amount == 0) {
        revert NothingToClaim();
      }
      nftAmountsFromUs[i] = amount;
      amountClaimableForTokenId[tokenId][orderId] = 0;
    }

    _safeBatchTransferNFTsFromUs(_msgSender(), _tokenIds, nftAmountsFromUs);
    emit ClaimedNFTs(_msgSender(), _orderIds, _tokenIds, nftAmountsFromUs);
  }

  /// @notice Convience function to claim both tokens and nfts in filled or partially filled orders.
  ///         Must be the maker of these orders.
  /// @param _brushOrderIds Array of order IDs from which to claim tokens
  /// @param _nftOrderIds Array of order IDs from which to claim NFTs
  /// @param _tokenIds Array of token IDs to claim NFTs for
  function claimAll(
    uint[] calldata _brushOrderIds,
    uint[] calldata _nftOrderIds,
    uint[] calldata _tokenIds
  ) external override {
    if (_brushOrderIds.length == 0 && _nftOrderIds.length == 0 && _tokenIds.length == 0) {
      revert NothingToClaim();
    }

    if (_brushOrderIds.length + _nftOrderIds.length > MAX_CLAIMABLE_ORDERS) {
      revert ClaimingTooManyOrders();
    }

    if (_brushOrderIds.length != 0) {
      claimTokens(_brushOrderIds);
    }

    if (_nftOrderIds.length != 0) {
      claimNFTs(_nftOrderIds, _tokenIds);
    }
  }

  /// @notice Get the amount of tokens claimable for these orders
  /// @param _orderIds The order IDs of which to find the claimable tokens for
  /// @param _takeAwayFees Whether to take away the fees from the claimable amount
  function tokensClaimable(
    uint40[] calldata _orderIds,
    bool _takeAwayFees
  ) external view override returns (uint amount_) {
    for (uint i = 0; i < _orderIds.length; ++i) {
      amount_ += tokenClaimable[_orderIds[i]].amount;
    }
    if (_takeAwayFees) {
      (uint royalty, uint dev, uint burn) = _calcFees(amount_);
      amount_ = amount_.sub(royalty).sub(dev).sub(burn);
    }
  }

  /// @notice Get the amount of NFTs claimable for these orders
  /// @param _orderIds The order IDs to get the claimable NFTs for
  /// @param _tokenIds The token IDs to get the claimable NFTs for
  function nftsClaimable(
    uint40[] calldata _orderIds,
    uint[] calldata _tokenIds
  ) external view override returns (uint[] memory amounts_) {
    amounts_ = new uint[](_orderIds.length);
    for (uint i = 0; i < _orderIds.length; ++i) {
      amounts_[i] = amountClaimableForTokenId[_tokenIds[i]][_orderIds[i]];
    }
  }

  /// @notice Get the token ID info for a specific token ID
  /// @param _tokenId The token ID to get the info for
  function getTokenIdInfo(uint _tokenId) external view override returns (TokenIdInfo memory) {
    return tokenIdInfo[_tokenId];
  }

  function getClaimableTokenInfo(uint40 _orderId) external view override returns (ClaimableTokenInfo memory) {
    return tokenClaimable[_orderId];
  }

  /// @notice Get the highest bid for a specific token ID
  /// @param _tokenId The token ID to get the highest bid for
  function getHighestBid(uint _tokenId) public view override returns (uint72) {
    return bids[_tokenId].last();
  }

  /// @notice Get the lowest ask for a specific token ID
  /// @param _tokenId The token ID to get the lowest ask for
  function getLowestAsk(uint _tokenId) public view override returns (uint72) {
    return asks[_tokenId].first();
  }

  /// @notice Get the order book entry for a specific order ID
  /// @param _side The side of the order book to get the order from
  /// @param _tokenId The token ID to get the order for
  /// @param _price The price level to get the order for
  function getNode(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view override returns (BokkyPooBahsRedBlackTreeLibrary.Node memory) {
    if (_side == OrderSide.Buy) {
      return bids[_tokenId].getNode(_price);
    } else {
      return asks[_tokenId].getNode(_price);
    }
  }

  /// @notice Check if the node exists
  /// @param _side The side of the order book to get the order from
  /// @param _tokenId The token ID to get the order for
  /// @param _price The price level to get the order for
  function nodeExists(OrderSide _side, uint _tokenId, uint72 _price) external view override returns (bool) {
    if (_side == OrderSide.Buy) {
      return bids[_tokenId].exists(_price);
    } else {
      return asks[_tokenId].exists(_price);
    }
  }

  /// @notice Get all orders at a specific price level
  /// @param _side The side of the order book to get orders from
  /// @param _tokenId The token ID to get orders for
  /// @param _price The price level to get orders for
  function allOrdersAtPrice(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view override returns (Order[] memory) {
    if (_side == OrderSide.Buy) {
      return _allOrdersAtPriceSide(bidsAtPrice[_tokenId][_price], bids[_tokenId], _price);
    } else {
      return _allOrdersAtPriceSide(asksAtPrice[_tokenId][_price], asks[_tokenId], _price);
    }
  }

  /// @notice When the nft royalty changes this updates the fee and recipient. Assumes all token ids have the same royalty
  function updateRoyaltyFee() public {
    if (nft.supportsInterface(type(IERC2981).interfaceId)) {
      (address _royaltyRecipient, uint _royaltyFee) = IERC2981(address(nft)).royaltyInfo(1, 10000);
      royaltyRecipient = _royaltyRecipient;
      royaltyFee = uint16(_royaltyFee);
    } else {
      royaltyRecipient = address(0);
      royaltyFee = 0;
    }
  }

  /// @notice The maximum amount of orders allowed at a specific price level
  /// @param _maxOrdersPerPrice The new maximum amount of orders allowed at a specific price level
  function setMaxOrdersPerPrice(uint16 _maxOrdersPerPrice) public payable onlyOwner {
    maxOrdersPerPrice = _maxOrdersPerPrice;
    if (maxOrdersPerPrice % NUM_ORDERS_PER_SEGMENT != 0) {
      revert MaxOrdersNotMultipleOfOrdersInSegment();
    }
    emit SetMaxOrdersPerPriceLevel(_maxOrdersPerPrice);
  }

  /// @notice Set constraints like minimum quantity of an order that is allowed to be
  ///         placed and the minimum of specific tokenIds in this nft collection.
  /// @param _tokenIds Array of token IDs for which to set TokenInfo
  /// @param _tokenIdInfos Array of TokenInfo to be set
  function setTokenIdInfos(uint[] calldata _tokenIds, TokenIdInfo[] calldata _tokenIdInfos) external payable onlyOwner {
    if (_tokenIds.length != _tokenIdInfos.length) {
      revert LengthMismatch();
    }

    for (uint i = 0; i < _tokenIds.length; ++i) {
      // Cannot change tick once set
      uint existingTick = tokenIdInfo[_tokenIds[i]].tick;
      uint newTick = _tokenIdInfos[i].tick;

      if (existingTick != 0 && newTick != 0 && existingTick != newTick) {
        revert TickCannotBeChanged();
      }

      tokenIdInfo[_tokenIds[i]] = _tokenIdInfos[i];
    }

    emit SetTokenIdInfos(_tokenIds, _tokenIdInfos);
  }

  /// @notice Set the fees for the contract
  /// @param _devAddr The address to receive trade fees
  /// @param _devFee The fee to send to the dev address (max 10%)
  /// @param _burntFee The fee to burn (max 2%)
  function setFees(address _devAddr, uint16 _devFee, uint8 _burntFee) public onlyOwner {
    if (_devFee != 0) {
      if (_devAddr == address(0)) {
        revert ZeroAddress();
      } else if (_devFee > 1000) {
        revert DevFeeTooHigh();
      }
    } else if (_devAddr != address(0)) {
      revert DevFeeNotSet();
    }
    devFee = _devFee; // 30 = 0.3% fee
    devAddr = _devAddr;
    burntFee = _burntFee;
    emit SetFees(_devAddr, _devFee, _burntFee);
  }

  function _takeFromOrderBookSide(
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool,
    OrderSide _side, // which side are you taking from
    mapping(uint tokenId => mapping(uint price => bytes32[] segments)) storage segmentsAtPrice,
    mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) storage tree
  ) private returns (uint24 quantityRemaining_, uint cost_) {
    quantityRemaining_ = _quantity;

    // reset the size
    assembly ("memory-safe") {
      mstore(_orderIdsPool, MAX_ORDERS_HIT)
      mstore(_quantitiesPool, MAX_ORDERS_HIT)
    }

    bool isTakingFromBuy = _side == OrderSide.Buy;
    uint numberOfOrders;
    while (quantityRemaining_ != 0) {
      uint72 bestPrice = isTakingFromBuy ? getHighestBid(_tokenId) : getLowestAsk(_tokenId);
      if (bestPrice == 0 || isTakingFromBuy ? bestPrice < _price : bestPrice > _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numSegmentsFullyConsumed = 0;
      bytes32[] storage segments = segmentsAtPrice[_tokenId][bestPrice];
      BokkyPooBahsRedBlackTreeLibrary.Node storage node = tree[_tokenId].getNode(bestPrice);

      bool eatIntoLastOrder;
      uint numOrdersWithinLastSegmentFullyConsumed;
      bytes32 segment;
      uint lastSegment;
      for (uint i = node.tombstoneOffset; i < segments.length && quantityRemaining_ != 0; ++i) {
        lastSegment = i;
        segment = segments[i];
        uint numOrdersWithinSegmentConsumed;
        bool wholeSegmentConsumed;
        for (uint offset; offset < NUM_ORDERS_PER_SEGMENT && quantityRemaining_ != 0; ++offset) {
          uint remainingSegment = uint(segment >> offset.mul(64));
          uint40 orderId = uint40(remainingSegment);
          if (orderId == 0) {
            // Check if there are any order left in this segment
            if (remainingSegment != 0) {
              // Skip this order in the segment as it's been deleted
              numOrdersWithinLastSegmentFullyConsumed = numOrdersWithinLastSegmentFullyConsumed.inc();
              continue;
            } else {
              break;
            }
          }
          uint24 quantityL3 = uint24(uint(segment >> offset.mul(64).add(40)));
          uint quantityNFTClaimable = 0;
          if (quantityRemaining_ >= quantityL3) {
            // Consume this whole order
            quantityRemaining_ -= quantityL3;
            // Is the last one in the segment being fully consumed?
            wholeSegmentConsumed = offset == NUM_ORDERS_PER_SEGMENT.dec();
            numOrdersWithinSegmentConsumed = numOrdersWithinSegmentConsumed.inc();
            quantityNFTClaimable = quantityL3;
          } else {
            // Eat into the order
            segment = bytes32(
              (uint(segment) & ~(uint(0xffffff) << offset.mul(64).add(40))) |
                (uint(quantityL3 - quantityRemaining_) << offset.mul(64).add(40))
            );
            quantityNFTClaimable = quantityRemaining_;
            quantityRemaining_ = 0;
            eatIntoLastOrder = true;
          }
          cost_ += quantityNFTClaimable * bestPrice;

          if (isTakingFromBuy) {
            amountClaimableForTokenId[_tokenId][orderId] += uint80(quantityNFTClaimable);
          } else {
            tokenClaimable[orderId].amount += uint80(quantityNFTClaimable * bestPrice);
          }

          _orderIdsPool[numberOfOrders] = orderId;
          _quantitiesPool[numberOfOrders] = quantityNFTClaimable;
          numberOfOrders = numberOfOrders.inc();

          if (numberOfOrders >= MAX_ORDERS_HIT) {
            revert TooManyOrdersHit();
          }
        }

        if (wholeSegmentConsumed) {
          numSegmentsFullyConsumed = numSegmentsFullyConsumed.inc();
          numOrdersWithinLastSegmentFullyConsumed = 0;
        } else {
          numOrdersWithinLastSegmentFullyConsumed = numOrdersWithinLastSegmentFullyConsumed.add(
            numOrdersWithinSegmentConsumed
          );
          if (eatIntoLastOrder) {
            break;
          }
        }
      }

      if (numSegmentsFullyConsumed != 0) {
        uint tombstoneOffset = node.tombstoneOffset;
        tree[_tokenId].edit(bestPrice, uint32(numSegmentsFullyConsumed));

        // Consumed all orders at this price level, so remove it from the tree
        if (numSegmentsFullyConsumed == segments.length - tombstoneOffset) {
          tree[_tokenId].remove(bestPrice); // TODO: A ranged delete would be nice
        }
      }

      if (eatIntoLastOrder || numOrdersWithinLastSegmentFullyConsumed != 0) {
        // This segment wasn't completely filled before
        if (numOrdersWithinLastSegmentFullyConsumed != 0) {
          for (uint i; i < numOrdersWithinLastSegmentFullyConsumed; ++i) {
            segment &= _clearOrderMask(i);
          }
        }
        if (uint(segment) == 0) {
          // All orders in the segment are consumed, delete from tree
          tree[_tokenId].remove(bestPrice);
        }

        segments[lastSegment] = segment;

        if (eatIntoLastOrder) {
          break;
        }
      }
    }
    if (numberOfOrders != 0) {
      assembly ("memory-safe") {
        mstore(_orderIdsPool, numberOfOrders)
        mstore(_quantitiesPool, numberOfOrders)
      }

      emit OrdersMatched(_msgSender(), _orderIdsPool, _quantitiesPool);
    }
  }

  function _takeFromOrderBook(
    OrderSide _side,
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining, uint cost) {
    // Take as much as possible from the order book
    if (_side == OrderSide.Buy) {
      (quantityRemaining, cost) = _takeFromOrderBookSide(
        _tokenId,
        _price,
        _quantity,
        _orderIdsPool,
        _quantitiesPool,
        OrderSide.Sell,
        asksAtPrice,
        asks
      );
    } else {
      (quantityRemaining, cost) = _takeFromOrderBookSide(
        _tokenId,
        _price,
        _quantity,
        _orderIdsPool,
        _quantitiesPool,
        OrderSide.Buy,
        bidsAtPrice,
        bids
      );
    }
  }

  function _allOrdersAtPriceSide(
    bytes32[] storage _segments,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price
  ) private view returns (Order[] memory orders_) {
    if (!_tree.exists(_price)) {
      return orders_;
    }
    BokkyPooBahsRedBlackTreeLibrary.Node storage node = _tree.getNode(_price);
    uint tombstoneOffset = node.tombstoneOffset;

    uint numInSegmentDeleted;
    {
      uint segment = uint(_segments[tombstoneOffset]);
      for (uint offset; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
        uint remainingSegment = uint64(segment >> offset.mul(64));
        uint64 order = uint64(remainingSegment);
        if (order == 0) {
          numInSegmentDeleted = numInSegmentDeleted.inc();
        } else {
          break;
        }
      }
    }

    orders_ = new Order[]((_segments.length - tombstoneOffset) * NUM_ORDERS_PER_SEGMENT - numInSegmentDeleted);
    uint numberOfEntries;
    for (uint i = numInSegmentDeleted; i < orders_.length.add(numInSegmentDeleted); ++i) {
      uint segment = uint(_segments[i.div(NUM_ORDERS_PER_SEGMENT).add(tombstoneOffset)]);
      uint offset = i.mod(NUM_ORDERS_PER_SEGMENT);
      uint40 id = uint40(segment >> offset.mul(64));
      if (id != 0) {
        uint24 quantity = uint24(segment >> offset.mul(64).add(40));
        orders_[numberOfEntries] = Order(tokenClaimable[id].maker, quantity, id);
        numberOfEntries = numberOfEntries.inc();
      }
    }

    assembly ("memory-safe") {
      mstore(orders_, numberOfEntries)
    }
  }

  function _cancelOrdersSide(
    uint _orderId,
    uint72 _price,
    bytes32[] storage _segments,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private returns (uint24 quantity_) {
    // Loop through all of them until we hit ours.
    if (!_tree.exists(_price)) {
      revert OrderNotFoundInTree(_orderId, _price);
    }

    BokkyPooBahsRedBlackTreeLibrary.Node storage node = _tree.getNode(_price);
    uint tombstoneOffset = node.tombstoneOffset;

    (uint index, uint offset) = _find(_segments, tombstoneOffset, _segments.length, _orderId);
    if (index == type(uint).max) {
      revert OrderNotFound(_orderId, _price);
    }
    quantity_ = uint24(uint(_segments[index]) >> offset.mul(64).add(40));
    _cancelOrder(_segments, _price, index, offset, tombstoneOffset, _tree);
  }

  function _makeLimitOrder(
    uint40 _newOrderId,
    LimitOrder calldata _limitOrder,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityAddedToBook_, uint24 failedQuantity_, uint cost_) {
    if (_limitOrder.quantity == 0) {
      revert NoQuantity();
    }

    if (_limitOrder.price == 0) {
      revert PriceZero();
    }

    uint128 tick = tokenIdInfo[_limitOrder.tokenId].tick;

    if (tick == 0) {
      revert TokenDoesntExist(_limitOrder.tokenId);
    }

    if (_limitOrder.price % tick != 0) {
      revert PriceNotMultipleOfTick(tick);
    }

    uint24 quantityRemaining;
    (quantityRemaining, cost_) = _takeFromOrderBook(
      _limitOrder.side,
      _limitOrder.tokenId,
      _limitOrder.price,
      _limitOrder.quantity,
      _orderIdsPool,
      _quantitiesPool
    );

    // Add the rest to the order book if has the minimum required, in order to keep order books healthy
    if (quantityRemaining >= tokenIdInfo[_limitOrder.tokenId].minQuantity) {
      quantityAddedToBook_ = quantityRemaining;
      _addToBook(_newOrderId, tick, _limitOrder.side, _limitOrder.tokenId, _limitOrder.price, quantityAddedToBook_);
    } else if (quantityRemaining != 0) {
      failedQuantity_ = quantityRemaining;
      emit FailedToAddToBook(_msgSender(), _limitOrder.side, _limitOrder.tokenId, _limitOrder.price, failedQuantity_);
    }
  }

  function _addToBookSide(
    mapping(uint price => bytes32[]) storage _segmentsPriceMap,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price,
    uint _orderId,
    uint _quantity,
    int128 _tick // -1 for buy, +1 for sell
  ) private returns (uint72 price_) {
    // Add to the bids section
    price_ = _price;
    if (!_tree.exists(price_)) {
      _tree.insert(price_);
    } else {
      uint tombstoneOffset = _tree.getNode(price_).tombstoneOffset;
      // Check if this would go over the max number of orders allowed at this price level
      bool lastSegmentFilled = uint(
        _segmentsPriceMap[price_][_segmentsPriceMap[price_].length.dec()] >> NUM_ORDERS_PER_SEGMENT.dec().mul(64)
      ) != 0;

      // Check if last segment is full
      if (
        (_segmentsPriceMap[price_].length.sub(tombstoneOffset)).mul(NUM_ORDERS_PER_SEGMENT) >= maxOrdersPerPrice &&
        lastSegmentFilled
      ) {
        // Loop until we find a suitable place to put this
        while (true) {
          price_ = uint72(uint128(int72(price_) + _tick));
          if (!_tree.exists(price_)) {
            _tree.insert(price_);
            break;
          } else if (
            (_segmentsPriceMap[price_].length.sub(tombstoneOffset)).mul(NUM_ORDERS_PER_SEGMENT) < maxOrdersPerPrice ||
            uint(
              _segmentsPriceMap[price_][_segmentsPriceMap[price_].length.dec()] >> NUM_ORDERS_PER_SEGMENT.dec().mul(64)
            ) ==
            0
          ) {
            // There are segments available at this price level or the last segment is not filled yet
            break;
          }
        }
      }
    }

    // Read last one. Decide if we can add to the existing segment or if we need to add a new segment
    bytes32[] storage segments = _segmentsPriceMap[price_];
    bool pushToEnd = true;
    if (segments.length != 0) {
      bytes32 lastSegment = segments[segments.length.dec()];
      // Are there are free entries in this segment
      for (uint offset = 0; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
        uint remainingSegment = uint(lastSegment >> (offset.mul(64)));
        if (remainingSegment == 0) {
          // Found free entry one, so add to an existing segment
          bytes32 newSegment = lastSegment |
            (bytes32(_orderId) << (offset.mul(64))) |
            (bytes32(_quantity) << (offset.mul(64).add(40)));
          segments[segments.length.dec()] = newSegment;
          pushToEnd = false;
          break;
        }
      }
    }

    if (pushToEnd) {
      bytes32 segment = bytes32(_orderId) | (bytes32(_quantity) << 40);
      segments.push(segment);
    }
  }

  function _addToBook(
    uint40 _newOrderId,
    uint128 _tick,
    OrderSide _side,
    uint _tokenId,
    uint72 _price,
    uint24 _quantity
  ) private {
    tokenClaimable[_newOrderId] = ClaimableTokenInfo(_msgSender(), 0);
    uint72 price;
    // Price can update if the price level is at capacity
    if (_side == OrderSide.Buy) {
      price = _addToBookSide(bidsAtPrice[_tokenId], bids[_tokenId], _price, _newOrderId, _quantity, -int128(_tick));
    } else {
      price = _addToBookSide(asksAtPrice[_tokenId], asks[_tokenId], _price, _newOrderId, _quantity, int128(_tick));
    }
    emit AddedToBook(_msgSender(), _side, _newOrderId, _tokenId, price, _quantity);
  }

  function _calcFees(uint _cost) private view returns (uint royalty_, uint dev_, uint burn_) {
    royalty_ = (_cost.mul(royaltyFee)).div(10000);
    dev_ = (_cost.mul(devFee)).div(10000);
    burn_ = (_cost.mul(burntFee)).div(10000);
  }

  function _sendFees(uint _royalty, uint _dev, uint _burn) private {
    if (_royalty != 0) {
      token.safeTransfer(royaltyRecipient, _royalty);
    }

    if (_dev != 0) {
      token.safeTransfer(devAddr, _dev);
    }

    if (_burn != 0) {
      token.burn(_burn);
    }
  }

  function _find(
    bytes32[] storage segments,
    uint begin,
    uint end,
    uint value
  ) private view returns (uint mid_, uint offset_) {
    while (begin < end) {
      mid_ = begin.add(end.sub(begin).div(2));
      uint segment = uint(segments[mid_]);
      offset_ = 0;

      for (uint i = 0; i < NUM_ORDERS_PER_SEGMENT; ++i) {
        uint40 id = uint40(segment >> (offset_.mul(8)));
        if (id == value) {
          return (mid_, i); // Return the index where the ID is found
        } else if (id < value) {
          offset_ = offset_.add(8); // Move to the next segment
        } else {
          break; // Break if the searched value is smaller, as it's a binary search
        }
      }

      if (offset_ == NUM_ORDERS_PER_SEGMENT * 8) {
        begin = mid_.inc();
      } else {
        end = mid_;
      }
    }

    return (type(uint).max, type(uint).max); // ID not found in any segment of the segment data
  }

  function _cancelOrder(
    bytes32[] storage _segments,
    uint72 _price,
    uint _index,
    uint _offset,
    uint _tombstoneOffset,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private {
    bytes32 segment = _segments[_index];
    uint40 orderId = uint40(uint(segment) >> _offset.mul(64));

    if (tokenClaimable[orderId].maker != _msgSender()) {
      revert NotMaker();
    }

    if (_offset == 0 && segment >> 64 == 0) {
      // If there is only one order at the start of the segment then remove the whole segment
      _segments.pop();
      if (_segments.length == _tombstoneOffset) {
        _tree.remove(_price);
      }
    } else {
      uint indexToRemove = _index * NUM_ORDERS_PER_SEGMENT + _offset;

      // Although this is called next, it also acts as the "last" used later
      uint nextSegmentIndex = indexToRemove / NUM_ORDERS_PER_SEGMENT;
      uint nextOffsetIndex = indexToRemove % NUM_ORDERS_PER_SEGMENT;
      // Shift orders cross-segments.
      // This does all except the last order
      // TODO: For offset 0, 1, 2 we can shift the whole elements of the segment in 1 go.
      uint totalOrders = _segments.length.mul(NUM_ORDERS_PER_SEGMENT).dec();
      for (uint i = indexToRemove; i < totalOrders; ++i) {
        nextSegmentIndex = (i.inc()) / NUM_ORDERS_PER_SEGMENT;
        nextOffsetIndex = (i.inc()) % NUM_ORDERS_PER_SEGMENT;

        bytes32 currentOrNextSegment = _segments[nextSegmentIndex];

        uint currentSegmentIndex = i / NUM_ORDERS_PER_SEGMENT;
        uint currentOffsetIndex = i % NUM_ORDERS_PER_SEGMENT;

        bytes32 currentSegment = _segments[currentSegmentIndex];
        uint nextOrder = uint64(uint(currentOrNextSegment >> nextOffsetIndex.mul(64)));
        if (nextOrder == 0) {
          // There are no more orders left, reset back to the currently iterated order as the last
          nextSegmentIndex = currentSegmentIndex;
          nextOffsetIndex = currentOffsetIndex;
          break;
        }

        // Clear the current order and set it with the shifted order
        currentSegment &= _clearOrderMask(currentOffsetIndex);
        currentSegment |= bytes32(nextOrder) << currentOffsetIndex.mul(64);
        _segments[currentSegmentIndex] = currentSegment;
      }
      // Only pop if the next offset is 0 which means there is 1 order left in that segment
      if (nextOffsetIndex == 0) {
        _segments.pop();
      } else {
        // Clear the last element
        bytes32 lastElement = _segments[nextSegmentIndex];
        lastElement &= _clearOrderMask(nextOffsetIndex);
        _segments[nextSegmentIndex] = lastElement;
      }
    }
  }

  function _clearOrderMask(uint _offsetIndex) private pure returns (bytes32) {
    return ~(bytes32(uint(0xffffffffffffffff)) << _offsetIndex.mul(64));
  }

  function _safeBatchTransferNFTsToUs(address _from, uint[] memory _tokenIds, uint[] memory _amounts) private {
    nft.safeBatchTransferFrom(_from, address(this), _tokenIds, _amounts, "");
  }

  function _safeBatchTransferNFTsFromUs(address _to, uint[] memory _tokenIds, uint[] memory _amounts) private {
    nft.safeBatchTransferFrom(address(this), _to, _tokenIds, _amounts, "");
  }

  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
