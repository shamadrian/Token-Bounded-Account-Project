// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import { NFT } from "src/NFT.sol";

contract NFTScript is Script {
    NFT public nft;
    address public owner;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        owner  = vm.addr(privateKey);
        string memory uri = vm.envString("URI");
        vm.startBroadcast(privateKey);
        nft = new NFT(uri);
        nft.mint(owner);
    }
}

//forge script script/NFT.s.sol:NFTScript --fork-url $SEPOLIA_RPC_URL 
//forge script script/NFT.s.sol:NFTScript --fork-url $SEPOLIA_RPC_URL --etherscan-api-key $API_KEY --broadcast --verify
//NFT: 0x8c77Dd29af65800c53527762906947b012152ec1