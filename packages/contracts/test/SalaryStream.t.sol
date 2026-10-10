// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SalaryStream} from "../src/SalaryStream.sol";

contract SalaryStreamTest is Test {
    SalaryStream public salaryStream;

    address public employer = address(0xA11CE);
    address public employee = address(0xB0B);
    address public attacker = address(0xBAD);

    uint256 public constant DEPOSIT = 1 ether;
    uint64 public constant DURATION = 3600;
    uint64 public constant CORRECTION_WINDOW = 60;

    uint256 public streamId;

    function setUp() public {
        salaryStream = new SalaryStream();

        vm.deal(employer, 100 ether);
        vm.deal(employee, 10 ether);
        vm.deal(attacker, 10 ether);

        vm.warp(1_000_000);

        vm.prank(employer);
        streamId = salaryStream.createStream{value: DEPOSIT}(employee, DURATION);
    }

    // ---------------------------------------------------------------
    // Stream creation
    // ---------------------------------------------------------------

    function testCreateStream() public view {
        (
            address storedEmployer,
            address storedEmployee,
            uint256 deposited,
            uint256 withdrawn,
            uint64 startTime,
            uint64 endTime,
            uint64 cancelledAt,
            bool cancelled
        ) = salaryStream.streams(streamId);

        assertEq(storedEmployer, employer);
        assertEq(storedEmployee, employee);
        assertEq(deposited, DEPOSIT);
        assertEq(withdrawn, 0);
        assertEq(uint256(startTime), block.timestamp + CORRECTION_WINDOW);
        assertEq(uint256(endTime), uint256(startTime) + DURATION);
        assertEq(cancelledAt, 0);
        assertFalse(cancelled);

        assertEq(address(salaryStream).balance, DEPOSIT);
        assertEq(salaryStream.nextStreamId(), 2);
    }

    function testRevertWhenEmployeeIsZeroAddress() public {
        vm.expectRevert(SalaryStream.InvalidEmployee.selector);
        vm.prank(employer);
        salaryStream.createStream{value: DEPOSIT}(address(0), DURATION);
    }

    function testRevertWhenEmployeeIsEmployer() public {
        vm.expectRevert(SalaryStream.InvalidEmployee.selector);
        vm.prank(employer);
        salaryStream.createStream{value: DEPOSIT}(employer, DURATION);
    }

    function testRevertWhenDepositIsZero() public {
        vm.expectRevert(SalaryStream.InvalidAmount.selector);
        vm.prank(employer);
        salaryStream.createStream{value: 0}(employee, DURATION);
    }

    function testRevertWhenDurationIsZero() public {
        vm.expectRevert(SalaryStream.InvalidDuration.selector);
        vm.prank(employer);
        salaryStream.createStream{value: DEPOSIT}(employee, 0);
    }

    // ---------------------------------------------------------------
    // Correction window
    // ---------------------------------------------------------------

    function testStreamStartsAfterCorrectionWindow() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        assertEq(uint256(startTime), block.timestamp + CORRECTION_WINDOW);

        assertEq(salaryStream.accrued(streamId), 0);
        assertEq(salaryStream.claimable(streamId), 0);
    }

    function testCannotWithdrawDuringCorrectionWindow() public {
        vm.expectRevert(SalaryStream.NothingToWithdraw.selector);
        vm.prank(employee);
        salaryStream.withdraw(streamId);
    }

    function testCancelDuringCorrectionWindowRefundsEntireDeposit() public {
        uint256 employerBalanceBefore = employer.balance;

        vm.prank(employer);
        salaryStream.cancel(streamId);

        assertEq(employer.balance, employerBalanceBefore + DEPOSIT);
        assertEq(address(salaryStream).balance, 0);
        assertEq(salaryStream.accrued(streamId), 0);
        assertEq(salaryStream.claimable(streamId), 0);

        (,,,,,, uint64 cancelledAt, bool cancelled) = salaryStream.streams(streamId);

        assertTrue(cancelled);
        assertEq(uint256(cancelledAt), block.timestamp);
    }

    function testCannotWithdrawAfterPendingStreamIsCancelled() public {
        vm.prank(employer);
        salaryStream.cancel(streamId);

        vm.expectRevert(SalaryStream.NothingToWithdraw.selector);
        vm.prank(employee);
        salaryStream.withdraw(streamId);
    }

    // ---------------------------------------------------------------
    // Accrual
    // ---------------------------------------------------------------

    function testNoAccrualBeforeStartTime() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) - 1);

        assertEq(salaryStream.accrued(streamId), 0);
        assertEq(salaryStream.claimable(streamId), 0);
    }

    function testAccrualAfterStartTime() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        // 1 MON streamed over 3600 seconds.
        // After 45 seconds, 0.0125 MON is earned.
        assertEq(salaryStream.accrued(streamId), 0.0125 ether);
        assertEq(salaryStream.claimable(streamId), 0.0125 ether);
    }

    function testAccrualReachesFullDepositAtEndTime() public {
        (,,,,, uint64 endTime,,) = salaryStream.streams(streamId);

        vm.warp(uint256(endTime));

        assertEq(salaryStream.accrued(streamId), DEPOSIT);
        assertEq(salaryStream.claimable(streamId), DEPOSIT);
    }

    function testAccrualDoesNotExceedDepositAfterEndTime() public {
        (,,,,, uint64 endTime,,) = salaryStream.streams(streamId);

        vm.warp(uint256(endTime) + 1 days);

        assertEq(salaryStream.accrued(streamId), DEPOSIT);
        assertEq(salaryStream.claimable(streamId), DEPOSIT);
    }

    // ---------------------------------------------------------------
    // Cancellation after streaming starts
    // ---------------------------------------------------------------

    function testCancelAfterStartRefundsUnearnedAmount() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        uint256 earned = salaryStream.accrued(streamId);
        uint256 expectedRefund = DEPOSIT - earned;
        uint256 employerBalanceBefore = employer.balance;

        vm.prank(employer);
        salaryStream.cancel(streamId);

        assertEq(earned, 0.0125 ether);
        assertEq(employer.balance, employerBalanceBefore + expectedRefund);
        assertEq(address(salaryStream).balance, earned);
        assertEq(salaryStream.accrued(streamId), earned);
        assertEq(salaryStream.claimable(streamId), earned);
    }

    function testAccrualIsFrozenAfterCancellation() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        uint256 earnedAtCancellation = salaryStream.accrued(streamId);

        vm.prank(employer);
        salaryStream.cancel(streamId);

        vm.warp(block.timestamp + 1 days);

        assertEq(salaryStream.accrued(streamId), earnedAtCancellation);
        assertEq(salaryStream.claimable(streamId), earnedAtCancellation);
    }

    function testEmployeeCanWithdrawEarnedSalaryAfterCancellation() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        uint256 earned = salaryStream.accrued(streamId);
        uint256 employeeBalanceBefore = employee.balance;

        vm.prank(employer);
        salaryStream.cancel(streamId);

        vm.prank(employee);
        salaryStream.withdraw(streamId);

        assertEq(employee.balance, employeeBalanceBefore + earned);
        assertEq(address(salaryStream).balance, 0);
        assertEq(salaryStream.claimable(streamId), 0);
    }

    function testCannotCancelTwice() public {
        vm.prank(employer);
        salaryStream.cancel(streamId);

        vm.expectRevert(SalaryStream.AlreadyCancelled.selector);
        vm.prank(employer);
        salaryStream.cancel(streamId);
    }

    // ---------------------------------------------------------------
    // Withdrawals and access control
    // ---------------------------------------------------------------

    function testEmployeeCanWithdrawAccruedSalary() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        uint256 earned = salaryStream.claimable(streamId);
        uint256 employeeBalanceBefore = employee.balance;

        vm.prank(employee);
        salaryStream.withdraw(streamId);

        assertEq(employee.balance, employeeBalanceBefore + earned);
        assertEq(salaryStream.claimable(streamId), 0);
    }

    function testCannotWithdrawTwiceWithoutNewAccrual() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        vm.prank(employee);
        salaryStream.withdraw(streamId);

        vm.expectRevert(SalaryStream.NothingToWithdraw.selector);
        vm.prank(employee);
        salaryStream.withdraw(streamId);
    }

    function testOnlyEmployerCanCancel() public {
        vm.expectRevert(SalaryStream.Unauthorized.selector);
        vm.prank(attacker);
        salaryStream.cancel(streamId);
    }

    function testOnlyEmployeeCanWithdraw() public {
        (,,,, uint64 startTime,,,) = salaryStream.streams(streamId);

        vm.warp(uint256(startTime) + 45);

        vm.expectRevert(SalaryStream.Unauthorized.selector);
        vm.prank(attacker);
        salaryStream.withdraw(streamId);
    }

    // ---------------------------------------------------------------
    // Unknown stream
    // ---------------------------------------------------------------

    function testRevertWhenAccruedStreamDoesNotExist() public {
        vm.expectRevert(SalaryStream.StreamNotFound.selector);
        salaryStream.accrued(999);
    }

    function testRevertWhenClaimableStreamDoesNotExist() public {
        vm.expectRevert(SalaryStream.StreamNotFound.selector);
        salaryStream.claimable(999);
    }

    function testRevertWhenCancellingUnknownStream() public {
        vm.expectRevert(SalaryStream.StreamNotFound.selector);
        vm.prank(employer);
        salaryStream.cancel(999);
    }

    function testRevertWhenWithdrawingFromUnknownStream() public {
        vm.expectRevert(SalaryStream.StreamNotFound.selector);
        vm.prank(employee);
        salaryStream.withdraw(999);
    }

    // ---------------------------------------------------------------
    // Fuzz test
    // ---------------------------------------------------------------

    function testFuzzAccrualNeverExceedsDeposit(uint64 durationInput, uint256 elapsedInput) public {
        uint64 duration = uint64(bound(durationInput, 1, 30 days));
        uint256 elapsed = bound(elapsedInput, 0, uint256(duration) + 1000);

        vm.prank(employer);
        uint256 id = salaryStream.createStream{value: DEPOSIT}(employee, duration);

        (,,,, uint64 startTime,,,) = salaryStream.streams(id);

        vm.warp(uint256(startTime) + elapsed);

        uint256 earned = salaryStream.accrued(id);

        assertLe(earned, DEPOSIT);
        assertLe(salaryStream.claimable(id), DEPOSIT);
    }
}
