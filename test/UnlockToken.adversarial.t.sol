// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {UnlockToken} from "src/UnlockToken.sol";

/// @notice Boundary and authorization cases that complement the original token suite.
/// forge-config: default.fuzz.runs = 1000
contract UnlockTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    UnlockToken internal token;
    address internal alice = makeAddr("adversarial-alice");
    address internal bob = makeAddr("adversarial-bob");
    address internal spender = makeAddr("adversarial-spender");

    function setUp() public {
        token = new UnlockToken();
    }

    function test_oneBaseUnitCanBeTransferredAndSpentWithoutRounding() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerNeedsSelfAllowanceForTransferFrom() public {
        assertTrue(token.transfer(alice, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_spenderCanReceiveTokensButCannotReuseExhaustedAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_infiniteAllowanceCanBeRevokedAndReplacedWithFiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(bob), 2);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalDoesNotBypassBalanceCheckAtUint256Maximum() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalBeforeFundingSurvivesFailedSpendAndWorksAfterFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_approvalDoesNotAuthorizeTheSameSpenderForAnotherOwner() public {
        assertTrue(token.transfer(alice, 2));
        assertTrue(token.transfer(bob, 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, alice, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 2);
    }

    function test_spenderCannotGiveItselfAnOwnersAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function testFuzz_selfTransferStillRequiresEnoughBalance(uint256 balance, uint256 extra) public {
        balance = bound(balance, 0, SUPPLY);
        extra = bound(extra, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        uint256 amount = balance + extra;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(alice, amount);

        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, alice, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalChangesOnlyTheOwnersChosenSpender(uint256 initial, uint256 replacement) public {
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(bob, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, replacement));
        // Approving twice is idempotent, including zero and unlimited approvals.
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
    }

    function testFuzz_failedZeroRecipientSpendPreservesFiniteAndInfiniteApprovals(uint256 amount, bool unlimited)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        // The failed call did not consume the authority needed for a valid retry.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : 0);
    }

    function test_approveZeroSpenderRejectsZeroAndMaximum() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromToZeroRecipientStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndLeavesApprovalsAlone(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedSpendingEqualsSingleSpend(uint256 first, uint256 second, uint256 approved) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        uint256 amount = first + second;
        approved = bound(approved, amount, type(uint256).max);
        UnlockToken single = new UnlockToken();
        assertTrue(single.approve(spender, approved));
        assertTrue(token.approve(spender, approved));

        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, second));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}
