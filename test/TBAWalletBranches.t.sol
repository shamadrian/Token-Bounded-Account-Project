// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import { TBAWallet } from "../src/TBAWallet.sol";
import { ERC6551Registry } from "../lib/reference/src/ERC6551Registry.sol";
import { NFT } from "../src/NFT.sol";
import { EntryPoint } from "../lib/account-abstraction/contracts/core/EntryPoint.sol";

import "../lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for ERC20;
import { ERC20Paymaster } from "../src/ERC20Paymaster.sol";

import { CantReceiveEther } from "../src/TestContract.sol";

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
    address paymasterOwner;

    address constant registryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry registry = ERC6551Registry(registryAddress);

    address constant entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    EntryPoint entryPoint = EntryPoint(payable(entryPointAddress));

    address constant USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    ERC20 USDC = ERC20(USDCAddress);

    NFT public nft;
    TBAWallet public tbaWalletBase;
    address account;
    TBAWallet public tbaWallet;
    ERC20Paymaster public paymaster;

    UserOperation userOp;
    bytes signature;

    CantReceiveEther cantReceiveEther;

    function setUp() public {
        //FORK ENVIRONMENT
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        //USERS SETUP
        (user1, user1PrivateKey) = makeAddrAndKey("user1");
        (user2, user2PrivateKey) = makeAddrAndKey("user2");
        paymasterOwner = makeAddr("paymasterOwner");
        deal(user1, 10 ether);
        deal(user2, 10 ether);
        deal(paymasterOwner, 10 ether);
        deal(USDCAddress, user1, 1000 * 10 ** 6);
        deal(USDCAddress, user2, 1000 * 10 ** 6);
        deal(USDCAddress, paymasterOwner, 1000 * 10 ** 6);

        //paymasterOwner ACTIONS
        vm.startPrank(paymasterOwner);
        paymaster = new ERC20Paymaster(entryPoint, address(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46));
        paymaster.deposit{value: 2 ether}();
        vm.stopPrank();

        //user1 ACTIONS
        vm.startPrank(user1);

        {   //Deploy NFT
            string memory uri = vm.envString("URI");
            nft = new NFT(uri);
        }

        {   //Setup TBA 
            tbaWalletBase = new TBAWallet(entryPoint);
            account = registry.account(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
            nft.mint(user1);
            registry.createAccount(address(tbaWalletBase), 0, block.chainid, address(nft), 1);
            tbaWallet = TBAWallet(payable(account));
        }

        {
            (bool success, ) = account.call{value: 2 ether}("");
            require(success, "failed to send ether");
            USDC.transfer(account, 1000 * 10 ** 6);
            tbaWallet.approveToken(USDCAddress, address(paymaster), 1000 * 10 ** 6);            
        }

        
        {
            bytes memory functionBytes = 
            abi.encodeWithSignature(
                "execute(address,uint256,bytes,uint8)", 
                USDCAddress, 
                0, 
                abi.encodeWithSignature("transfer(address,uint256)", user2, 100 * 10 ** 6), 
                0
            );

            bytes memory paymasterAndData = abi.encodePacked(address(paymaster));

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
                paymasterAndData: paymasterAndData,
                signature: bytes("")
            });
        }
        cantReceiveEther = new CantReceiveEther();
        vm.stopPrank();
    }

    function test_wrongSignature() public {
        //SIGN USER OPERATION WITH USER2 PRIAVTE KEY
        vm.startPrank(user2);
        {
            bytes32 userOpHashReal = entryPoint.getUserOpHash(userOp);
            bytes32 message = keccak256(abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(userOpHashReal.length),
                userOpHashReal
            ));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, message);
            signature = abi.encodePacked(r, s, v);
            userOp.signature = signature;
        }

        {
            UserOperation[] memory input = new UserOperation[](1);
            input[0] = userOp;
            vm.expectRevert();
            entryPoint.handleOps(input, payable(address(paymaster)));
        }
        vm.stopPrank();
    }

    function test_failCall() public {
        bytes memory functionBytes = 
            abi.encodeWithSignature(
                "execute(address,uint256,bytes,uint8)", 
                address(cantReceiveEther), 
                1 ether, 
                bytes(""), 
                0
            );

        userOp.callData = functionBytes;

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

        {
            UserOperation[] memory input = new UserOperation[](1);
            input[0] = userOp;
            entryPoint.handleOps(input, payable(address(paymaster)));
        }
    }

    function test_executeBranch() public {
        vm.startPrank(user1);
        vm.expectRevert("Only call operations are supported");
        tbaWallet.execute(user2, 0, bytes(""), 1);
        vm.expectRevert("Can't receive ether");
        tbaWallet.execute(address(cantReceiveEther), 1000, bytes(""), 0);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert();
        tbaWallet.execute(user2, 1 ether, bytes(""), 0);
    }

    function test_executeBatchBranch() public{
        vm.startPrank(user1);
        {
            address[] memory targets = new address[](2);
            targets[0] = user2;
            targets[1] = USDCAddress;
            uint256[] memory values = new uint256[](2);
            values[0] = 1 ether;
            values[1] = 0;
            uint256[] memory valuesWrong = new uint256[](3);
            valuesWrong[0] = 1 ether;
            valuesWrong[1] = 0;
            valuesWrong[2] = 0;
            bytes[] memory datas = new bytes[](2);
            datas[0] = bytes("");
            datas[1] = abi.encodeWithSignature("transfer(address,uint256)", user2, 100 * 10 ** 6);
            bytes[] memory dataWrong = new bytes[](3);
            dataWrong[0] = bytes("");
            dataWrong[1] = abi.encodeWithSignature("transfer(address,uint256)", user2, 100 * 10 ** 6);
            dataWrong[2] = bytes("");
            vm.expectRevert("wrong array lengths df");
            tbaWallet.executeBatch(targets, values, dataWrong);
            vm.expectRevert("wrong array lengths dv");
            tbaWallet.executeBatch(targets, valuesWrong, datas);

            vm.stopPrank();

            vm.startPrank(user2);
            vm.expectRevert();
            tbaWallet.executeBatch(targets, values, datas);
        }
        vm.stopPrank();
    }

    function test_approveTokenFail() public {
        vm.startPrank(user2);
        vm.expectRevert( "Only Owner can execute approveToken");
        tbaWallet.approveToken(USDCAddress, address(paymaster), 1000 * 10 ** 6);
        vm.stopPrank();
    }
}