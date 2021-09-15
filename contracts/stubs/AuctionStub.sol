// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "../Loans.sol";


struct AuctionItem {
    uint256 id;
    address owner;
    address nft;
    uint256 nftId;
    uint256 startPrice;
    uint256 winPrice;
}

contract AuctionStub is IAuction {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    mapping (uint256 /*id*/ => AuctionItem) internal _items;
    uint256 internal _nextId;

    // mapping (address /*nft*/ => mapping (uint256 /*nftId*/ => uint256 /*price*/)) internal _nfts;
    // mapping (address /*nft*/ => mapping (uint256 /*nftId*/ => uint256 /*winPrice*/)) internal _soldNfts;

    constructor(address _token) {
        require(_token != address(0), "ZERO_ADDRESS");
        token = IERC20(_token);
    }
    
    /** @notice Returns a token address used in auction. */
    function payableToken() public view override returns(address) {
        return address(token);
    }

    /** @notice Creates new auction. */
    function createAuction(address nft, uint256 nftId, uint256 startPrice) external override returns(uint256) {
        require(startPrice > 0, "ZERO_PRICE");
        
        uint256 id = _nextId++;
        AuctionItem storage item = _items[id];
        item.id = id;
        item.owner = msg.sender;
        item.nft = nft;
        item.nftId = nftId;
        item.startPrice = startPrice;

        IERC721(nft).transferFrom(msg.sender, address(this), nftId);
    }
    
    /** @notice Returns auction win price or 0 if auction isn't finished. */
    function getAuctionWinPrice(uint256 id) external view override returns(uint256 winPrice) {
        AuctionItem storage item = _items[id];
        require(item.owner != address(0), "AUCTION_NOT_EXISTS");
        return item.winPrice;
    }


    /** @notice Simulates finishing auction at specific price. */
    function _finishAuction(uint256 id, uint256 finalPrice) external {
        AuctionItem storage item = _items[id];
        require(item.owner != address(0), "AUCTION_NOT_EXISTS");
        require(item.winPrice == 0, "AUCTION_FINISHED");

        item.winPrice = finalPrice;

        token.safeTransferFrom(msg.sender, item.owner, finalPrice);
        IERC721(item.nft).transferFrom(address(this), msg.sender, item.nftId);
    }
}