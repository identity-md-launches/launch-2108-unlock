// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnlockToken} from "../src/UnlockToken.sol";

/// @dev Stateful transfers and approvals across a closed set of holders.
contract TokenHandler is Test {
    UnlockToken public immutable token;
    address[4] public actors;

    constructor(UnlockToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 available = balance < allowanceBefore ? balance : allowanceBefore;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        uint256 expectedAllowance = allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount;
        assertEq(token.allowance(owner, spender), expectedAllowance);
    }
}

contract UnlockTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    UnlockToken internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new UnlockToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndAllBalancesAreAccountedFor() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
