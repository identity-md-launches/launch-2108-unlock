// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {UnlockToken} from "src/UnlockToken.sol";

/// @dev Closed holder set: only these four actors can send or receive during a campaign.
/// Ghost credits/debits come from successful call inputs, never from balanceOf; approvals
/// come from the owner's instructions, never from allowance. Rejected calls update neither.
contract UnlockAccountingHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    UnlockToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public credited;
    mapping(address => uint256) public debited;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public nonzeroTransfers;
    uint256 public nonzeroDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor() {
        token = new UnlockToken();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("accounting-holder-", vm.toString(i)));
            actors[i] = actor;
            assertTrue(token.transfer(actor, SUPPLY / actors.length));
            credited[actor] = SUPPLY / actors.length;
        }
        assertEq(token.balanceOf(address(this)), 0);
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return credited[actor] - debited[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, expectedBalance(from));
        _transfer(from, to, amount);
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        // Keep arbitrary uint256 approvals and deliberately revisit their semantic edges.
        uint8 choice = mode % 6;
        if (choice == 1) amount = 0;
        else if (choice == 2) amount = type(uint256).max;
        else if (choice == 3) amount = type(uint256).max - 1;
        else if (choice == 4) amount = SUPPLY;
        else if (choice == 5) amount = 1;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance(owner);
        if (approved < available) available = approved;
        amount = bound(amount, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordTransfer(owner, to, amount);
        if (amount != 0) ++nonzeroDelegatedTransfers;
    }

    function overdrawBalance(uint256 fromSeed, uint256 toSeed, uint256 extra) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        extra = bound(extra, 1, type(uint256).max - balance);
        uint256 amount = balance + extra;
        _reject(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function overdrawAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 seed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 approved = expectedAllowance[owner][spender];
        // Unlimited authority cannot be overdrawn: first replace it with a finite grant.
        if (approved == type(uint256).max) {
            approved = bound(seed, 0, SUPPLY);
            _approve(owner, spender, approved);
        }
        uint256 amount = approved + 1;
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
    }

    function delegatedOverdrawBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = balance + 1;
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = bound(amount, 0, expectedBalance(owner));
        bytes memory errorData = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            if (expectedAllowance[owner][spender] < amount) _approve(owner, spender, amount);
            _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), errorData);
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), errorData);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        if (amount != 0) ++nonzeroTransfers;
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        // Gross flows also account for from == to, whose net balance change must be zero.
        debited[from] += amount;
        credited[to] += amount;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) internal {
        // Catch only the token's expected rejection; an assertion failure must escape the
        // handler and fail the campaign (fail-on-revert is enabled below).
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        ++rejectedCalls;
    }
}

/// @notice Independent accounting and authorization checks after every random handler call.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract UnlockTokenAccountingInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    UnlockAccountingHandler internal handler;
    UnlockToken internal token;

    function setUp() public {
        handler = new UnlockAccountingHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = UnlockAccountingHandler.transfer.selector;
        selectors[1] = UnlockAccountingHandler.transferAll.selector;
        selectors[2] = UnlockAccountingHandler.approve.selector;
        selectors[3] = UnlockAccountingHandler.transferFrom.selector;
        selectors[4] = UnlockAccountingHandler.overdrawBalance.selector;
        selectors[5] = UnlockAccountingHandler.overdrawAllowance.selector;
        selectors[6] = UnlockAccountingHandler.delegatedOverdrawBalance.selector;
        selectors[7] = UnlockAccountingHandler.rejectZeroRecipient.selector;
        selectors[8] = UnlockAccountingHandler.rejectZeroSpender.selector;
        selectors[9] = UnlockAccountingHandler.revokeAndAttemptSpend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesMatchIndependentFlowsAndSupplyIsFixed() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor), "holder balance differs from authorized net flows");
            balances += actual;
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "UNLOCK");
        assertEq(token.symbol(), "UNLK");
        assertEq(token.decimals(), 18);
    }

    function invariant_allowancesMatchOwnerInstructionsAndSuccessfulSpends() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed outside its owner's grant or an authorized spend"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            assertEq(token.allowance(owner, address(handler)), 0);
        }
    }

    /// @dev Pin a productive sequence so a handler that only exercises zero transfers is
    /// not mistaken for useful stateful coverage. The random campaign still starts fresh.
    function test_handlerExercisesNonzeroDelegationAndExpectedRejections() public {
        handler.transfer(0, 1, 1);
        handler.transferAll(1, 2);
        handler.approve(2, 3, 7, 0);
        handler.transferFrom(2, 3, 0, 3);
        handler.overdrawBalance(0, 1, 1);
        handler.overdrawAllowance(2, 3, 0, 0);
        handler.delegatedOverdrawBalance(2, 3, 0, false);
        handler.delegatedOverdrawBalance(2, 3, 0, true);
        handler.rejectZeroRecipient(2, 3, 1, false);
        handler.rejectZeroRecipient(2, 3, 1, true);
        handler.rejectZeroSpender(2, 0);
        handler.revokeAndAttemptSpend(2, 3, 0);
        assertEq(handler.nonzeroTransfers(), 2);
        assertEq(handler.nonzeroDelegatedTransfers(), 1);
        assertEq(handler.rejectedCalls(), 8);
        invariant_balancesMatchIndependentFlowsAndSupplyIsFixed();
        invariant_allowancesMatchOwnerInstructionsAndSuccessfulSpends();
    }
}
