import time
from enum import Enum

import pytest
from brownie import accounts, XToken, MatrixNFT, AuctionStub, Loans


class LoanStatus(Enum):
    Proposed = 0
    Cancelled = 1
    Started = 2
    Liquidating = 3
    Liquidated = 4
    Returned = 5

@pytest.fixture
def x_token(accounts):
    token = XToken.deploy(1000000*1e18, {'from': accounts[0]})
    for account in accounts[1:]:
        token.transfer(account, 100*1e18, {'from': accounts[0]})
    return token


@pytest.fixture
def matrix_nft(accounts):
    contract = MatrixNFT.deploy({'from': accounts[0]})
    return contract


@pytest.fixture
def auction(accounts, x_token):
    contract = AuctionStub.deploy(x_token.address, {'from': accounts[0]})
    return contract


@pytest.fixture
def loans(accounts, x_token, auction):
    contract = Loans.deploy(x_token.address, auction.address, {'from': accounts[0]})
    return contract