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
    address guardian5;
    address guardian6;
    address guardian7;
    address guardian8;
    address guardian9;

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
            guardian5 = makeAddr("guardian5");
            guardian6 = makeAddr("guardian6");
            guardian7 = makeAddr("guardian7");
            guardian8 = makeAddr("guardian8");
            guardian9 = makeAddr("guardian9");
            address[] memory guardians = new address[](3);
            guardians[0] = guardian1;
            guardians[1] = guardian2;
            guardians[2] = guardian3;
            tbaWallet.initializeGuardians(guardians, 2);
        }
        vm.stopPrank();
    }

    function test_initializeGuardiansBranches() public {
        address[] memory guardians = new address[](3);
        guardians[0] = guardian1;
        guardians[1] = guardian2;
        guardians[2] = guardian3;

        vm.startPrank(user2);
        vm.expectRevert("Caller is not Owner");
        tbaWallet.initializeGuardians(guardians, 2);
        vm.stopPrank();

        vm.startPrank(user1);
        nft.setApprovalForAll(account, false);
        vm.expectRevert("TBA Wallet is not operator");
        tbaWallet.initializeGuardians(guardians, 2);
        nft.setApprovalForAll(account, true);
        address[] memory guardians2 = new address[](9);
        guardians2[0] = guardian1;
        guardians2[1] = guardian2;
        guardians2[2] = guardian3;
        guardians2[3] = guardian4;
        guardians2[4] = guardian5;
        guardians2[5] = guardian6;
        guardians2[6] = guardian7;
        guardians2[7] = guardian8;
        guardians2[8] = guardian9;
        vm.expectRevert("0 < Number of guardians < 9");
        tbaWallet.initializeGuardians(guardians2, 2);
        vm.expectRevert("0 < threshhold <= Number of guardians");
        tbaWallet.initializeGuardians(guardians, 4);
        vm.expectRevert("guardians already initialized");
        tbaWallet.initializeGuardians(guardians, 2);
        vm.stopPrank();
    }

    function test_addAndRemoveGuardianBranches() public {
        vm.startPrank(user2);
        vm.expectRevert("Caller is not Owner");
        tbaWallet.addGuardian(guardian4, 3);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("guardian already exists");
        tbaWallet.addGuardian(guardian3, 3);
        vm.expectRevert("guardian cannot be owner");
        tbaWallet.addGuardian(user1, 3);
        vm.expectRevert("threshhold must be less than or equal to the number of guardians");
        tbaWallet.addGuardian(guardian4, 5);
        tbaWallet.addGuardian(guardian4, 2);
        tbaWallet.addGuardian(guardian5, 3);
        tbaWallet.addGuardian(guardian6, 3);
        tbaWallet.addGuardian(guardian7, 4);
        tbaWallet.addGuardian(guardian8, 4);
        vm.expectRevert("guardian count must be less than 8");
        tbaWallet.addGuardian(guardian9, 4);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Caller is not Owner");
        tbaWallet.removeGuardian(guardian9, 4);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("guardian does not exist");
        tbaWallet.removeGuardian(guardian9, 4);
        vm.expectRevert("threshhold must be less than or equal to the number of guardians");
        tbaWallet.removeGuardian(guardian8, 9);
        vm.expectRevert("threshhold must be greater than 0");
        tbaWallet.removeGuardian(guardian8, 0);
        tbaWallet.removeGuardian(guardian8, 3);
        tbaWallet.removeGuardian(guardian7, 3);
        tbaWallet.removeGuardian(guardian6, 2);
        tbaWallet.removeGuardian(guardian5, 2);
        tbaWallet.removeGuardian(guardian4, 1);
        tbaWallet.removeGuardian(guardian3, 1);
        tbaWallet.removeGuardian(guardian2, 1);
        vm.expectRevert("threshhold must be 0 when removing last guardian");
        tbaWallet.removeGuardian(guardian1, 1);
        tbaWallet.removeGuardian(guardian1, 0);
        vm.stopPrank();
    }

    function test_setThreshholdBranches() public {
        vm.startPrank(user2);
        vm.expectRevert("Caller is not Owner");
        tbaWallet.setThreshhold(3);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("threshhold must be less than or equal to the number of guardians");
        tbaWallet.setThreshhold(4);
        vm.expectRevert("threshhold must be greater than 0");
        tbaWallet.setThreshhold(0);
        vm.stopPrank();
    }

    function test_ownerInconsistency() public {
        vm.startPrank(user2);
        vm.expectRevert("only guardian");
        tbaWallet.proposeChangeOwner(user2);
        vm.expectRevert("only guardian");
        tbaWallet.voteChangeOwner(user2);
        vm.expectRevert("only guardian");
        tbaWallet.executeChangeOwner(user2);
        vm.stopPrank();

        vm.startPrank(user1);
        nft.safeTransferFrom(user1, user2, 1);
        vm.stopPrank();

        vm.startPrank(guardian1);
        vm.expectRevert("owner mismatch");
        tbaWallet.proposeChangeOwner(user2);
        vm.expectRevert("owner mismatch");
        tbaWallet.voteChangeOwner(user2);
        vm.expectRevert("owner mismatch");
        tbaWallet.executeChangeOwner(user2);
    }

    function test_proposeChangeOwnerBranches() public {
        vm.startPrank(user1);
        nft.setApprovalForAll(account, false);
        vm.stopPrank();

        vm.startPrank(guardian1);
        vm.expectRevert("TBA Wallet is not operator");
        tbaWallet.proposeChangeOwner(user2);
        vm.expectRevert("TBA Wallet is not operator");
        tbaWallet.voteChangeOwner(user2);
        vm.expectRevert("TBA Wallet is not operator");
        tbaWallet.executeChangeOwner(user2);
        vm.stopPrank();

        vm.startPrank(user1);
        nft.setApprovalForAll(account, true);
        vm.stopPrank();

        vm.startPrank(guardian1);
        vm.expectRevert("valid = 1");
        tbaWallet.proposeChangeOwner(address(0));
        vm.expectRevert("valid = 2");
        tbaWallet.proposeChangeOwner(user1);
        vm.expectRevert("valid = 3");
        tbaWallet.proposeChangeOwner(guardian1);
        vm.expectRevert("valid = 4");
        tbaWallet.proposeChangeOwner(account);
        tbaWallet.proposeChangeOwner(user2);
        vm.expectRevert("_newOwner is currently an active proposal");
        tbaWallet.proposeChangeOwner(user2);
    }

    function test_voteChangeOwnerBranches() public {
        vm.startPrank(guardian1);
        tbaWallet.proposeChangeOwner(user2);
        vm.expectRevert("already voted");
        tbaWallet.voteChangeOwner(user2);
        vm.stopPrank();
        
        vm.startPrank(guardian2);
        vm.expectRevert("no recovery in progress");
        tbaWallet.voteChangeOwner(guardian4);
        vm.expectRevert("no recovery in progress");
        tbaWallet.executeChangeOwner(guardian4);
        vm.stopPrank();

        vm.startPrank(guardian3);
        vm.expectRevert("not enough votes");
        tbaWallet.executeChangeOwner(user2);
        vm.stopPrank();
    }
}