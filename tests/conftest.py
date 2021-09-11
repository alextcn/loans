import time

import pytest
from brownie import accounts, XToken, MatrixNFT, AuctionStub, Loans


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
def auction_stub(accounts, x_token):
    contract = AuctionStub.deploy(x_token.address, {'from': accounts[0]})
    return contract


@pytest.fixture
def loans(accounts, x_token, auction_stub):
    contract = Loans.deploy(x_token.address, auction_stub.address, {'from': accounts[0]})
    return contract