// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title Eip712SigUtils
 * @notice Shared EIP-712 digest builders for the SCC/SFC signature tests.
 * @dev One home for the EIP-2612 (permit) + ERC20Votes (delegateBySig) typehashes
 *      and the `\x19\x01` domain-wrapping, so the two token test suites can't drift
 *      apart on the (security-sensitive) digest math. The digest is returned — `vm.sign`
 *      stays in the test, which lets a test sign the SAME owner-bound digest with a
 *      DIFFERENT key (the wrong-signer / forged-signature case). Both builders read the
 *      token's live `DOMAIN_SEPARATOR()` + `nonces()`, so they work for SCC and SFC alike.
 */
abstract contract Eip712SigUtils is Test {
    /// @dev EIP-2612 (mirror of ERC20Permit's private constant).
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev ERC20Votes delegation (mirror of Votes' private constant).
    bytes32 internal constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice EIP-2612 permit digest for `owner` at the token's CURRENT nonce + domain separator.
    /// @dev Reads `nonces(owner)` so a freshly-built digest always targets the next valid nonce.
    function _permitDigest(address token, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        uint256 nonce = IERC20Permit(token).nonces(owner);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked(hex"1901", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
    }

    /// @notice ERC20Votes delegateBySig digest. `nonce` is explicit (it is a delegateBySig param
    ///         checked against the signer's current nonce by `_useCheckedNonce`).
    function _delegationDigest(address token, address delegatee, uint256 nonce, uint256 expiry)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        return keccak256(abi.encodePacked(hex"1901", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
    }
}
