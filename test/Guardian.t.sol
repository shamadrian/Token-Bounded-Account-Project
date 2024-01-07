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

    address guardian1;
    address guardian2;
    address guardian3;
    address guardian4;

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

    struct Recovery {
        uint approvalCount;
        uint startTime;
        mapping(address => bool) voted; 
    }

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

        {   //initialize guardians
            nft.setApprovalForAll(account, true);
            guardian1 = makeAddr("guardian1");
            guardian2 = makeAddr("guardian2");
            guardian3 = makeAddr("guardian3");
            guardian4 = makeAddr("guardian4");
            address[] memory guardians = new address[](3);
            guardians[0] = guardian1;
            guardians[1] = guardian2;
            guardians[2] = guardian3;
            tbaWallet.initializeGuardians(guardians, 2);
        }
        vm.stopPrank();
    }

    function test_initializeGuardians() public {
        assertEq(tbaWallet.getGuardianCount(), 3);
        assertEq(tbaWallet.getThreshhold(), 2);
        assertEq(tbaWallet.guardians(0, guardian1), true);
        assertEq(tbaWallet.guardians(0, guardian2), true);
        assertEq(tbaWallet.guardians(0, guardian3), true);
        assertEq(tbaWallet.guardianFlag(), true);
    }

    function test_addAndRemoveGuardian() public {
        vm.startPrank(user1);
        tbaWallet.addGuardian(guardian4, 3);
        assertEq(tbaWallet.getGuardianCount(), 4);
        assertEq(tbaWallet.getThreshhold(), 3);
        assertEq(tbaWallet.guardians(0, guardian4), true);
        tbaWallet.removeGuardian(guardian3, 2);
        assertEq(tbaWallet.getGuardianCount(), 3);
        assertEq(tbaWallet.getThreshhold(), 2);
        assertEq(tbaWallet.guardians(0, guardian3), false);
    }

    function test_setThreshhold() public {
        vm.startPrank(user1);
        tbaWallet.setThreshhold(3);
        assertEq(tbaWallet.getThreshhold(), 3);
        tbaWallet.setThreshhold(1);
        assertEq(tbaWallet.getThreshhold(), 1);
    }

    function test_ChangeOwner() public {
        {
            vm.startPrank(guardian1);
            tbaWallet.proposeChangeOwner(user2);
            (uint256 approvalCount, uint256 timestamp) = tbaWallet.recoveries(0, user2);
            assertEq(approvalCount, 1);
            assertEq(timestamp, block.timestamp);
            vm.stopPrank();
        }
        
        {
            vm.warp(2 minutes);
            vm.startPrank(guardian2);
            tbaWallet.voteChangeOwner(user2);
            (uint256 approvalCount, ) = tbaWallet.recoveries(0, user2);
            assertEq(approvalCount, 2);
            vm.stopPrank();
        }

        {
            vm.warp(2 minutes);
            vm.startPrank(guardian3);
            tbaWallet.executeChangeOwner(user2);
            assertEq(tbaWallet.owner(), user2);
            assertEq(tbaWallet.getGuardianCount(), 0);
            assertEq(tbaWallet.getThreshhold(), 0);
            assertEq(tbaWallet.guardianFlag(), false);
            assertEq(tbaWallet.ownerRecorded(), user2);
            assertEq(tbaWallet.counter(), 1);
        }
    }
}