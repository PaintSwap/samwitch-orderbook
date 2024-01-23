// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UnsafeMath} from "@0xdoublesharp/unsafe-math/contracts/UnsafeMath.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BokkyPooBahsRedBlackTreeLibrary} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

import {IBrushToken} from "./interfaces/IBrushToken.sol";
import {ISamWitchOrderBook} from "./interfaces/ISamWitchOrderBook.sol";

/// @title SamWitchOrderBook (SWOB)
/// @author Sam Witch (PaintSwap & Estfor Kingdom)
/// @author 0xDoubleSharp
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
  using ECDSA for bytes32;

  // constants
  uint16 private constant MAX_ORDERS_HIT = 500;
  uint8 private constant NUM_ORDERS_PER_SEGMENT = 4;

  string private constant VERSION = "1";
  bytes32 private constant EIP712_DOMAIN_HASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  bytes32 private constant LIMIT_ORDER_HASH =
    keccak256("LimitOrder(uint8 side,uint256 tokenId,uint72 price,uint24 quantity)");
  bytes32 private constant LIMIT_ORDERS_HASH =
    keccak256(
      abi.encodePacked(
        "limitOrders(address sender,uint256 nonce,uint256 deadline,LimitOrder[] orders)",
        "LimitOrder(uint8 side,uint256 tokenId,uint72 price,uint24 quantity)"
      )
    );

  bytes32 private constant CANCEL_ORDER_INFO_HASH = keccak256("CancelOrder(uint8 side,uint256 tokenId,uint72 price)");
  bytes32 private constant CANCEL_ORDERS_HASH =
    keccak256(
      abi.encodePacked(
        "cancelOrders(address sender,uint256 nonce,uint256 deadline,uint256[] orderIds,CancelOrder[] orders)",
        "CancelOrder(uint8 side,uint256 tokenId,uint72 price)"
      )
    );

  // state
  IERC1155 public nft;
  IBrushToken public token;

  address private devAddr;
  uint16 private devFee; // Base 10000
  uint8 private burntFee;
  uint16 private royaltyFee;
  uint16 private maxOrdersPerPrice;
  uint40 private nextOrderId;
  address private royaltyRecipient;

  mapping(uint tokenId => TokenIdInfo tokenIdInfo) public tokenIdInfos;

  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private asks;
  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private bids;
  mapping(uint tokenId => mapping(uint price => bytes32[] packedOrders)) private askValues; // quantity (uint24), id (uint40) 4x packed of these
  mapping(uint tokenId => mapping(uint price => bytes32[] packedOrders)) private bidValues; // quantity (uint24), id (uint40) 4x packed of these
  mapping(uint orderId => address maker) private orderBookIdToMaker;
  uint80[1_099_511_627_776] private brushClaimable; // Can pack 3 brush claimables into 1 word
  mapping(uint40 orderId => mapping(uint tokenId => uint amount)) private tokenIdsClaimable;

  mapping(address => uint) public nonces;

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

    // make sure dev address/fee is set appropriately
    if (_devFee != 0) {
      if (_devAddr == address(0)) {
        revert ZeroAddress();
      } else if (_devFee > 1000) {
        revert DevFeeNotSet();
      }
    } else if (_devAddr != address(0)) {
      revert DevFeeNotSet();
    }

    // nft must be an ERC1155 via ERC165
    if (!_nft.supportsInterface(type(IERC1155).interfaceId)) {
      revert NotERC1155();
    }

    nft = _nft;
    token = IBrushToken(_token);
    updateRoyaltyFee();

    devFee = _devFee; // 30 = 0.3% fee,
    devAddr = _devAddr;
    burntFee = _burntFee; // 30 = 0.3% fee,
    setMaxOrdersPerPrice(_maxOrdersPerPrice); // This includes inside segments, so num segments = maxOrdersPrice / NUM_ORDERS_PER_SEGMENT
    nextOrderId = 1;
  }

  /// @notice Place multiple limit orders in the order book
  /// @param _orders Array of limit orders to be placed
  function limitOrders(LimitOrder[] calldata _orders) external override {
    _limitOrders(_msgSender(), _orders);
  }

  function limitOrdersIfSignatureMatch(
    uint8 _v,
    bytes32 _r,
    bytes32 _s,
    address _sender,
    uint _nonce,
    uint _deadline,
    LimitOrder[] calldata _orders
  ) external {
    if (block.timestamp > _deadline) {
      revert DeadlineExpired(_deadline);
    }

    // check that the nonce matches the current nonce
    uint nonce = nonces[_sender];
    if (_nonce != nonce) {
      revert InvalidNonce(nonce, _nonce);
    }

    // we need to encode each of the array elements
    bytes32[] memory hashedOrders = new bytes32[](_orders.length);
    for (uint i = 0; i < _orders.length; i++) {
      hashedOrders[i] = keccak256(
        // use encode here to prevent collisions
        abi.encode(LIMIT_ORDER_HASH, _orders[i].side, _orders[i].tokenId, _orders[i].price, _orders[i].quantity)
      );
    }

    // this is the signed message hash
    bytes32 hash = MessageHashUtils.toTypedDataHash(
      _getDomainSeparator("limitOrders", VERSION, address(this)),
      keccak256(abi.encode(LIMIT_ORDERS_HASH, _sender, nonce, _deadline, keccak256(abi.encodePacked(hashedOrders))))
    );

    // recover the signer from the signature
    address recoveredAddress = hash.recover(_v, _r, _s);

    // check that the signer is the sender
    if (recoveredAddress != _sender || recoveredAddress == address(0)) {
      revert InvalidSignature(_sender, recoveredAddress);
    }

    // increment the nonce
    nonces[_sender] = nonce.inc();

    // execute limit orders
    _limitOrders(_sender, _orders);
  }

  function _limitOrders(address _sender, LimitOrder[] calldata _orders) private {
    uint numberOfOrders = _orders.length;
    uint royalty;
    uint dev;
    uint burn;
    uint brushToUs;
    uint brushFromUs;
    uint nftsToUs;
    uint[] memory nftIdsToUs = new uint[](numberOfOrders);
    uint[] memory nftAmountsToUs = new uint[](numberOfOrders);
    uint lengthFromUs;
    uint[] memory nftIdsFromUs = new uint[](numberOfOrders);
    uint[] memory nftAmountsFromUs = new uint[](numberOfOrders);

    // This is done here so that it can be used in many limit orders without wasting too much space
    uint[] memory orderIdsPool = new uint[](MAX_ORDERS_HIT);
    uint[] memory quantitiesPool = new uint[](MAX_ORDERS_HIT);

    // read the next order ID so we can increment in memory
    uint40 currentOrderId = nextOrderId;
    for (uint i = 0; i < numberOfOrders; ++i) {
      LimitOrder calldata limitOrder = _orders[i];
      (uint24 quantityAddedToBook, uint24 failedQuantity, uint cost) = _makeLimitOrder(
        currentOrderId,
        limitOrder,
        orderIdsPool,
        quantitiesPool
      );
      currentOrderId = uint40(currentOrderId.inc());

      if (limitOrder.side == OrderSide.Buy) {
        brushToUs += cost + uint(limitOrder.price) * quantityAddedToBook;
        if (cost != 0) {
          (uint _royalty, uint _dev, uint _burn) = _calcFees(cost);
          royalty = royalty.add(_royalty);
          dev = dev.add(_dev);
          burn = burn.add(_burn);

          // Transfer the NFTs straight to the user
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
    // update the state
    nextOrderId = currentOrderId;

    if (brushToUs != 0) {
      token.safeTransferFrom(_sender, address(this), brushToUs);
    }

    if (brushFromUs != 0) {
      token.safeTransfer(_sender, brushFromUs);
    }

    if (nftsToUs != 0) {
      assembly ("memory-safe") {
        mstore(nftIdsToUs, nftsToUs)
        mstore(nftAmountsToUs, nftsToUs)
      }
      _safeBatchTransferNFTsToUs(_sender, nftIdsToUs, nftAmountsToUs);
    }

    if (lengthFromUs != 0) {
      assembly ("memory-safe") {
        mstore(nftIdsFromUs, lengthFromUs)
        mstore(nftAmountsFromUs, lengthFromUs)
      }
      _safeBatchTransferNFTsFromUs(_sender, nftIdsFromUs, nftAmountsFromUs);
    }

    _sendFees(royalty, dev, burn);
  }

  /// @notice Cancel multiple orders in the order book
  /// @param _orderIds Array of order IDs to be cancelled
  /// @param _orders Information about the orders so that they can be found in the order book
  function cancelOrders(uint[] calldata _orderIds, CancelOrder[] calldata _orders) external override {
    if (_orderIds.length != _orders.length) {
      revert LengthMismatch();
    }
    _cancelOrders(_msgSender(), _orderIds, _orders);
  }

  function cancelOrdersIfSignatureMatch(
    uint8 _v,
    bytes32 _r,
    bytes32 _s,
    address _sender,
    uint _nonce,
    uint _deadline,
    uint[] calldata _orderIds,
    CancelOrder[] calldata _orders
  ) external {
    if (_orderIds.length != _orders.length) {
      revert LengthMismatch();
    }

    if (block.timestamp > _deadline) {
      revert DeadlineExpired(_deadline);
    }

    uint nonce = nonces[_sender];
    if (_nonce != nonce) {
      revert InvalidNonce(nonce, _nonce);
    }

    // encode all of the elements of each array
    bytes32[] memory hashedOrders = new bytes32[](_orders.length);
    for (uint i = 0; i < _orders.length; i++) {
      hashedOrders[i] = keccak256(
        abi.encode(CANCEL_ORDER_INFO_HASH, _orders[i].side, _orders[i].tokenId, _orders[i].price)
      );
    }

    // this is the signed data
    bytes32 hash = MessageHashUtils.toTypedDataHash(
      _getDomainSeparator("cancelOrders", VERSION, address(this)),
      keccak256(
        abi.encode(
          CANCEL_ORDERS_HASH,
          _sender,
          nonce,
          _deadline,
          keccak256(abi.encodePacked(_orderIds)),
          keccak256(abi.encodePacked(hashedOrders))
        )
      )
    );

    address recoveredAddress = hash.recover(_v, _r, _s);

    if (recoveredAddress != _sender || recoveredAddress == address(0)) {
      revert InvalidSignature(_sender, recoveredAddress);
    }

    nonces[_sender] = nonce.inc();

    _cancelOrders(_sender, _orderIds, _orders);
  }

  /// @dev calling function should check _orderIds.length != _orders.length
  function _cancelOrders(address _sender, uint[] calldata _orderIds, CancelOrder[] calldata _orders) private {
    uint brushFromUs = 0;
    uint nftsFromUs = 0;
    uint numberOfOrders = _orderIds.length;
    uint[] memory nftIdsFromUs = new uint[](numberOfOrders);
    uint[] memory nftAmountsFromUs = new uint[](numberOfOrders);
    for (uint i = 0; i < numberOfOrders; ++i) {
      CancelOrder calldata cancelOrder = _orders[i];
      (OrderSide side, uint tokenId, uint72 price) = (cancelOrder.side, cancelOrder.tokenId, cancelOrder.price);

      if (side == OrderSide.Buy) {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, bidValues[tokenId][price], bids[tokenId]);
        // Send the remaining token back to them
        brushFromUs += quantity * price;
      } else {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, askValues[tokenId][price], asks[tokenId]);
        // Send the remaining NFTs back to them
        nftIdsFromUs[nftsFromUs] = tokenId;
        nftAmountsFromUs[nftsFromUs] = quantity;
        nftsFromUs = nftsFromUs.inc();
      }
    }

    emit OrdersCancelled(_sender, _orderIds);

    // Transfer tokens if there are any to send
    if (brushFromUs != 0) {
      token.safeTransfer(_sender, brushFromUs);
    }

    // Send the NFTs
    if (nftsFromUs != 0) {
      // reset the size
      assembly ("memory-safe") {
        mstore(nftIdsFromUs, nftsFromUs)
        mstore(nftAmountsFromUs, nftsFromUs)
      }
      _safeBatchTransferNFTsFromUs(_sender, nftIdsFromUs, nftAmountsFromUs);
    }
  }

  /// @notice Claim NFTs associated with filled or partially filled orders.
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  function claimTokens(uint[] calldata _orderIds) public override {
    uint amount;
    for (uint i = 0; i < _orderIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      uint80 claimableAmount = brushClaimable[orderId];
      if (claimableAmount == 0) {
        revert NothingToClaim();
      }

      address maker = orderBookIdToMaker[orderId];
      if (maker != _msgSender()) {
        revert NotMaker();
      }
      amount += claimableAmount;
      brushClaimable[orderId] = 0;
    }

    if (amount == 0) {
      revert NothingToClaim();
    }

    (uint royalty, uint dev, uint burn) = _calcFees(amount);
    uint fees = royalty.add(dev).add(burn);
    uint amountExclFees = 0;
    if (amount > fees) {
      amountExclFees = amount.sub(fees);
    }

    emit ClaimedTokens(_msgSender(), _orderIds, amountExclFees);

    if (amountExclFees != 0) {
      token.safeTransfer(_msgSender(), amountExclFees);
    }
  }

  /// @notice Claim NFTs associated with filled or partially filled orders
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  /// @param _tokenIds Array of token IDs to claim NFTs for
  function claimNFTs(uint[] calldata _orderIds, uint[] calldata _tokenIds) public override {
    if (_orderIds.length != _tokenIds.length) {
      revert LengthMismatch();
    }

    uint[] memory nftAmountsFromUs = new uint[](_tokenIds.length);
    for (uint i = 0; i < _tokenIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      uint tokenId = _tokenIds[i];
      mapping(uint => uint) storage tokenIdsClaimableForOrder = tokenIdsClaimable[orderId];
      uint amount = tokenIdsClaimableForOrder[tokenId];
      if (amount == 0) {
        revert NothingToClaim();
      }
      nftAmountsFromUs[i] = amount;
      tokenIdsClaimableForOrder[tokenId] = 0;
    }

    emit ClaimedNFTs(_msgSender(), _orderIds, _tokenIds, nftAmountsFromUs);

    _safeBatchTransferNFTsFromUs(_msgSender(), _tokenIds, nftAmountsFromUs);
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
    claimTokens(_brushOrderIds);
    claimNFTs(_nftOrderIds, _tokenIds);
  }

  /// @notice Get the amount of tokens claimable for these orders
  /// @param _orderIds The order IDs to get the claimable tokens for
  /// @param takeAwayFees Whether to take away the fees from the claimable amount
  function tokensClaimable(
    uint40[] calldata _orderIds,
    bool takeAwayFees
  ) external view override returns (uint amount_) {
    for (uint i = 0; i < _orderIds.length; ++i) {
      amount_ += brushClaimable[_orderIds[i]];
    }
    if (takeAwayFees) {
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
      amounts_[i] = tokenIdsClaimable[_orderIds[i]][_tokenIds[i]];
    }
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

  /// @notice Get the tick size for a specific token ID
  /// @param _tokenId The token ID to get the tick size for
  function getTick(uint _tokenId) external view override returns (uint) {
    return tokenIdInfos[_tokenId].tick;
  }

  /// @notice The minimum amount that can be added to the order book for a specific token ID, to keep the order book healthy
  /// @param _tokenId The token ID to get the minimum quantity for
  function getMinAmount(uint _tokenId) external view override returns (uint) {
    return tokenIdInfos[_tokenId].minQuantity;
  }

  /// @notice Get all orders at a specific price level
  /// @param _side The side of the order book to get orders from
  /// @param _tokenId The token ID to get orders for
  /// @param _price The price level to get orders for
  function allOrdersAtPrice(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view override returns (OrderBookEntryHelper[] memory orderBookEntries) {
    if (_side == OrderSide.Buy) {
      return _allOrdersAtPriceSide(bidValues[_tokenId][_price], bids[_tokenId], _price);
    } else {
      return _allOrdersAtPriceSide(askValues[_tokenId][_price], asks[_tokenId], _price);
    }
  }

  /// @notice When the nft royalty changes this updates the fee and recipient. Assumes all token ids have the same royalty
  function updateRoyaltyFee() public {
    bool supportsERC2981 = nft.supportsInterface(type(IERC2981).interfaceId);
    if (supportsERC2981) {
      (address _royaltyRecipient, uint _royaltyFee) = IERC2981(address(nft)).royaltyInfo(1, 10000);
      royaltyRecipient = _royaltyRecipient;
      royaltyFee = uint16(_royaltyFee);
    }
  }

  /// @notice The maximum amount of orders allowed at a specific price level
  /// @param _maxOrdersPerPrice The new maximum amount of orders allowed at a specific price level
  function setMaxOrdersPerPrice(uint16 _maxOrdersPerPrice) public payable onlyOwner {
    maxOrdersPerPrice = _maxOrdersPerPrice;
    emit SetMaxOrdersPerPriceLevel(_maxOrdersPerPrice);
  }

  /// @notice Set constraints like minimum quantity of an order that is allowed to be
  ///         placed and the minimum of specific tokenIds in this nft collection.
  /// @param _tokenIds Array of token IDs for which to set TokenIdInfo
  /// @param _tokenIdInfos Array of TokenIdInfo to be set
  function setTokenIdInfos(uint[] calldata _tokenIds, TokenIdInfo[] calldata _tokenIdInfos) external payable onlyOwner {
    if (_tokenIds.length != _tokenIdInfos.length) {
      revert LengthMismatch();
    }

    for (uint i = 0; i < _tokenIds.length; ++i) {
      tokenIdInfos[_tokenIds[i]] = _tokenIdInfos[i];
    }

    emit SetTokenIdInfos(_tokenIds, _tokenIdInfos);
  }

  // TODO: editOrder

  function _getDomainSeparator(
    string memory _name,
    string memory _version,
    address _verifier
  ) private view returns (bytes32) {
    return
      keccak256(
        abi.encode(EIP712_DOMAIN_HASH, keccak256(bytes(_name)), keccak256(bytes(_version)), block.chainid, _verifier)
      );
  }

  function _buyTakeFromOrderBook(
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining_, uint cost_) {
    quantityRemaining_ = _quantity;

    // reset the size
    assembly ("memory-safe") {
      mstore(_orderIdsPool, MAX_ORDERS_HIT)
      mstore(_quantitiesPool, MAX_ORDERS_HIT)
    }

    uint numberOfOrders;
    while (quantityRemaining_ != 0) {
      uint72 lowestAsk = getLowestAsk(_tokenId);
      if (lowestAsk == 0 || lowestAsk > _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numSegmentsFullyConsumed = 0;
      bytes32[] storage lowestAskValues = askValues[_tokenId][lowestAsk];
      BokkyPooBahsRedBlackTreeLibrary.Node storage lowestAskNode = asks[_tokenId].getNode(lowestAsk);

      bool eatIntoLastOrder;
      uint initialOffset = lowestAskNode.getNumInSegmentDeleted();
      uint lastNumOrdersWithinSegmentConsumed = initialOffset;
      for (uint i = lowestAskNode.tombstoneOffset; i < lowestAskValues.length; ++i) {
        bytes32 packed = lowestAskValues[i];
        uint numOrdersWithinSegmentConsumed;
        bool wholeSegmentConsumed;
        for (uint offset = initialOffset; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
          uint40 orderId = uint40(uint(packed >> offset.mul(64)));
          if (orderId == 0 || quantityRemaining_ == 0) {
            // No more orders at this price level in this segment. If we are at the end
            if (orderId != 0) {
              wholeSegmentConsumed = false;
            }
            break;
          }
          uint24 quantityL3 = uint24(uint(packed >> (offset.mul(64).add(40))));
          uint quantityNFTClaimable = 0;
          if (quantityRemaining_ >= quantityL3) {
            // Consume this whole order
            quantityRemaining_ -= quantityL3;
            // Is the last one in the segment being fully consumed?
            wholeSegmentConsumed = offset == NUM_ORDERS_PER_SEGMENT.dec() || uint(packed >> offset.inc().mul(64)) == 0;
            numOrdersWithinSegmentConsumed = numOrdersWithinSegmentConsumed.inc();
            quantityNFTClaimable = quantityL3;
          } else {
            // Eat into the order
            packed = bytes32(
              (uint(packed) & ~(uint(0xffffff) << offset.mul(64).add(40))) |
                (uint(quantityL3 - quantityRemaining_) << offset.mul(64).add(40))
            );
            quantityNFTClaimable = quantityRemaining_;
            quantityRemaining_ = 0;
            eatIntoLastOrder = true;
          }
          cost_ += quantityNFTClaimable * lowestAsk;

          brushClaimable[orderId] += uint80(quantityNFTClaimable * lowestAsk);

          _orderIdsPool[numberOfOrders] = orderId;
          _quantitiesPool[numberOfOrders] = quantityNFTClaimable;
          numberOfOrders = numberOfOrders.inc();

          if (numberOfOrders >= MAX_ORDERS_HIT) {
            revert TooManyOrdersHit();
          }
        }

        if (wholeSegmentConsumed) {
          numSegmentsFullyConsumed = numSegmentsFullyConsumed.inc();
          lastNumOrdersWithinSegmentConsumed = 0;
        } else {
          lastNumOrdersWithinSegmentConsumed = uint8(
            lastNumOrdersWithinSegmentConsumed.add(numOrdersWithinSegmentConsumed)
          );
          if (eatIntoLastOrder) {
            // Update remaining order
            lowestAskValues[i] = packed;
            break;
          }
        }
        if (quantityRemaining_ == 0) {
          break;
        }
        initialOffset = 0; // So any further segments start at the beginning
      }

      if (numSegmentsFullyConsumed != 0 || lastNumOrdersWithinSegmentConsumed != 0) {
        uint tombstoneOffset = lowestAskNode.tombstoneOffset;
        asks[_tokenId].edit(lowestAsk, uint32(numSegmentsFullyConsumed), uint8(lastNumOrdersWithinSegmentConsumed));

        // We consumed all orders at this price level, so remove all
        if (numSegmentsFullyConsumed == lowestAskValues.length - tombstoneOffset) {
          asks[_tokenId].remove(lowestAsk); // TODO: A ranged delete would be nice
        }
      }
    }

    assembly ("memory-safe") {
      mstore(_orderIdsPool, numberOfOrders)
      mstore(_quantitiesPool, numberOfOrders)
    }

    emit OrdersMatched(_msgSender(), _orderIdsPool, _quantitiesPool);
  }

  function _sellTakeFromOrderBook(
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining_, uint cost_) {
    quantityRemaining_ = _quantity;

    // reset the size
    assembly ("memory-safe") {
      mstore(_orderIdsPool, MAX_ORDERS_HIT)
      mstore(_quantitiesPool, MAX_ORDERS_HIT)
    }
    uint numberOfOrders;
    while (quantityRemaining_ != 0) {
      uint72 highestBid = getHighestBid(_tokenId);
      if (highestBid == 0 || highestBid < _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numSegmentsFullyConsumed = 0;
      bytes32[] storage highestBidValues = bidValues[_tokenId][highestBid];
      BokkyPooBahsRedBlackTreeLibrary.Node storage highestBidNode = bids[_tokenId].getNode(highestBid);

      bool eatIntoLastOrder;
      uint initialOffset = highestBidNode.getNumInSegmentDeleted();
      uint lastNumOrdersWithinSegmentConsumed = initialOffset;
      uint highestBidValuesLength = highestBidValues.length;
      for (uint i = highestBidNode.tombstoneOffset; i < highestBidValuesLength; ++i) {
        bytes32 packed = highestBidValues[i];
        uint numOrdersWithinSegmentConsumed;
        bool wholeSegmentConsumed;
        for (uint offset = initialOffset; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
          uint40 orderId = uint40(uint(packed >> offset.mul(64)));
          if (orderId == 0 || quantityRemaining_ == 0) {
            // No more orders at this price level in this segment
            if (orderId != 0) {
              wholeSegmentConsumed = false;
            }
            break;
          }
          uint24 quantityL3 = uint24(uint(packed >> offset.mul(64).add(40)));
          uint quantityNFTClaimable = 0;
          if (quantityRemaining_ >= quantityL3) {
            // Consume this whole order
            quantityRemaining_ -= quantityL3;
            // Is the last one in the segment being fully consumed?
            wholeSegmentConsumed = offset == NUM_ORDERS_PER_SEGMENT.dec() || uint(packed >> offset.inc().mul(64)) == 0;
            numOrdersWithinSegmentConsumed = numOrdersWithinSegmentConsumed.inc();
            quantityNFTClaimable = quantityL3;
          } else {
            // Eat into the order
            packed = bytes32(
              (uint(packed) & ~(uint(0xffffff) << offset.mul(64).add(40))) |
                (uint(quantityL3 - quantityRemaining_) << offset.mul(64).add(40))
            );
            quantityNFTClaimable = quantityRemaining_;
            quantityRemaining_ = 0;
            eatIntoLastOrder = true;
          }
          cost_ += quantityNFTClaimable * highestBid;

          tokenIdsClaimable[orderId][_tokenId] += quantityNFTClaimable;

          _orderIdsPool[numberOfOrders] = orderId;
          _quantitiesPool[numberOfOrders] = quantityNFTClaimable;
          numberOfOrders = numberOfOrders.inc();

          if (numberOfOrders >= MAX_ORDERS_HIT) {
            revert TooManyOrdersHit();
          }
        }

        if (wholeSegmentConsumed) {
          numSegmentsFullyConsumed = numSegmentsFullyConsumed.inc();
          lastNumOrdersWithinSegmentConsumed = 0;
        } else {
          lastNumOrdersWithinSegmentConsumed = lastNumOrdersWithinSegmentConsumed.add(numOrdersWithinSegmentConsumed);
          if (eatIntoLastOrder) {
            // Update remaining order
            highestBidValues[i] = packed;
            break;
          }
        }
        if (quantityRemaining_ == 0) {
          break;
        }
        initialOffset = 0; // So any further segments start at the beginning
      }

      if (numSegmentsFullyConsumed != 0 || lastNumOrdersWithinSegmentConsumed != 0) {
        uint tombstoneOffset = highestBidNode.tombstoneOffset;
        bids[_tokenId].edit(highestBid, uint32(numSegmentsFullyConsumed), uint8(lastNumOrdersWithinSegmentConsumed));

        // We consumed all orders at this price level, so remove all
        if (numSegmentsFullyConsumed == highestBidValues.length - tombstoneOffset) {
          bids[_tokenId].remove(highestBid); // TODO: A ranged delete would be nice
        }
      }
    }

    assembly ("memory-safe") {
      mstore(_orderIdsPool, numberOfOrders)
      mstore(_quantitiesPool, numberOfOrders)
    }

    emit OrdersMatched(_msgSender(), _orderIdsPool, _quantitiesPool);
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
      (quantityRemaining, cost) = _buyTakeFromOrderBook(_tokenId, _price, _quantity, _orderIdsPool, _quantitiesPool);
    } else {
      (quantityRemaining, cost) = _sellTakeFromOrderBook(_tokenId, _price, _quantity, _orderIdsPool, _quantitiesPool);
    }
  }

  function _allOrdersAtPriceSide(
    bytes32[] storage packedOrderBookEntries,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price
  ) private view returns (OrderBookEntryHelper[] memory orderBookEntries_) {
    if (!_tree.exists(_price)) {
      return orderBookEntries_;
    }
    BokkyPooBahsRedBlackTreeLibrary.Node storage node = _tree.getNode(_price);
    uint tombstoneOffset = node.tombstoneOffset;
    uint numInSegmentDeleted = node.getNumInSegmentDeleted();
    orderBookEntries_ = new OrderBookEntryHelper[](
      (packedOrderBookEntries.length - tombstoneOffset) * NUM_ORDERS_PER_SEGMENT - numInSegmentDeleted
    );
    uint numberOfEntries;
    for (uint i = numInSegmentDeleted; i < orderBookEntries_.length.add(numInSegmentDeleted); ++i) {
      uint packed = uint(packedOrderBookEntries[i.div(NUM_ORDERS_PER_SEGMENT).add(tombstoneOffset)]);
      uint offset = i.mod(NUM_ORDERS_PER_SEGMENT);
      uint40 id = uint40(packed >> offset.mul(64));
      if (id != 0) {
        uint24 quantity = uint24(packed >> offset.mul(64).add(40));
        orderBookEntries_[numberOfEntries] = OrderBookEntryHelper(orderBookIdToMaker[id], quantity, id);
        numberOfEntries = numberOfEntries.inc();
      }
    }

    assembly ("memory-safe") {
      mstore(orderBookEntries_, numberOfEntries)
    }
  }

  function _cancelOrdersSide(
    uint _orderId,
    uint72 _price,
    bytes32[] storage _packedOrderBookEntries,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private returns (uint24 quantity_) {
    // Loop through all of them until we hit ours.
    if (!_tree.exists(_price)) {
      revert OrderNotFoundInTree(_orderId, _price);
    }

    BokkyPooBahsRedBlackTreeLibrary.Node storage node = _tree.getNode(_price);
    uint tombstoneOffset = node.tombstoneOffset;
    uint numInSegmentDeleted = node.getNumInSegmentDeleted();

    (uint index, uint offset) = _find(
      _packedOrderBookEntries,
      tombstoneOffset,
      _packedOrderBookEntries.length,
      _orderId
    );
    if (index == type(uint).max || (index == tombstoneOffset && offset < numInSegmentDeleted)) {
      revert OrderNotFound(_orderId, _price);
    }
    quantity_ = uint24(uint(_packedOrderBookEntries[index]) >> offset.mul(64).add(40));
    _cancelOrder(_packedOrderBookEntries, _price, index, offset, tombstoneOffset, _tree);
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

    TokenIdInfo storage tokenIdInfo = tokenIdInfos[_limitOrder.tokenId];
    uint128 tick = tokenIdInfo.tick;

    if (tick == 0) {
      revert TokenDoesntExist(_limitOrder.tokenId);
    }

    if (_limitOrder.price % tick != 0) {
      revert PriceNotMultipleOfTick(tick);
    }

    (quantityAddedToBook_, cost_) = _takeFromOrderBook(
      _limitOrder.side,
      _limitOrder.tokenId,
      _limitOrder.price,
      _limitOrder.quantity,
      _orderIdsPool,
      _quantitiesPool
    );

    // Add the rest to the order book if has the minimum required, in order to keep order books healthy
    if (quantityAddedToBook_ >= tokenIdInfo.minQuantity) {
      _addToBook(_newOrderId, tick, _limitOrder.side, _limitOrder.tokenId, _limitOrder.price, quantityAddedToBook_);
    } else {
      failedQuantity_ = quantityAddedToBook_;
      quantityAddedToBook_ = 0;
      emit FailedToAddToBook(_msgSender(), _limitOrder.side, _limitOrder.tokenId, _limitOrder.price, failedQuantity_);
    }
  }

  function _addToBookSide(
    mapping(uint price => bytes32[]) storage _packedOrdersPriceMap,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price,
    uint _orderId,
    uint _quantity,
    int128 _tickIncrement // -1 for buy, +1 for sell
  ) private returns (uint72 price_) {
    // Add to the bids section
    price_ = _price;
    if (!_tree.exists(price_)) {
      _tree.insert(price_);
    } else {
      uint tombstoneOffset = _tree.getNode(price_).tombstoneOffset;
      // Check if this would go over the max number of orders allowed at this price level
      bool lastSegmentFilled = uint(
        _packedOrdersPriceMap[price_][_packedOrdersPriceMap[price_].length.dec()] >>
          NUM_ORDERS_PER_SEGMENT.dec().mul(64)
      ) != 0;

      // Check if last segment is full
      if (
        (_packedOrdersPriceMap[price_].length.sub(tombstoneOffset)).mul(NUM_ORDERS_PER_SEGMENT) >= maxOrdersPerPrice &&
        lastSegmentFilled
      ) {
        // Loop until we find a suitable place to put this
        while (true) {
          price_ = uint72(uint128(int72(price_) + _tickIncrement));
          if (!_tree.exists(price_)) {
            _tree.insert(price_);
            break;
          } else if (
            (_packedOrdersPriceMap[price_].length.sub(tombstoneOffset)).mul(NUM_ORDERS_PER_SEGMENT) >=
            maxOrdersPerPrice &&
            uint(
              _packedOrdersPriceMap[price_][_packedOrdersPriceMap[price_].length.dec()] >>
                NUM_ORDERS_PER_SEGMENT.dec().mul(64)
            ) !=
            0
          ) {
            break;
          }
        }
      }
    }

    // Read last one. Decide if we can add to the existing segment or if we need to add a new segment
    bytes32[] storage packedOrders = _packedOrdersPriceMap[price_];
    bool pushToEnd = true;
    if (packedOrders.length != 0) {
      bytes32 lastPacked = packedOrders[packedOrders.length.dec()];
      // Are there are free entries in this segment
      for (uint i = 0; i < NUM_ORDERS_PER_SEGMENT; ++i) {
        uint orderId = uint40(uint(lastPacked >> (i.mul(64))));
        if (orderId == 0) {
          // Found one, so add to an existing segment
          bytes32 newPacked = lastPacked |
            (bytes32(_orderId) << (i.mul(64))) |
            (bytes32(_quantity) << (i.mul(64).add(40)));
          packedOrders[packedOrders.length.dec()] = newPacked;
          pushToEnd = false;
          break;
        }
      }
    }

    if (pushToEnd) {
      bytes32 packedOrder = bytes32(_orderId) | (bytes32(_quantity) << 40);
      packedOrders.push(packedOrder);
    }
  }

  function _addToBook(
    uint40 _newOrderId,
    uint128 tick,
    OrderSide _side,
    uint _tokenId,
    uint72 _price,
    uint24 _quantity
  ) private {
    orderBookIdToMaker[_newOrderId] = _msgSender();
    uint72 price;
    // Price can update if the price level is at capacity
    if (_side == OrderSide.Buy) {
      price = _addToBookSide(bidValues[_tokenId], bids[_tokenId], _price, _newOrderId, _quantity, -int128(tick));
    } else {
      price = _addToBookSide(askValues[_tokenId], asks[_tokenId], _price, _newOrderId, _quantity, int128(tick));
    }
    emit AddedToBook(_msgSender(), _side, _newOrderId, price, _quantity);
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
    bytes32[] storage packedData,
    uint begin,
    uint end,
    uint value
  ) private view returns (uint mid_, uint offset_) {
    while (begin < end) {
      mid_ = begin.add(end.sub(begin).div(2));
      uint packed = uint(packedData[mid_]);
      offset_ = 0;

      for (uint i = 0; i < NUM_ORDERS_PER_SEGMENT; ++i) {
        uint40 id = uint40(packed >> (offset_.mul(8)));
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

    return (type(uint).max, type(uint).max); // ID not found in any segment of the packed data
  }

  function _cancelOrder(
    bytes32[] storage orderBookEntries,
    uint72 _price,
    uint _index,
    uint _offset,
    uint _tombstoneOffset,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private {
    bytes32 packed = orderBookEntries[_index];
    uint40 orderId = uint40(uint(packed) >> _offset.mul(64));

    address maker = orderBookIdToMaker[orderId];
    if (maker == address(0) || maker != _msgSender()) {
      revert NotMaker();
    }

    if (_offset == 0 && packed >> 64 == bytes32(0)) {
      // Only 1 order in this segment, so remove the segment by shifting all other segments to the left.
      for (uint i = _index; i < orderBookEntries.length.sub(1); ++i) {
        orderBookEntries[i] = orderBookEntries[i.inc()];
      }
      orderBookEntries.pop();
      if (orderBookEntries.length - _tombstoneOffset == 0) {
        // Last one at this price level so trash it in the tree
        _tree.remove(_price);
      }
    } else {
      uint indexToRemove = _index * NUM_ORDERS_PER_SEGMENT + _offset;

      uint nextElementIndex = 0;
      uint nextOffsetIndex = 0;
      // Shift orders cross-segments.
      // This does all except the last order
      // TODO: For offset 0, 1, 2 we can shift the whole elements of the segment in 1 go.
      for (uint i = indexToRemove; i < orderBookEntries.length.mul(NUM_ORDERS_PER_SEGMENT).dec(); ++i) {
        nextElementIndex = (i.inc()) / NUM_ORDERS_PER_SEGMENT;
        nextOffsetIndex = (i.inc()) % NUM_ORDERS_PER_SEGMENT;

        bytes32 nextElement = orderBookEntries[nextElementIndex];

        uint currentElementIndex = i / NUM_ORDERS_PER_SEGMENT;
        uint currentOffsetIndex = i % NUM_ORDERS_PER_SEGMENT;

        bytes32 currentElement = orderBookEntries[currentElementIndex];

        uint newOrder = uint64(uint(nextElement >> nextOffsetIndex.mul(64)));
        if (newOrder == 0) {
          nextElementIndex = currentElementIndex;
          nextOffsetIndex = currentOffsetIndex;
          break;
        }

        // Clear the current order and set it with the shifted order
        currentElement &= _clearOrderMask(currentOffsetIndex);
        currentElement |= bytes32(newOrder) << currentOffsetIndex.mul(64);
        orderBookEntries[currentElementIndex] = currentElement;
      }
      if (nextOffsetIndex == 0) {
        orderBookEntries.pop();
      } else {
        // Clear the last element
        bytes32 lastElement = orderBookEntries[nextElementIndex];
        lastElement &= _clearOrderMask(nextOffsetIndex);
        orderBookEntries[nextElementIndex] = lastElement;
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
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
    // upgradeable by owner
  }
}
