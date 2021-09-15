import time

import brownie
from conftest import LoanStatus

# TODO: implement tests:
# [ ] test loan status
# [ ] test events
# [ ] test with getLoan()
# [ ] test calcAmountWithInterest()

def test_create_loan(loans, matrix_nft, accounts):
    creator = accounts[1]
    loanRate = 1500/10000 # 15%
    loanAmount = 100 * 10**18 # 100 tokens
    maxPeriod = 7 * 24 * 3600 # 1 week

    # can't create loan with non-existing nft
    with brownie.reverts('ERC721: operator query for nonexistent token'):
        tx = loans.createLoanProposal(matrix_nft.address, 123, loanAmount, loanRate, maxPeriod, { 'from': creator })

    # mint nft
    tx = matrix_nft.mintWithTokenURI("https://ipfs.io/ipfs/QmU84SmCFee2ekP7PWpr4zXaqf96jqLQ7oiDR7Qw8qSfiZ/metadata.json", {'from': creator})
    nft_id = tx.events['Transfer']['tokenId']
    assert matrix_nft.ownerOf(nft_id) == creator

    # can't create without approve
    with brownie.reverts('ERC721: operator query for nonexistent token'):
        tx = loans.createLoanProposal(matrix_nft.address, 123, loanAmount, loanRate, maxPeriod, { 'from': creator })

    # can create loan proposal
    tx = matrix_nft.approve(loans.address, nft_id, {'from': creator})
    tx = loans.createLoanProposal(matrix_nft.address, nft_id, loanAmount, loanRate, maxPeriod, { 'from': creator })
    loanId = tx.events['LoanProposalCreated']['loanId']
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Proposed.value


def test_cancel_empty_loan(loans, matrix_nft, accounts):
    creator = accounts[1]
    lender = accounts[2]
    loanRate = 1500/10000 # 15%
    loanAmount = 100 * 10**18 # 100 tokens
    maxPeriod = 7 * 24 * 3600 # 1 week

    # mint nft
    tx = matrix_nft.mintWithTokenURI("https://ipfs.io/ipfs/QmU84SmCFee2ekP7PWpr4zXaqf96jqLQ7oiDR7Qw8qSfiZ/metadata.json", {'from': creator})
    nft_id = tx.events['Transfer']['tokenId']
    assert matrix_nft.ownerOf(nft_id) == creator

    # create loan proposal
    tx = matrix_nft.approve(loans.address, nft_id, {'from': creator})
    tx = loans.createLoanProposal(matrix_nft.address, nft_id, loanAmount, loanRate, maxPeriod, { 'from': creator })
    loanId = tx.events['LoanProposalCreated']['loanId']
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == 0

    # can't cancel someone else
    with brownie.reverts('NOT_LOAN_AUTHOR'):
        loans.cancelLoanProposal(loanId, { 'from': lender })

    # cancel loan
    loans.cancelLoanProposal(loanId, { 'from': creator })
    assert matrix_nft.ownerOf(nft_id) == creator
    assert loans.getLoanStatus(loanId) == LoanStatus.Cancelled.value


def test_participation(loans, x_token, matrix_nft, accounts, chain):
    creator = accounts[1]
    lender = accounts[2]
    loanRate = 1500/10000 # 15%
    loanAmount = 100 * 10**18 # 100 tokens
    maxPeriod = 7 * 24 * 3600 # 1 week

    initCreatorBalance = x_token.balanceOf(creator)
    initLenderBalance = x_token.balanceOf(lender)

    # mint nft
    tx = matrix_nft.mintWithTokenURI("https://ipfs.io/ipfs/QmU84SmCFee2ekP7PWpr4zXaqf96jqLQ7oiDR7Qw8qSfiZ/metadata.json", {'from': creator})
    nft_id = tx.events['Transfer']['tokenId']
    assert matrix_nft.ownerOf(nft_id) == creator

    # can't participate in non-existing loan
    with brownie.reverts('LOAN_NOT_EXISTS'):
        loans.updateProposalParticipation(123, 1 * 10**18, { 'from': lender })

    # create loan proposal
    tx = matrix_nft.approve(loans.address, nft_id, {'from': creator})
    tx = loans.createLoanProposal(matrix_nft.address, nft_id, loanAmount, loanRate, maxPeriod, {'from': creator})
    loanId = tx.events['LoanProposalCreated']['loanId']
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Proposed.value
    assert loans.getLoanLenders(loanId) == []
    assert x_token.balanceOf(loans.address) == 0

    # reverts on exceeding amount
    with brownie.reverts('EXCEEDS_LOAN_AMOUNT'):
        loans.updateProposalParticipation(loanId, loanAmount + 1, { 'from': lender })

    # participate
    lendingAmount1 = 7 * 10**18 # 7 tokens
    x_token.approve(loans.address, lendingAmount1, {'from': lender})
    loans.updateProposalParticipation(loanId, lendingAmount1, {'from': lender})
    assert loans.getLoanLenders(loanId) == [lender]
    assert loans.getLoanLenderAmount(loanId, lender) == lendingAmount1
    assert x_token.balanceOf(lender) == initLenderBalance - lendingAmount1
    assert x_token.balanceOf(loans) == lendingAmount1

    # reverts on zero amount
    with brownie.reverts('ZERO_AMOUNT'):
        loans.updateProposalParticipation(loanId, 0, { 'from': lender })

    # reverts on same amount
    with brownie.reverts('SAME_AMOUNT'):
        loans.updateProposalParticipation(loanId, lendingAmount1, { 'from': lender })

    # reverts on exceeding amount on update
    with brownie.reverts('EXCEEDS_LOAN_AMOUNT'):
        loans.updateProposalParticipation(loanId, loanAmount + 1, { 'from': lender })

    # decrease amount
    lendingAmount2 = 3 * 10**18 # 3 tokens
    # x_token.approve(loans.address, lendingAmount1, {'from': lender})
    loans.updateProposalParticipation(loanId, lendingAmount2, {'from': lender})
    assert loans.getLoanLenders(loanId) == [lender]
    assert loans.getLoanLenderAmount(loanId, lender) == lendingAmount2
    assert x_token.balanceOf(lender) == initLenderBalance - lendingAmount2
    assert x_token.balanceOf(loans) == lendingAmount2

    # increase amount
    lendingAmount3 = 25 * 10**18 # 25 tokens
    x_token.approve(loans.address, lendingAmount3 - lendingAmount2, {'from': lender})
    loans.updateProposalParticipation(loanId, lendingAmount3, {'from': lender})
    assert loans.getLoanLenders(loanId) == [lender]
    assert loans.getLoanLenderAmount(loanId, lender) == lendingAmount3
    assert x_token.balanceOf(lender) == initLenderBalance - lendingAmount3
    assert x_token.balanceOf(loans) == lendingAmount3

    # cancel
    loans.cancelProposalParticipation(loanId, {'from': lender})
    assert loans.getLoanLenders(loanId) == []
    assert loans.getLoanLenderAmount(loanId, lender) == 0
    assert x_token.balanceOf(lender) == initLenderBalance
    assert x_token.balanceOf(loans) == 0

    # participate on full amount
    x_token.approve(loans.address, loanAmount, {'from': lender})
    loans.updateProposalParticipation(loanId, loanAmount, {'from': lender})
    assert loans.getLoanLenders(loanId) == [lender]
    assert loans.getLoanLenderAmount(loanId, lender) == loanAmount
    assert x_token.balanceOf(lender) == initLenderBalance - loanAmount
    assert x_token.balanceOf(loans) == loanAmount

    # start
    loans.claimLoanedTokens(loanId, {'from': creator})
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Started.value
    assert x_token.balanceOf(loans) == 0
    assert x_token.balanceOf(creator) == initCreatorBalance + loanAmount

    # can't participate in non-proposed loan
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.updateProposalParticipation(loanId, 1, {'from': lender})

    # can't cancel participation in non-proposed loan
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.cancelProposalParticipation(loanId, {'from': lender})


def test_start_return(loans, x_token, matrix_nft, accounts, chain):
    creator = accounts[1]
    lender1 = accounts[2]
    lender2 = accounts[3]
    loanRate = 1500 # 15%
    loanAmount = 100 * 10**18 # 100 tokens
    interestAmount = 15 * 10**18 # 15 tokens
    returnAmount = loanAmount + interestAmount
    # interestAmount = loanAmount * loanRate / loans.LOAN_ANNUAL_RATE_DENOMINATOR()
    maxPeriod = 7 * 24 * 3600 # 1 week

    initCreatorBalance = x_token.balanceOf(creator)
    initLender1Balance = x_token.balanceOf(lender1)
    initLender2Balance = x_token.balanceOf(lender2)

    # mint nft
    tx = matrix_nft.mintWithTokenURI("https://ipfs.io/ipfs/QmU84SmCFee2ekP7PWpr4zXaqf96jqLQ7oiDR7Qw8qSfiZ/metadata.json", {'from': creator})
    nft_id = tx.events['Transfer']['tokenId']
    assert matrix_nft.ownerOf(nft_id) == creator

    # create loan proposal
    tx = matrix_nft.approve(loans.address, nft_id, {'from': creator})
    tx = loans.createLoanProposal(matrix_nft.address, nft_id, loanAmount, loanRate, maxPeriod, {'from': creator})
    loanId = tx.events['LoanProposalCreated']['loanId']
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Proposed.value
    assert loans.getLoanLenders(loanId) == []
    assert x_token.balanceOf(loans.address) == 0

    # participate 1
    lendingAmount1 = 27 * 10**18
    x_token.approve(loans.address, lendingAmount1, {'from': lender1})
    loans.updateProposalParticipation(loanId, lendingAmount1, {'from': lender1})
    assert len(loans.getLoanLenders(loanId)) == 1
    assert loans.getLoanLenderAmount(loanId, lender1) == lendingAmount1
    assert x_token.balanceOf(lender1) == initLender1Balance - lendingAmount1
    assert x_token.balanceOf(loans) == lendingAmount1

    # participate 2
    lendingAmount2 = 73 * 10**18
    x_token.approve(loans.address, lendingAmount2, {'from': lender2})
    loans.updateProposalParticipation(loanId, lendingAmount2, {'from': lender2})
    assert len(loans.getLoanLenders(loanId)) == 2
    assert loans.getLoanLenderAmount(loanId, lender1) == lendingAmount1
    assert loans.getLoanLenderAmount(loanId, lender2) == lendingAmount2
    assert x_token.balanceOf(lender1) == initLender1Balance - lendingAmount1
    assert x_token.balanceOf(lender2) == initLender2Balance - lendingAmount2
    assert x_token.balanceOf(loans) == lendingAmount1 + lendingAmount2

    # start
    loans.claimLoanedTokens(loanId, {'from': creator})
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Started.value
    assert x_token.balanceOf(loans) == 0
    assert x_token.balanceOf(creator) == initCreatorBalance + loanAmount
    assert loans.calcAmountWithInterest(loanAmount, loanRate) == returnAmount

    # can't claim twice
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.claimLoanedTokens(loanId, {'from': creator})
    
    # can't cancel proposal once started
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.cancelLoanProposal(loanId, {'from': creator})

    # return loan with interest
    x_token.approve(loans.address, returnAmount, {'from': creator})
    loans.returnLoan(loanId, {'from': creator})
    assert matrix_nft.ownerOf(nft_id) == creator
    assert loans.getLoanStatus(loanId) == LoanStatus.Returned.value
    assert len(loans.getLoanLenders(loanId)) == 2
    assert loans.getLoanLenderAmount(loanId, lender1) == lendingAmount1
    assert loans.getLoanLenderAmount(loanId, lender2) == lendingAmount2
    assert x_token.balanceOf(loans) == returnAmount
    assert x_token.balanceOf(creator) == initCreatorBalance - interestAmount

    # claim by lender 1
    interestAmount1 = lendingAmount1 * loanRate / loans.LOAN_ANNUAL_RATE_DENOMINATOR()
    loans.claimLoanedReturns(loanId, {'from': lender1})
    assert matrix_nft.ownerOf(nft_id) == creator
    assert loans.getLoanStatus(loanId) == LoanStatus.Returned.value
    assert len(loans.getLoanLenders(loanId)) == 1
    assert loans.getLoanLenderAmount(loanId, lender1) == 0
    assert loans.getLoanLenderAmount(loanId, lender2) == lendingAmount2
    assert x_token.balanceOf(loans) == returnAmount - lendingAmount1 - interestAmount1
    assert x_token.balanceOf(creator) == initCreatorBalance - interestAmount
    assert x_token.balanceOf(lender1) == initLender1Balance + interestAmount1
    assert x_token.balanceOf(lender2) == initLender2Balance - lendingAmount2

    # claim by lender 2
    interestAmount2 = lendingAmount2 * loanRate / loans.LOAN_ANNUAL_RATE_DENOMINATOR()
    loans.claimLoanedReturns(loanId, {'from': lender2})
    assert matrix_nft.ownerOf(nft_id) == creator
    assert loans.getLoanStatus(loanId) == LoanStatus.Returned.value
    assert len(loans.getLoanLenders(loanId)) == 0
    assert loans.getLoanLenderAmount(loanId, lender1) == 0
    assert loans.getLoanLenderAmount(loanId, lender2) == 0
    assert x_token.balanceOf(loans) == returnAmount - lendingAmount1 - interestAmount1 - lendingAmount2 - interestAmount2
    assert x_token.balanceOf(creator) == initCreatorBalance - interestAmount
    assert x_token.balanceOf(lender1) == initLender1Balance + interestAmount1
    assert x_token.balanceOf(lender2) == initLender2Balance + interestAmount2


def test_liquidation(loans, auction, x_token, matrix_nft, accounts, chain):
    admin = accounts[0]
    creator = accounts[1]
    lender = accounts[2]
    liquidator = accounts[3]
    auctionWinner = accounts[4]
    loanRate = 1500 # 15%
    loanAmount = 100 * 10**18 # 100 tokens
    interestAmount = 15 * 10**18 # 15 tokens
    returnAmount = loanAmount + interestAmount # 115 tokens
    auctionWinPrice = 125 * 10**18 # 125 tokens
    liquidatorProfit = auctionWinPrice - returnAmount # 10 tokens
    maxPeriod = 7 * 24 * 3600 # 1 week

    x_token.transfer(auctionWinner, auctionWinPrice, {'from': admin})
    assert x_token.balanceOf(auctionWinner) >= auctionWinPrice # TODO: remove line

    initCreatorBalance = x_token.balanceOf(creator)
    initLenderBalance = x_token.balanceOf(lender)
    initLiquidatorBalance = x_token.balanceOf(liquidator)
    initAuctionWinnerBalance = x_token.balanceOf(auctionWinner)

    # mint nft
    tx = matrix_nft.mintWithTokenURI("https://ipfs.io/ipfs/QmU84SmCFee2ekP7PWpr4zXaqf96jqLQ7oiDR7Qw8qSfiZ/metadata.json", {'from': creator})
    nft_id = tx.events['Transfer']['tokenId']
    assert matrix_nft.ownerOf(nft_id) == creator

    # create loan proposal
    tx = matrix_nft.approve(loans.address, nft_id, {'from': creator})
    tx = loans.createLoanProposal(matrix_nft.address, nft_id, loanAmount, loanRate, maxPeriod, {'from': creator})
    loanId = tx.events['LoanProposalCreated']['loanId']
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Proposed.value
    assert loans.getLoanLenders(loanId) == []
    assert x_token.balanceOf(loans.address) == 0

    # participate
    x_token.approve(loans.address, loanAmount, {'from': lender})
    loans.updateProposalParticipation(loanId, loanAmount, {'from': lender})
    assert len(loans.getLoanLenders(loanId)) == 1
    assert loans.getLoanLenderAmount(loanId, lender) == loanAmount
    assert x_token.balanceOf(lender) == initLenderBalance - loanAmount
    assert x_token.balanceOf(loans) == loanAmount

    # start
    loans.claimLoanedTokens(loanId, {'from': creator})
    assert matrix_nft.ownerOf(nft_id) == loans.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Started.value
    assert x_token.balanceOf(loans) == 0
    assert x_token.balanceOf(creator) == initCreatorBalance + loanAmount
    assert loans.calcAmountWithInterest(loanAmount, loanRate) == returnAmount

    # fast forward in the middle of lending period
    chain.sleep(3600)
    chain.mine()

    # can't liquidate early
    with brownie.reverts('LOAN_NOT_EXPIRED'):
        loans.liquidateCollateral(loanId, {'from': lender})

    # fast forward after lending period
    chain.sleep(maxPeriod)
    chain.mine()

    # liquidate
    tx = loans.liquidateCollateral(loanId, {'from': lender})
    auctionId = tx.events['LoanLiquidationStarted']['auctionId']
    assert matrix_nft.ownerOf(nft_id) == auction.address
    assert loans.getLoanStatus(loanId) == LoanStatus.Liquidating.value
    assert auction.getAuctionWinPrice(auctionId) == 0

    # can't liquidate twice
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.liquidateCollateral(loanId, {'from': lender})

    # can't claim
    with brownie.reverts('AUCTION_NOT_FINISHED'):
        loans.claimAuction(loanId, {'from': liquidator})

    # finish auction
    x_token.approve(auction.address, auctionWinPrice, {'from': auctionWinner})
    auction._finishAuction(auctionId, auctionWinPrice, {'from': auctionWinner})
    assert auction.getAuctionWinPrice(auctionId) == auctionWinPrice
    assert matrix_nft.ownerOf(nft_id) == auctionWinner
    assert loans.getLoanStatus(loanId) == LoanStatus.Liquidating.value # still liquidating until claimAuction called
    assert x_token.balanceOf(loans) == auctionWinPrice
    assert x_token.balanceOf(auctionWinner) == initAuctionWinnerBalance - auctionWinPrice

    # lender can't claim before claimed
    with brownie.reverts('ILLEGAL_LOAN_STATUS'):
        loans.claimLoanedReturns(loanId, {'from': lender})
    
    # claim auction
    loans.claimAuction(loanId, {'from': liquidator})
    assert loans.getLoanStatus(loanId) == LoanStatus.Liquidated.value
    assert len(loans.getLoanLenders(loanId)) == 1
    assert loans.getLoanLenderAmount(loanId, lender) == loanAmount
    assert x_token.balanceOf(loans) == returnAmount
    assert x_token.balanceOf(creator) == initCreatorBalance + loanAmount
    assert x_token.balanceOf(lender) == initLenderBalance - loanAmount
    assert x_token.balanceOf(liquidator) == initLiquidatorBalance + liquidatorProfit

    # claim loaned tokens with interest
    loans.claimLoanedReturns(loanId, {'from': lender})
    assert loans.getLoanStatus(loanId) == LoanStatus.Liquidated.value
    assert len(loans.getLoanLenders(loanId)) == 0
    assert loans.getLoanLenderAmount(loanId, lender) == 0
    assert x_token.balanceOf(loans) == 0
    assert x_token.balanceOf(creator) == initCreatorBalance + loanAmount
    assert x_token.balanceOf(lender) == initLenderBalance + interestAmount
    assert x_token.balanceOf(liquidator) == initLiquidatorBalance + liquidatorProfit

    # can't claim again
    with brownie.reverts('NOT_LOAN_LENDER'):
        loans.claimLoanedReturns(loanId, {'from': lender})