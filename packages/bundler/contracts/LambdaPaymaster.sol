// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

/* solhint-disable reason-string */
/* solhint-disable no-inline-assembly */

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/UserOperationLib.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "hardhat/console.sol";
/**
 * A sample paymaster that uses external service to decide whether to pay for the UserOp.
 * The paymaster trusts an external signer to sign the transaction.
 * The calling user must pass the UserOp to that external signer first, which performs
 * whatever off-chain verification before signing the UserOp.
 * Note that this signature is NOT a replacement for the account-specific signature:
 * - the paymaster checks a signature to agree to PAY for GAS.
 * - the account checks a signature to prove identity and account ownership.
 */
contract LambdaPaymaster is BasePaymaster {

    using UserOperationLib for PackedUserOperation;

    address public immutable verifyingSigner;

    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET;

    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + 64;

    struct Request {
        uint256 timestamp;
    }

    address TOKEN_ADDRESS;


    // 매핑: 주소별 요청 기록 저장
    mapping(address => Request[]) private requests;

    // 제한 상수
    uint256 constant TIME_LIMIT = 24 hours;
    uint256 constant MAX_REQUESTS = 3;

    constructor(IEntryPoint _entryPoint, address _verifyingSigner, address _tokenAddress) BasePaymaster(_entryPoint) {
        verifyingSigner = _verifyingSigner;
        TOKEN_ADDRESS = _tokenAddress;
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
    public view returns (bytes32) {
        //can't use userOp.hash(), since it contains also the paymasterAndData itself.
        address sender = userOp.getSender();
        return
            keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET : PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[20:84] : abi.encode(validUntil, validAfter)
     * paymasterAndData[84:] : signature
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 /*userOpHash*/, uint256 requiredPreFund)
    internal override returns (bytes memory context, uint256 validationData) {
        (requiredPreFund);
        console.log("start!! ");


        (uint48 validUntil, uint48 validAfter, bytes calldata signature) = parsePaymasterAndData(userOp.paymasterAndData);
        //ECDSA library supports both 64 and 65-byte long signatures.
        // we only "require" it here so that the revert reason on invalid signature will be of "VerifyingPaymaster", and not "ECDSA"


        require(signature.length == 64 || signature.length == 65, "VerifyingPaymaster: invalid signature length in paymasterAndData");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(getHash(userOp, validUntil, validAfter));
        console.log("verifyingSigner: ", verifyingSigner);
        console.log("ECDSA.recover(hash, signature): ", ECDSA.recover(hash, signature));
        //don't revert on signature failure: return SIG_VALIDATION_FAILED
        if (verifyingSigner != ECDSA.recover(hash, signature)) {
            //return ("", _packValidationData(true, validUntil, validAfter));
        }

        address to = address(bytes20(userOp.callData[16:36]));
        require(to == TOKEN_ADDRESS, "Invalid token address");

        // 현재 타임스탬프 가져오기
        uint256 currentTime = block.timestamp;

        // 해당 주소의 요청 배열 가져오기
        Request[] storage userRequests = requests[userOp.sender];

        // 오래된 요청 제거 (24시간 이전 요청)
        while (userRequests.length > 0 && currentTime - userRequests[0].timestamp >= TIME_LIMIT) {
            // 배열의 첫 번째 요소 제거
            for (uint i = 0; i < userRequests.length - 1; i++) {
                userRequests[i] = userRequests[i + 1];
            }
            userRequests.pop();
        }

        // 요청 수 확인: 24시간 내 요청이 MAX_REQUESTS 이상이면 에러 발생
        require(userRequests.length < MAX_REQUESTS, "Request limit exceeded");

        // 새로운 요청 추가
        userRequests.push(Request(currentTime));

        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return ("", _packValidationData(false, validUntil, validAfter));
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData) public pure returns (uint48 validUntil, uint48 validAfter, bytes calldata signature) {

        console.log("paymasterAndData: ", toHexString(paymasterAndData));

        (validUntil, validAfter) = abi.decode(paymasterAndData[VALID_TIMESTAMP_OFFSET :], (uint48, uint48));
        console.log("validUntil: ", validUntil);
        console.log("validAfter: ", validAfter);
        signature = paymasterAndData[SIGNATURE_OFFSET :];
    }

    function toHexString(bytes memory data) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(2 + data.length * 2);

        hexString[0] = "0";
        hexString[1] = "x";

        for (uint i = 0; i < data.length; i++) {
            hexString[2 + i * 2] = hexChars[uint8(data[i] >> 4)];
            hexString[3 + i * 2] = hexChars[uint8(data[i] & 0x0f)];
        }

        return string(hexString);
    }
}
