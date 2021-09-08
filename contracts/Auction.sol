// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

pragma experimental ABIEncoderV2;

import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {AdminPausableUpgradeSafe} from './misc/AdminPausableUpgradeSafe.sol';


struct AuctionData {
    uint256 currentBid;
    address auctioneer;
    address currentBidder;
    uint40 endTimestamp;
}

library Errors {
  string public constant INVALID_AUCTION_PARAMS = 'INVALID_AUCTION_PARAMS';
  string public constant AUCTION_EXISTS = 'AUCTION_EXISTS';
  string public constant AUCTION_NOT_FINISHED = 'AUCTION_NOT_FINISHED';
  string public constant AUCTION_FINISHED = 'AUCTION_FINISHED';
  string public constant SMALL_BID_AMOUNT = 'SMALL_BID_AMOUNT';
  string public constant PAUSED = 'PAUSED';
  string public constant NO_RIGHTS = 'NO_RIGHTS';
  string public constant NOT_ADMIN = 'NOT_ADMIN';
  string public constant EMPTY_WINNER = 'EMPTY_WINNER';
  string public constant AUCTION_ALREADY_STARTED = 'AUCTION_ALREADY_STARTED';
  string public constant AUCTION_NOT_EXISTS = 'AUCTION_NOT_EXISTS';
  string public constant NFT_CONTRACT_IS_NOT_ALLOWED = 'NFT_CONTRACT_IS_NOT_ALLOWED';
  string public constant ZERO_ADDRESS = 'ZERO_ADDRESS';
}

/**
 * @dev Interface of extension of the ERC721 standard to allow `tokenAuthor` method.
 */
interface IERC721TokenAuthor {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function tokenAuthor(uint256 tokenId) external view returns(address);
}


/**
 * @dev Auction between NFT holders and participants.
 */
contract Auction is AdminPausableUpgradeSafe, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;

    mapping(address => mapping(uint256 => AuctionData)) public nftAuction2nftID2auction;
    uint256 public minPriceStepNumerator;
    uint256 constant MINIMUM_STEP_DENOMINATOR = 10000;
    uint256 constant MIN_MIN_PRICE_STEP_NUMERATOR = 1;  // 0.01%
    uint256 constant MAX_MIN_PRICE_STEP_NUMERATOR = 10000;  // 100%

    uint256 public authorRoyaltyNumerator;
    uint256 constant AUTHOR_ROYALTY_DENOMINATOR = 10000;

    uint40 public overtimeWindow;
    uint40 public auctionDuration;
    uint40 constant MAX_OVERTIME_WINDOW = 365 days;
    uint40 constant MIN_OVERTIME_WINDOW = 60;
    uint40 constant MAX_AUCTION_DURATION = 365 days;
    uint40 constant MIN_AUCTION_DURATION = 1 minutes;
    IERC20 public payableToken;
    IERC721 public allowedNFT;

    /**
     * @notice Emitted when a new auction is created.
     *
     * @param nft The NFT address of the token to auction.
     * @param nftId The NFT ID of the token to auction.
     * @param auctioneer The creator.
     * @param startPrice The auction's starting price.
     */
    event AuctionCreated(
        address indexed nft,
        uint256 indexed nftId,
        address indexed auctioneer,
        uint256 startPrice
    );

    /**
     * @notice Emitted when a royalty paid to an author.
     *
     * @param nft The NFT address of the token to auction.
     * @param nftId The NFT ID of the token to auction.
     * @param author The author.
     * @param amount The royalty amount.
     */
    event RoyaltyPaid(
        address indexed nft,
        uint256 indexed nftId,
        address indexed author,
        uint256 amount
    );

    /**
     * @notice Emitted when an auction is canceled.
     *
     * @param nft The NFT address of the token to auction.
     * @param nftId The NFT ID of the token to auction.
     * @param canceler Who canceled the auction.
     */
    event AuctionCanceled(
        address indexed nft,
        uint256 indexed nftId,
        address indexed canceler
    );

    /**
     * @notice Emitted when a new auction params are set.
     *
     * @param minPriceStepNumerator.
     */
    event MinPriceStepNumeratorSet(
        uint256 minPriceStepNumerator
    );

    /**
     * @notice Emitted when a new auction params are set.
     *
     * @param auctionDuration.
     */
    event AuctionDurationSet(
        uint40 auctionDuration
    );

    /**
     * @notice Emitted when a new auction params are set.
     *
     * @param overtimeWindow.
     */
    event OvertimeWindowSet(
        uint40 overtimeWindow
    );

    /**
     * @notice Emitted when a new auction params are set.
     *
     * @param authorRoyaltyNumerator.
     */
    event AuthorRoyaltyNumeratorSet(
        uint256 authorRoyaltyNumerator
    );

    /**
     * @notice Emitted when a new bid or outbid is created on a given NFT.
     *
     * @param nft The NFT address of the token bid on.
     * @param nftId The NFT ID of the token bid on.
     * @param bidder The bidder address.
     * @param amount The amount used to bid.
     * @param endTimestamp The new end timestamp.
     */
    event BidSubmitted(
        address indexed nft,
        uint256 indexed nftId,
        address indexed bidder,
        uint256 amount,
        uint40 endTimestamp
    );

    /**
     * @notice Emitted when an NFT is won and claimed.
     *
     * @param nft The NFT address of the token claimed.
     * @param nftId The NFT ID of the token claimed.
     * @param winner The winner of the NFT.
     * @param claimCaller Who called the claim method.
     */
    event WonNftClaimed(
        address indexed nft,
        uint256 indexed nftId,
        address indexed winner,
        address claimCaller
    );

    /**
     * @notice Emitted when auction reserve price changed.
     *
     * @param nft The NFT address of the token changed.
     * @param nftId The NFT ID of the token changed.
     * @param startPrice The new reserve price.
     * @param reservePriceChanger The caller of the method.
     */
    event ReservePriceChanged(
        address indexed nft,
        uint256 indexed nftId,
        uint256 startPrice,
        address indexed reservePriceChanger
    );

    function getPaused() external view returns(bool) {
        return _paused;
    }

    /**
     * @dev Initializes the contract.
     *
     * @param _overtimeWindow The overtime window,
     * triggers on bid `endTimestamp := max(endTimestamp, bid.timestamp + overtimeWindow)`
     * @param _auctionDuration The minimum auction duration.  (e.g. 24*3600)
     * @param _minStepNumerator The minimum auction price step. (e.g. 500 ~ 5% see `MINIMUM_STEP_DENOMINATOR`)
     * @param _payableToken The address of payable token.
     * @param _allowedNFT For now, the only one NFT is allowed.
     * @param _adminAddress The administrator address to set, allows pausing and editing settings.
     */
    function initialize(
        uint40 _overtimeWindow,
        uint40 _auctionDuration,
        uint256 _minStepNumerator,
        uint256 _authorRoyaltyNumerator,
        address _payableToken,
        address _allowedNFT,
        address _adminAddress
    ) external initializer {
        require(
            _adminAddress != address(0),
            Errors.ZERO_ADDRESS
        );
        require(
            _payableToken != address(0),
            Errors.ZERO_ADDRESS
        );
        require(
            _allowedNFT != address(0),
            Errors.ZERO_ADDRESS
        );
        _admin = _adminAddress;
        payableToken = IERC20(_payableToken);
        allowedNFT = IERC721(_allowedNFT);
        setAuctionDuration(_auctionDuration);
        setOvertimeWindow(_overtimeWindow);
        setMinPriceStepNumerator(_minStepNumerator);
        setAuthorRoyaltyNumerator(_authorRoyaltyNumerator);
    }

    /**
     * @dev Admin function to change the auction duration.
     *
     * @param newAuctionDuration The new minimum auction duration to set.
     */
    function setAuctionDuration(uint40 newAuctionDuration) public onlyAdmin {
        require(newAuctionDuration >= MIN_AUCTION_DURATION && newAuctionDuration <= MAX_AUCTION_DURATION,
            Errors.INVALID_AUCTION_PARAMS);
        auctionDuration = newAuctionDuration;
        emit AuctionDurationSet(newAuctionDuration);
    }

    /**
     * @dev Admin function to set the auction overtime window.
     *
     * @param newOvertimeWindow The new overtime window to set.
     */
    function setOvertimeWindow(uint40 newOvertimeWindow) public onlyAdmin {
        require(newOvertimeWindow >= MIN_OVERTIME_WINDOW && newOvertimeWindow <= MAX_OVERTIME_WINDOW,
            Errors.INVALID_AUCTION_PARAMS);
        overtimeWindow = newOvertimeWindow;
        emit OvertimeWindowSet(newOvertimeWindow);
    }

    /**
     * @dev Admin function to set the auction price step numerator.
     *
     * @param newMinPriceStepNumerator The new overtime window to set.
     */
    function setMinPriceStepNumerator(uint256 newMinPriceStepNumerator) public onlyAdmin {
        require(newMinPriceStepNumerator >= MIN_MIN_PRICE_STEP_NUMERATOR &&
                newMinPriceStepNumerator <= MAX_MIN_PRICE_STEP_NUMERATOR,
            Errors.INVALID_AUCTION_PARAMS);
        minPriceStepNumerator = newMinPriceStepNumerator;
        emit MinPriceStepNumeratorSet(newMinPriceStepNumerator);
    }

    /**
     * @dev Admin function to set author royalty numerator.
     *
     * @param newAuthorRoyaltyNumerator The new overtime window to set.
     */
    function setAuthorRoyaltyNumerator(uint256 newAuthorRoyaltyNumerator) public onlyAdmin {
        require(newAuthorRoyaltyNumerator <= AUTHOR_ROYALTY_DENOMINATOR, Errors.INVALID_AUCTION_PARAMS);
        authorRoyaltyNumerator = newAuthorRoyaltyNumerator;
        emit AuthorRoyaltyNumeratorSet(newAuthorRoyaltyNumerator);
    }

    /**
     * @dev Create new auction.
     *
     * @param nft Address of ERC721 NFT contract.
     * @param nftId Id of NFT token for the auction (must be approved for transfer by Auction smart-contract).
     * @param startPrice Minimum price for the first bid.
     */
    function createAuction(
        address nft,
        uint256 nftId,
        uint256 startPrice
    ) external nonReentrant whenNotPaused {
        require(nft == address(allowedNFT), Errors.NFT_CONTRACT_IS_NOT_ALLOWED);
        require(nftAuction2nftID2auction[nft][nftId].auctioneer == address(0), Errors.AUCTION_EXISTS);
        require(
            startPrice > 0,
            Errors.INVALID_AUCTION_PARAMS
        );
        AuctionData memory auctionData = AuctionData(
            startPrice,
            msg.sender,
            address(0),  // bidder
            0  // endTimestamp
        );
        nftAuction2nftID2auction[nft][nftId] = auctionData;
        IERC721(nft).transferFrom(msg.sender, address(this), nftId);  // maybe use safeTransferFrom
        emit AuctionCreated(nft, nftId, msg.sender, startPrice);
    }

    function stub() external pure returns(bytes4) {
        return type(IERC721TokenAuthor).interfaceId;
    }

    /**
     * @notice Claims a won NFT after an auction. Can be called by anyone.
     *
     * @param nft The NFT address of the token to claim.
     * @param nftId The NFT ID of the token to claim.
     */
    function claimWonNFT(address nft, uint256 nftId) external nonReentrant whenNotPaused {
        AuctionData storage auction = nftAuction2nftID2auction[nft][nftId];

        address auctioneer = auction.auctioneer;
        address winner = auction.currentBidder;
        uint256 endTimestamp = auction.endTimestamp;
        uint256 payToAuctioneer = auction.currentBid;

        require(block.timestamp > endTimestamp, Errors.AUCTION_NOT_FINISHED);
        require(winner != address(0), Errors.EMPTY_WINNER);  // auction does not exist or did not start, no bid

        delete nftAuction2nftID2auction[nft][nftId];
        emit WonNftClaimed(nft, nftId, winner, msg.sender);

        // the only one NFT we allow always supports this
//        if (IERC165(nft).supportsInterface(type(IERC721TokenAuthor).interfaceId)) {  // danger: external calls
//            address author = IERC721TokenAuthor(nft).tokenAuthor(nftId);
//            if (author != address(0) && author != auctioneer) {
//                uint256 payToAuthor = payToAuctioneer * authorRoyaltyNumerator / AUTHOR_ROYALTY_DENOMINATOR;
//                payToAuctioneer -= payToAuthor;
//                emit RoyaltyPaid(nft, nftId, author, payToAuthor);
//                payableToken.safeTransfer(author, payToAuthor);
//            }
//        }

        // warning will not work for usual erc721
        address author = IERC721TokenAuthor(nft).tokenAuthor(nftId);
//        if (author != address(0) && author != auctioneer) {
        if (author != auctioneer) {
            uint256 payToAuthor = payToAuctioneer * authorRoyaltyNumerator / AUTHOR_ROYALTY_DENOMINATOR;
            payToAuctioneer -= payToAuthor;
            emit RoyaltyPaid(nft, nftId, author, payToAuthor);
            payableToken.safeTransfer(author, payToAuthor);
        }

        payableToken.safeTransfer(auctioneer, payToAuctioneer);
        IERC721(nft).transferFrom(address(this), winner, nftId);  // maybe use safeTransfer (I don't want unclear onERC721Received stuff)
    }

    /**
     * @notice Returns the auction data for a given NFT.
     *
     * @param nft The NFT address to query.
     * @param nftId The NFT ID to query.
     *
     * @return The AuctionData containing all data related to a given NFT.
     */
    function getAuctionData(address nft, uint256 nftId)
    external
    view
    returns (AuctionData memory)
    {
        return nftAuction2nftID2auction[nft][nftId];
    }

    /**
     * @notice Cancel an auction. Can be called by the auctioneer or by the admin.
     *
     * @param nft The NFT address of the token to cancel.
     * @param nftId The NFT ID of the token to cancel.
     */
    function cancelAuction(
        address nft,
        uint256 nftId
    ) external whenNotPaused nonReentrant {
        AuctionData memory auction = nftAuction2nftID2auction[nft][nftId];
        require(
            auction.auctioneer != address(0),
            Errors.AUCTION_NOT_EXISTS
        );
        require(
            msg.sender == auction.auctioneer || msg.sender == _admin,
            Errors.NO_RIGHTS
        );
        require(
            auction.currentBidder == address(0),
            Errors.AUCTION_ALREADY_STARTED
        );  // auction can't be canceled if someone placed a bid.
        delete nftAuction2nftID2auction[nft][nftId];
        emit AuctionCanceled(nft, nftId, msg.sender);
        // maybe use safeTransfer (I don't want unclear onERC721Received stuff)
        IERC721(nft).transferFrom(address(this), auction.auctioneer, nftId);
    }

    /**
     * @notice Change the reserve price (minimum price) of the auction.
     *
     * @param nft The NFT address of the token.
     * @param nftId The NFT ID of the token.
     * @param startPrice New start price.
     */
    function changeReservePrice(
        address nft,
        uint256 nftId,
        uint256 startPrice
    ) external whenNotPaused nonReentrant {
        AuctionData memory auction = nftAuction2nftID2auction[nft][nftId];
        require(
            auction.auctioneer != address(0),
            Errors.AUCTION_NOT_EXISTS
        );
        require(
            msg.sender == auction.auctioneer || msg.sender == _admin,
            Errors.NO_RIGHTS
        );
        require(
            auction.currentBidder == address(0),
            Errors.AUCTION_ALREADY_STARTED
        );  // auction can't be canceled if someone placed a bid.
        require(
            startPrice > 0,
            Errors.INVALID_AUCTION_PARAMS
        );
        nftAuction2nftID2auction[nft][nftId].currentBid = startPrice;
        emit ReservePriceChanged(nft, nftId, startPrice, msg.sender);
    }

    /**
     * @notice Place the bid.
     *
     * @param nft The NFT address of the token.
     * @param nftId The NFT ID of the token.
     * @param amount Bid amount.
     */
    function bid(
        address nft,
        uint256 nftId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        AuctionData storage auction = nftAuction2nftID2auction[nft][nftId];
        require(auction.auctioneer != address(0), Errors.AUCTION_NOT_EXISTS);
        uint256 currentBid = auction.currentBid;
        address currentBidder = auction.currentBidder;
        uint40 endTimestamp = auction.endTimestamp;

        require(
            block.timestamp < endTimestamp || endTimestamp == 0,
            Errors.AUCTION_FINISHED
        );

        uint40 newEndTimestamp = auction.endTimestamp;
        if (endTimestamp == 0) { // first bid
            require(amount >= currentBid, Errors.SMALL_BID_AMOUNT);  // >= startPrice stored in currentBid
            newEndTimestamp = uint40(block.timestamp) + auctionDuration;
            auction.endTimestamp = newEndTimestamp;
        } else {
            require(amount >= (MINIMUM_STEP_DENOMINATOR + minPriceStepNumerator) * currentBid / MINIMUM_STEP_DENOMINATOR,
                Errors.SMALL_BID_AMOUNT);  // >= step over the previous bid
//            if (overtimeWindow > 0 && block.timestamp > endTimestamp - overtimeWindow) {
            if (block.timestamp > endTimestamp - overtimeWindow) {
                newEndTimestamp = uint40(block.timestamp) + overtimeWindow;
                auction.endTimestamp = newEndTimestamp;
            }
        }

        auction.currentBidder = msg.sender;
        auction.currentBid = amount;

        if (currentBidder != msg.sender) {
            if (currentBidder != address(0)) {
                 payableToken.safeTransfer(currentBidder, currentBid);
            }
            payableToken.safeTransferFrom(msg.sender, address(this), amount);
        } else {
            uint256 more = amount - currentBid;
            payableToken.safeTransferFrom(msg.sender, address(this), more);
        }

        emit BidSubmitted(nft, nftId, msg.sender, amount, newEndTimestamp);
    }

    function getRevision() external pure returns(uint256) {
        return 7;
    }
    uint256[50] private __gap;
}
