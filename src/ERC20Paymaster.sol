// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BasePaymaster } from "../dependency/BasePaymaster.sol";
import "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "../lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20Paymaster is BasePaymaster {
    using SafeERC20 for ERC20;

    address constant USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    ERC20 USDC = ERC20(USDCAddress);

    //Aggregator: USDT / ETH
    //Address: 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46
    //Chain: Mainnet

    AggregatorV3Interface internal dataFeed;

    constructor(
        IEntryPoint _entryPoint, 
        address _dataFeed
    ) BasePaymaster(_entryPoint, msg.sender) {
        dataFeed = AggregatorV3Interface(_dataFeed);
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (uint256) {
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return uint256(answer);
    }

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 , uint256 maxCost)
    internal 
    override 
    returns (bytes memory context, uint256 validationData) {
        uint256 price = getChainlinkDataFeedLatestAnswer();
        uint256 tokenAmount = maxCost / price;
        require(USDC.balanceOf(userOp.sender) >= tokenAmount, "ERC20Paymaster: not enough USDT");
        require(USDC.allowance(userOp.sender, address(this)) >= tokenAmount, "ERC20Paymaster: not enough allowance");
        USDC.safeTransferFrom(userOp.sender, address(this), tokenAmount * 10 ** 6);
        context = abi.encodePacked(tokenAmount, userOp.sender);
        validationData = 0;
    }

    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost)
    internal
    override {
        if (mode == PostOpMode.postOpReverted) {
            return; // Do nothing here to not revert the whole bundle and harm reputation
        }

        address sender = address(bytes20(context[32:52]));
        uint256 tokenAmount = uint256(bytes32(context[0:32]));
        uint256 price = getChainlinkDataFeedLatestAnswer();
        uint256 actualTokenAmount = actualGasCost / price;
        USDC.safeTransfer(sender, (tokenAmount - actualTokenAmount) * 10 ** 6);
    }

    receive() external payable {}

    function withdrawToOwnerUSDC(address _to) external onlyOwner{
        USDC.safeTransfer(_to, USDC.balanceOf(address(this)));
    }

    function withdrawToOwnerETH(address _to) external onlyOwner{
        (bool success, ) = payable(_to).call{value: address(this).balance}("");
        require(success, "failed to send ether");
    }
}