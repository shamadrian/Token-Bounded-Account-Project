// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import { TBAWallet } from "../src/TBAWallet.sol";
import { ERC6551Registry } from "../lib/reference/src/ERC6551Registry.sol";
import { NFT } from "../src/NFT.sol";
import { EntryPoint } from "../lib/account-abstraction/contracts/core/EntryPoint.sol";

import "../lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

/*
    struct UserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
    }
*/

contract TBAWalletTest is Test {
    address user1;
    uint256 user1PrivateKey;
    address user2;
    uint256 user2PrivateKey;

    address constant registryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry registry = ERC6551Registry(registryAddress);

    address constant entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    EntryPoint entryPoint = EntryPoint(payable(entryPointAddress));

    NFT public nft;
    TBAWallet public tbaWalletBase;

    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    function setUp() public {
        //FORK ENVIRONMENT
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        //USERS SETUP
        (user1, user1PrivateKey) = makeAddrAndKey("user1");
        (user2, user2PrivateKey) = makeAddrAndKey("user2");
        deal(user1, 10 ether);
        deal(user2, 10 ether);

        //user1 ACTIONS
        vm.startPrank(user1);
        string memory uri = vm.envString("URI");
        nft = new NFT(uri);
        tbaWalletBase = new TBAWallet(entryPoint);
        vm.stopPrank();
    }

    function test_CreateWallet() public {
        //CREATE ACCOUNT
        address account = registry.account(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        vm.startPrank(user1);
        nft.mint(user1);
        vm.expectEmit();
        emit ERC6551AccountCreated(account, address(tbaWalletBase), bytes32(0), block.chainid, address(nft), 1);
        registry.createAccount(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        vm.stopPrank();

        TBAWallet tbaWallet = TBAWallet(payable(account));
        assertEq(tbaWallet.owner(), user1);
    }

    function test_OwnerExecute() public {
        //CREATE ACCOUNT
        address account = registry.account(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        vm.startPrank(user1);
        nft.mint(user1);
        registry.createAccount(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        TBAWallet tbaWallet = TBAWallet(payable(account));
        
        //USER1 SENDS ETHER TO ACCOUNT
        {
            (bool success, ) = account.call{value: 1 ether}("");
            require(success, "failed to send ether");
        }
        assertEq(address(tbaWallet).balance, 1 ether);

        //USER1 EXECUTES CALL FUNCTION TO SEND ETHER TO USER2
        tbaWallet.execute(user2, 1 ether, bytes(""), 0);
        assertEq(address(tbaWallet).balance, 0);
        assertEq(address(user2).balance, 11 ether);
        vm.stopPrank();
    }

    function test_EntryPointExecute() public {
        //CREATE ACCOUNT
        address account = registry.account(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        vm.startPrank(user1);
        nft.mint(user1);
        registry.createAccount(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
        TBAWallet tbaWallet = TBAWallet(payable(account));
        
        //USER1 SENDS ETHER TO ACCOUNT
        {
            (bool success, ) = account.call{value: 2 ether}("");
            require(success, "failed to send ether");
        }

        //INIT USER OPERATION
        UserOperation memory userOp;
        bytes memory signature;
        {
            bytes memory functionBytes = abi.encodeWithSignature("execute(address,uint256,bytes,uint8)", user2, 1 ether, bytes(""), 0);

            userOp = UserOperation({
                sender: account,
                nonce: 0,
                initCode: bytes(""),
                callData: functionBytes,
                callGasLimit: 260611,
                verificationGasLimit: 362451,
                preVerificationGas: 53576,
                maxFeePerGas: 29964445250,
                maxPriorityFeePerGas: 100000000, 
                paymasterAndData: bytes(""),
                signature: bytes("")
            });
        }

        //SIGN USER OPERATION WITH USER PRIAVTE KEY
        {
            bytes32 userOpHashReal = entryPoint.getUserOpHash(userOp);
            bytes32 message = keccak256(abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(userOpHashReal.length),
                userOpHashReal
            ));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, message);
            signature = abi.encodePacked(r, s, v);
            userOp.signature = signature;
        }

        //CALL HANDLE OPS
        {
            UserOperation[] memory input = new UserOperation[](1);
            input[0] = userOp;
            entryPoint.handleOps(input, payable(account));
        }
        assertEq(user2.balance, 11 ether);
        assertEq(user1.balance, 8 ether);
        console2.log("Account Balance = ", address(tbaWallet).balance);
    }
}