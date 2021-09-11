// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";


contract MatrixNFT is ERC721, ERC721Enumerable, ERC721URIStorage {
    uint256 public nextTokenId = 0;

    constructor() ERC721("NatrixNFT", "MNFT") {}

    function mintWithTokenURI(string memory _tokenURI) public returns (uint256) {
        require(bytes(_tokenURI).length > 0, "EMPTY_METADATA");
        uint256 tokenId = nextTokenId++;
        _mintWithTokenURI(_msgSender(), tokenId, _tokenURI);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view override (ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _mintWithTokenURI(address to, uint256 tokenId, string memory _tokenURI) internal virtual {
        _mint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
    }

    function _mint(address to, uint256 tokenId) internal override {
        super._mint(to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
