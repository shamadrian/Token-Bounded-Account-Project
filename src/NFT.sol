// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFT is ERC721, Ownable{
    string public currURI;
    uint256 public tokenId = 1;

    constructor(string memory _uri) ERC721("TokenBoundedAccount", "TBA") Ownable(msg.sender) {
        currURI = _uri;
    }

    function mint(address to) public onlyOwner {
        _safeMint(to, tokenId);
        tokenId++;
    }

    function changeURI(string memory _uri) public onlyOwner {
        currURI = _uri;
    }

    function tokenURI(uint256 /*_tokenId */) public view override returns (string memory) {
        return currURI;
    }

    function burn(uint256 _tokenId) public onlyOwner {
        _burn(_tokenId);
    }
}
