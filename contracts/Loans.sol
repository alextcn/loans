// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface IAuction {
    /** @notice Returns a token address used in auction. */
    function payableToken() external returns(address);

    /** @notice Creates new auction. */
    function createAuction(address nft, uint256 nftId, uint256 startPrice) external returns(uint256 id);
    
    /** @notice Returns auction win price or 0 if auction isn't finished. */
    function getAuctionWinPrice(uint256 id) external view returns(uint256 winPrice);
}

enum LoanStatus { Proposed, Cancelled, Started, Liquidating, Liquidated, Returned }

struct Loan {
    address creator;
    address nft;
    uint256 nftId;
    uint256 amount;
    LoanStatus status;
    EnumerableSet.AddressSet lenders;
    mapping(address /*lender*/ => uint256 /*loan*/) lenderLoans;
    uint32 rateNumerator;
    uint40 startTimestamp;  // time when loan's author claimed loan amount provided by lenders
    uint40 finishTimestamp; // time when loan is either cancelled, liquidated, or returned
    uint40 maxPeriod; // time in seconds given to creator to return a loan with interest
    uint256 auctionId;
}

contract Loans {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /** @notice Denominator of interested rate. */
    uint256 constant public LOAN_ANNUAL_RATE_DENOMINATOR = 10000;

    /** @notice A new loan proposal created. */
    event LoanProposalCreated(
        uint256 indexed loanId,
        address creator,
        address indexed nft,
        uint256 indexed nftId,
        uint256 loanAmount,
        uint32 rateNumerator,
        uint40 maxPeriod
    );

    /** @notice Loan proposal cancelled. */
    event LoanProposalCanceled(
        uint256 indexed loanId
    );

    /** @notice A lender accepted or updated offered tokens for proposed loan. */ 
    event LoanParticipationUpdated(
        uint256 indexed loanId, 
        address indexed lender, 
        uint256 amount
    );

    /** @notice A lender took his tokens back for proposed or cancelled loan. */ 
    event LoanParticipationCanceled(
        uint256 indexed loanId, 
        address indexed lender
    );

    /** @notice Loan's author claimed tokens loaned by lenders. */
    event LoanStarted(
        uint256 indexed loanId
    );

    /** @notice Loan's NFT collateral is placed on auction for liquidation. */
    event LoanLiquidationStarted(
        uint256 indexed loanId,
        address indexed nft,
        uint256 indexed nftId,
        uint256 auctionId,
        uint256 minPrice
    );

    /** @notice Loan has been liquidated on auction. */
    event LoanLiquidated(
        uint256 indexed loanId,
        uint256 liquidationPrice
    );

    /** @notice Loan's author returned tokens with interest and received NFT collateral back. */
    event LoanReturned(
        uint256 indexed loanId,
        uint256 amount
    );

    /** @notice A lender claimed his amount with interest on liquidated or returned loan. */
    event LoanedReturnClaimed(
        uint256 indexed loanId,
        address indexed lender,
        uint256 amount
    );

    /** @notice List of loans. */
    mapping (uint256 /*loanId*/ => Loan) internal _loans;
    /** @dev Loan id generator. */
    uint256 internal _nextLoanId;
    /** @notice A token used for payments, e.g. USDC. */
    IERC20 public immutable payableToken;
    /** @notice Auction contract used to liquidate NFT collateral of expired loans. */
    IAuction public immutable auction;
    
    /** @notice Reverts if loan doesn't exist. */
    modifier loanExists(uint256 id) {
        require(_loans[id].creator != address(0), "LOAN_NOT_EXISTS");
        _;
    }

    /** @notice Reverts if sender isn't loan's author. */
    modifier onlyAuthor(uint256 loanId) {
        require(_loans[loanId].creator == msg.sender, "NOT_LOAN_AUTHOR");
        _;
    }

    /** @notice Reverts if sender isn't loan's lender. */
    modifier onlyLender(uint256 loanId) {
        require(_loans[loanId].lenders.contains(msg.sender), "NOT_LOAN_LENDER");
        _;
    }

    /** @notice Returns loan. */
    function getLoan(uint256 loanId) loanExists(loanId) external view returns(
        address creator,
        address nft,
        uint256 nftId,
        uint256 amount,
        LoanStatus status,
        uint32 rateNumerator,
        uint40 startTimestamp,
        uint40 finishTimestamp,
        uint40 maxPeriod
    ) {
        Loan storage loan = _loans[loanId];
        return (loan.creator, loan.nft, loan.nftId, loan.amount, loan.status, loan.rateNumerator,
            loan.startTimestamp, loan.finishTimestamp, loan.maxPeriod);
    }

    /** @notice Return loan's lenders who has been yet claimed his loan back. */
    function getLoanLenders(uint256 loanId) loanExists(loanId) external view returns(address[] memory) {
        EnumerableSet.AddressSet storage lendersMap = _loans[loanId].lenders;
        address[] memory lenders = new address[](lendersMap.length());
        for (uint256 i = 0; i < lendersMap.length(); i++) {
            lenders[i] = lendersMap.at(i);
        }
        return lenders;
    }

    /** @notice Amount of lender's loan for not finished loan. */
    function getLoanLenderAmount(uint256 loanId, address lender) loanExists(loanId) external view returns(uint256) {
        return _loans[loanId].lenderLoans[lender];
    }

    /** @notice Returns loan's status. */
    function getLoanStatus(uint256 loanId) loanExists(loanId) external view returns(LoanStatus) {
        return _loans[loanId].status;
    }

    /** @notice Calculates loan amount with interest. */
    function calcAmountWithInterest(uint256 amount, uint32 rateNumerator) public pure returns(uint256 share) {
        return amount + amount * rateNumerator / LOAN_ANNUAL_RATE_DENOMINATOR;
    }

    constructor(
        address _payableToken,
        address _auction
    ) {
        require(_payableToken != address(0), "ZERO_ADDRESS");
        require(_auction != address(0), "ZERO_ADDRESS");
    
        IAuction iauction = IAuction(_auction);
        require(iauction.payableToken() == _payableToken, "TOKENS_DONT_MATCH");
        auction = iauction; // TODO: is there a better solution to read from contract in constructor?

        payableToken = IERC20(_payableToken);
    }


    /** @notice Create loan proposal to ask amount of tokens by giving NFT as a collateral. */
    function createLoanProposal(
        address nft, 
        uint256 nftId, 
        uint256 amount,
        uint32 rateNumerator,
        uint40 maxPeriod
    ) external {
        require(amount > 0, "INVALID_LOAN_PARAMS");

        uint256 loanId = _nextLoanId++;
        Loan storage loan = _loans[loanId];
        loan.creator = msg.sender;
        loan.nft = nft;
        loan.nftId = nftId;
        loan.rateNumerator = rateNumerator;
        loan.amount = amount;
        loan.maxPeriod = maxPeriod;

        IERC721(nft).transferFrom(msg.sender, address(this), nftId); // TODO: use safeTransferFrom?
        emit LoanProposalCreated(loanId, msg.sender, nft, nftId, amount, rateNumerator, maxPeriod);
    }

    /** 
     * @notice Cancels proposed loan.
     *
     * Loan should be in a Proposed status.
     * When loan is cancelled, lenders can manually claim their tokens back.
     */
    function cancelLoanProposal(uint256 loanId) loanExists(loanId) onlyAuthor(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Proposed, "ILLEGAL_LOAN_STATUS");
        loan.status = LoanStatus.Cancelled;
        loan.finishTimestamp = uint40(block.timestamp);
        IERC721(loan.nft).transferFrom(address(this), msg.sender, loan.nftId);  // TODO: use safeTransferFrom?
        emit LoanProposalCanceled(loanId);
    }


    /** 
     * @notice Provide tokens for proposed loan.
     *
     * Loan should be in Proposed status.
     * When amount fills loan amount, an author can claim loaned tokens by calling claimStartedLoanTokens.
     * Amount can't be 0 and can't exceed total loan's amount.
     * Can be called multiple times to update lending amount of tokens.
     */
    function updateProposalParticipation(uint256 loanId, uint256 amount) loanExists(loanId) external {
        require(amount > 0, "ZERO_AMOUNT");
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Proposed, "ILLEGAL_LOAN_STATUS");

        uint256 maxLoanAmount = loan.amount;
        uint256 totalLoanedAmount = _getCurrentLoanAmount(loan);
        
        if (!loan.lenders.contains(msg.sender)) {
            // add new lender's loan
            require(totalLoanedAmount + amount <= maxLoanAmount, "EXCEEDS_LOAN_AMOUNT");
            loan.lenders.add(msg.sender);
            loan.lenderLoans[msg.sender] = amount;
            payableToken.safeTransferFrom(msg.sender, address(this), amount);
            emit LoanParticipationUpdated(loanId, msg.sender, amount);
        } else {
            // update lender's loan
            uint256 oldAmount = loan.lenderLoans[msg.sender];
            require(oldAmount != amount, "SAME_AMOUNT");
            require(totalLoanedAmount - oldAmount + amount <= maxLoanAmount, "EXCEEDS_LOAN_AMOUNT");
            loan.lenderLoans[msg.sender] = amount;
            if (amount > oldAmount) {
                payableToken.safeTransferFrom(msg.sender, address(this), amount - oldAmount);
                emit LoanParticipationUpdated(loanId, msg.sender, amount - oldAmount);
            } else if (amount < oldAmount) {
                payableToken.safeTransfer(msg.sender, oldAmount - amount);
                emit LoanParticipationUpdated(loanId, msg.sender, oldAmount - amount);
            }
        }
    }

    /** 
     * @notice Calls by lenders to take all tokens back from proposed or cancelled loan.
     *
     * A loan should be in Proposal or Cancelled state.
     */
    function cancelProposalParticipation(uint256 loanId) loanExists(loanId) onlyLender(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Proposed || loan.status == LoanStatus.Cancelled, "ILLEGAL_LOAN_STATUS");

        uint256 loanedAmount = loan.lenderLoans[msg.sender];
        if (loanedAmount > 0) {
            payableToken.safeTransfer(msg.sender, loanedAmount);
        }

        loan.lenders.remove(msg.sender);
        delete loan.lenderLoans[msg.sender];
        emit LoanParticipationCanceled(loanId, msg.sender);
    }

    /** @notice Claim tokens of proposed loan by loan's author. Starts a loan. */
    function claimLoanedTokens(uint256 loanId) loanExists(loanId) onlyAuthor(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Proposed, "ILLEGAL_LOAN_STATUS");

        uint256 loanAmount = loan.amount;
        uint256 totalLoanedAmount = _getCurrentLoanAmount(loan);
        require(loanAmount == totalLoanedAmount, "NOT_ENOUGH_LOANED");

        loan.status = LoanStatus.Started;
        loan.startTimestamp = uint40(block.timestamp);
        payableToken.safeTransfer(msg.sender, loanAmount);
        emit LoanStarted(loanId);
    }

    /** @notice Return loaned tokens with interest and get NFT collateral back. */
    function returnLoan(uint256 loanId) loanExists(loanId) onlyAuthor(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Started, "ILLEGAL_LOAN_STATUS");

        loan.status = LoanStatus.Returned;
        loan.finishTimestamp = uint40(block.timestamp);

        uint256 returnAmount = calcAmountWithInterest(loan.amount, loan.rateNumerator);
        payableToken.safeTransferFrom(msg.sender, address(this), returnAmount);
        IERC721(loan.nft).safeTransferFrom(address(this), msg.sender, loan.nftId);
        emit LoanReturned(loanId, returnAmount);
    }

    /**
     * @notice Claim loaned tokens with interest by loan lender.
     *
     * Can only be called on liquidated or returned loan.
     */
    function claimLoanedReturns(uint256 loanId) loanExists(loanId) onlyLender(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Liquidated || loan.status == LoanStatus.Returned, "ILLEGAL_LOAN_STATUS");

        uint256 lenderAmount = loan.lenderLoans[msg.sender];

        loan.lenders.remove(msg.sender);
        delete loan.lenderLoans[msg.sender];

        uint256 returnAmount = calcAmountWithInterest(lenderAmount, loan.rateNumerator);
        if (returnAmount > 0) {
            payableToken.safeTransfer(msg.sender, returnAmount);
        }
        emit LoanedReturnClaimed(loanId, msg.sender, returnAmount);
    }

    /** 
     * @notice If loan hasn't been paid on time, this function can be called 
     * by any lender to liquidate collateral by placing a sell NFT order on auction.
     */
    function liquidateCollateral(uint256 loanId) loanExists(loanId) onlyLender(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Started, "ILLEGAL_LOAN_STATUS");
        require(block.timestamp > loan.startTimestamp + loan.maxPeriod, "LOAN_NOT_EXPIRED");

        address nft = loan.nft;
        uint256 nftId = loan.nftId;
        uint256 minPrice = calcAmountWithInterest(loan.amount, loan.rateNumerator);
        uint256 auctionId = auction.createAuction(nft, nftId, minPrice);

        loan.status = LoanStatus.Liquidating;
        loan.auctionId = auctionId;
        emit LoanLiquidationStarted(loanId, nft, nftId, auctionId, minPrice);
    }

    /** 
     * @notice Called on liquidating loan to check if NFT has been sold.
     * 
     * Can be called by anyone. A caller is rewarded by extra profit above required price.
     */
    function claimAuction(uint256 loanId) loanExists(loanId) external {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Liquidating, "ILLEGAL_LOAN_STATUS");

        uint256 liquidationPrice = auction.getAuctionWinPrice(loan.auctionId);
        if (liquidationPrice > 0) {
            // NFT has been sold, contract has tokens
            loan.status = LoanStatus.Liquidated;
            loan.finishTimestamp = uint40(block.timestamp);

            // send extra tokens to liquidator
            uint256 extraReward = liquidationPrice - loan.amount;
            if (extraReward > 0) {
                payableToken.transfer(msg.sender, extraReward);
            }
            emit LoanLiquidated(loanId, liquidationPrice);
        }
    }


    /**
     * @dev Calculates total amount lenders provived for a loan and not claimed yet.
     * 
     * If loan is cancelled, liquidated, or returned, the result doesn't
     * include amounts lenders already claimed.
     */
    function _getCurrentLoanAmount(Loan storage loan) private view returns(uint256 currentAmount) {
        for (uint256 i = 0; i < loan.lenders.length(); i++) {
            address lender = loan.lenders.at(i);
            uint256 lenderLoan = loan.lenderLoans[lender];
            currentAmount += lenderLoan;
        }
    }
}