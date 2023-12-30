// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import { AAWallet } from "src/AAWallet.sol";
import { EntryPoint } from "../lib/account-abstraction/contracts/core/EntryPoint.sol"; 
import "../lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import { AccountFactory } from "src/AccountFactory.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable state-visibility */

contract AAWalletTest is Test {
    address user;
    uint256 userPrivateKey;
    address payable sender;
    AccountFactory public accountFactory;
    AAWallet public aaWallet;

    //solhint-disable-next-line 
    address constant entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    EntryPoint entryPoint = EntryPoint(payable(entryPointAddress));

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

    function setUp() public {
        //FORK ENVIRONMENT
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        //USER ADDRESS & PRIVATE KEY
        (user, userPrivateKey) = makeAddrAndKey("user");

        //DEPLOY FACTORY
        vm.startPrank(user);
        accountFactory = new AccountFactory(entryPoint);
        sender = payable(accountFactory.getAddress(user, 0));
        vm.deal(sender, 1 ether);
        vm.stopPrank();
    }

    //solhint-disable-next-line
    function test_WalletCreation() public {
        vm.startPrank(user);
        UserOperation memory userOp;
        bytes memory signature;

        //INIT USER OPERATION
        {
            bytes memory functionBytes = abi.encodeWithSignature("createAccount(address,uint256)", user, 0);
            bytes memory initCode = abi.encodePacked(accountFactory, functionBytes);

            userOp = UserOperation({
                sender: sender,
                nonce: 0,
                initCode: initCode,
                callData: bytes(""),
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
            //solhint-disable-next-line
            console2.logBytes32(userOpHashReal);

            // bytes memory userOpPacked = abi.encodePacked(
            //     userOp.sender, 
            //     userOp.nonce, 
            //     keccak256(userOp.initCode), 
            //     keccak256(userOp.callData),
            //     userOp.callGasLimit, 
            //     userOp.verificationGasLimit, 
            //     userOp.preVerificationGas, 
            //     userOp.maxFeePerGas, 
            //     userOp.maxPriorityFeePerGas,
            //     keccak256(userOp.paymasterAndData)
            // );

            // bytes32 userOpHash = keccak256(userOpPacked);
            // console2.logBytes32(userOpHash);
            // bytes32 userOpHash2 = keccak256(abi.encode(userOpHash, entryPointAddress, block.chainid));
            // console2.logBytes32(userOpHash2);

            bytes32 message = keccak256(abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                Strings.toString(userOpHashReal.length),
                userOpHashReal
            ));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, message);
            signature = abi.encodePacked(r, s, v);
            userOp.signature = signature;
        }

        //CALL HANDLE OPS
        {
            UserOperation[] memory input = new UserOperation[](1);
            input[0] = userOp;
            entryPoint.handleOps(input, sender);
        }
    }
}
