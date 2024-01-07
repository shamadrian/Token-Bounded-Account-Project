// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import { ERC4337Compatible } from "./ERC4337Compatible.sol";
import "../lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import "../lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { GuardianCompatible } from "./GuardianCompatible.sol";
import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

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

//---------------------------------------------------------------------------
//                            IERC6551 INTERFACES
//---------------------------------------------------------------------------

interface IERC6551Account {
    receive() external payable;

    function token()
        external
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId);

    function state() external view returns (uint256);

    function isValidSigner(address signer, bytes calldata context)
        external
        view
        returns (bytes4 magicValue);
}

interface IERC6551Executable {
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory);
}

//---------------------------------------------------------------------------
//                              ERC6551 CONTRACT
//---------------------------------------------------------------------------

contract TBAWallet is 
    IERC165, 
    IERC1271, 
    IERC6551Account, 
    IERC6551Executable,
    ERC4337Compatible,
    GuardianCompatible {
    using ECDSA for bytes32;

    //STORAGE
    uint256 public state;
    IEntryPoint private immutable _entryPoint;

    receive() external payable {}

    //---------------------------------------------------------------------------
    //                      ERC4337Compatible FUNCTIONS
    //---------------------------------------------------------------------------

    constructor (IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
    }

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner(), "account: not Owner or EntryPoint");
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(userOpHash.length), userOpHash));
        if (owner() != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        returns (bytes memory result)
    {
        _requireFromEntryPointOrOwner();
        require(operation == 0, "Only call operations are supported");

        ++state;

        _call(to, value, data);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "wrong array lengths df");
        require(dest.length == value.length, "wrong array lengths dv");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], value[i], func[i]);
        }
    }

    // ---------------------------------------------------------------------------
    //                                ERC6551 FUNCTIONS
    // ---------------------------------------------------------------------------    

    function _isValidSigner(address signer) internal view virtual returns (bool) {
        return signer == owner();
    }

    function isValidSigner(address signer, bytes calldata) external view virtual returns (bytes4) {
        if (_isValidSigner(signer)) {
            return IERC6551Account.isValidSigner.selector;
        }

        return bytes4(0);
    }

    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        virtual
        returns (bytes4 magicValue)
    {
        bool isValid = SignatureChecker.isValidSignatureNow(owner(), hash, signature);

        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return bytes4(0);
    }

    function token() public view virtual returns (uint256, address, uint256) {
        bytes memory footer = new bytes(0x60);

        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }

        return abi.decode(footer, (uint256, address, uint256));
    }

    function owner() public view virtual returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);

        return IERC721(tokenContract).ownerOf(tokenId);
    }

    // ---------------------------------------------------------------------------
    //                         GUARDIAN COMPATIBLE FUNCTIONS
    // ---------------------------------------------------------------------------

    function checkCallerIsOwner() internal override virtual {
        require(_isValidSigner(msg.sender), "Caller is not Owner");
    }

    function updateOwnerRecorded() internal override virtual {
        ownerRecorded = owner();
    }

    function checkIsOperator() internal override virtual {
        (uint256 chainId, address tokenContract, ) = token();
        require(chainId == block.chainid, "chainId mismatch");
        require(IERC721(tokenContract).isApprovedForAll(owner(), address(this)), "TBA Wallet is not operator");
    }

    function transferOwnership(address _newOwner) internal override virtual {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        require(chainId == block.chainid, "chainId mismatch");
        IERC721(tokenContract).transferFrom(owner(), _newOwner, tokenId);
    }

    function checkOwnerConsistency() internal override virtual {
        require(ownerRecorded == owner(), "owner mismatch");
    }

    // ---------------------------------------------------------------------------
    //                                OWNER FUNCTIONS
    // --------------------------------------------------------------------------- 
    function approveToken(address tokenAddress, address spender, uint256 amount) external {
        require(_isValidSigner(msg.sender), "Only Owner can execute approveToken");
        ERC20(tokenAddress).approve(spender, amount);
    }
}