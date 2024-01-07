// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract CantReceiveEther {
    receive() external payable {
        revert("Can't receive ether");
    }
}