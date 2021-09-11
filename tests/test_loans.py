import time

import brownie


def test_create_loan(loans, XToken, MatrixNFT, accounts, chain):
    user = accounts[1]
    
    # TODO: mint nft
    # TODO: ...