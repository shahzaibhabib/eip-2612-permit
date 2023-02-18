// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./../src/MockToken.sol";
import "./../src/SigUtils.sol";

contract ERC20Test is Test {
    MockToken internal token;
    SigUtils internal sigUtils;

    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;

    address internal owner;
    address internal spender;

    function setUp() public {
        token = new MockToken();
        sigUtils = new SigUtils(token.getDomainSeparator());

        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);

        token.mint(owner, 1e18);
    }

    // testing permit
    function test_Permit() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        assertEq(token.allowance(owner, spender), 1e18);
        assertEq(token.nonces(owner), 1);
    }

    // testing failure for calls with an expired deadline, invalid signer, invalid nonce & signature replay
    function testRevert_ExpiredPermit() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: 1e18, nonce: token.nonces(owner), deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.warp(1 days + 1 seconds); // fast forward one second past the deadline

        vm.expectRevert("MockToken:: AUTH_EXPIRED");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_InvalidSigner() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: 1e18, nonce: token.nonces(owner), deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(spenderPrivateKey, digest); // spender signs owner's approval

        vm.expectRevert("MockToken:: INVALID_SIGNATURE");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_InvalidNonce() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 1, // owner nonce stored on-chain is 0
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert("MockToken:: INVALID_SIGNATURE");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_SignatureReplay() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert("MockToken:: INVALID_SIGNATURE");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    // testing transferfrom
    function test_TransferFromLimitedPermit() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: 1e18, nonce: 0, deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 1e18);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), 1e18);
        assertEq(token.allowance(owner, spender), 0);
    }

    function test_TransferFromMaxPermit() public {
        SigUtils.Permit memory permit =
            SigUtils.Permit({owner: owner, spender: spender, value: type(uint256).max, nonce: 0, deadline: 1 days});

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 1e18);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), 1e18);
        assertEq(token.allowance(owner, spender), type(uint256).max);
    }

    // testing failure for calls with and invalid allowance & balance
    function testFail_InvalidAllowance() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 5e17, // approve only 0.5 tokens
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 1e18); // attempt to transfer 1 token
    }

    function testFail_InvalidBalance() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 2e18, // approve 2 tokens
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 2e18); // attempt to transfer 2 tokens (owner only owns 1)
    }
}
