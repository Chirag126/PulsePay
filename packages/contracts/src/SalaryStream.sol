// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SalaryStream is ReentrancyGuard {
    uint64 public constant CORRECTION_WINDOW = 60;

    uint256 public nextStreamId = 1;

    struct Stream {
        address employer;
        address employee;
        uint256 deposited;
        uint256 withdrawn;
        uint64 startTime;
        uint64 endTime;
        uint64 cancelledAt;
        bool cancelled;
    }

    mapping(uint256 => Stream) public streams;

    event StreamCreated(
        uint256 indexed streamId,
        address indexed employer,
        address indexed employee,
        uint256 amount,
        uint64 startTime,
        uint64 endTime
    );

    event SalaryWithdrawn(uint256 indexed streamId, address indexed employee, uint256 amount);

    event StreamCancelled(uint256 indexed streamId, uint256 refund);

    error InvalidEmployee();
    error InvalidAmount();
    error InvalidDuration();
    error StreamNotFound();
    error Unauthorized();
    error NothingToWithdraw();
    error TransferFailed();
    error AlreadyCancelled();
    error TimestampOverflow();

    function createStream(address employee, uint64 duration) external payable returns (uint256 streamId) {
        if (employee == address(0) || employee == msg.sender) {
            revert InvalidEmployee();
        }

        if (msg.value == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();

        uint256 start = block.timestamp + CORRECTION_WINDOW;
        uint256 end = start + duration;

        if (end > type(uint64).max) revert TimestampOverflow();

        streamId = nextStreamId++;

        streams[streamId] = Stream({
            employer: msg.sender,
            employee: employee,
            deposited: msg.value,
            withdrawn: 0,
            startTime: uint64(start),
            endTime: uint64(end),
            cancelledAt: 0,
            cancelled: false
        });

        emit StreamCreated(streamId, msg.sender, employee, msg.value, uint64(start), uint64(end));
    }

    function accrued(uint256 streamId) public view returns (uint256) {
        Stream storage s = streams[streamId];

        if (s.employer == address(0)) {
            revert StreamNotFound();
        }

        // A stream cancelled during its correction window earns nothing.
        if (block.timestamp < s.startTime) {
            return 0;
        }

        uint256 effectiveTime = block.timestamp;

        // Never accrue beyond the scheduled end.
        if (effectiveTime > s.endTime) {
            effectiveTime = s.endTime;
        }

        // Freeze accrual at cancellation.
        if (s.cancelled && effectiveTime > s.cancelledAt) {
            effectiveTime = s.cancelledAt;
        }

        if (effectiveTime <= s.startTime) {
            return 0;
        }

        return (s.deposited * (effectiveTime - s.startTime)) / (s.endTime - s.startTime);
    }

    function claimable(uint256 streamId) public view returns (uint256) {
        Stream storage s = streams[streamId];

        if (s.employer == address(0)) {
            revert StreamNotFound();
        }

        return accrued(streamId) - s.withdrawn;
    }

    function withdraw(uint256 streamId) external nonReentrant {
        Stream storage s = streams[streamId];

        if (s.employer == address(0)) {
            revert StreamNotFound();
        }

        if (msg.sender != s.employee) {
            revert Unauthorized();
        }

        uint256 amount = claimable(streamId);

        if (amount == 0) {
            revert NothingToWithdraw();
        }

        // Update state before sending native MON.
        s.withdrawn += amount;

        (bool success,) = payable(s.employee).call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit SalaryWithdrawn(streamId, s.employee, amount);
    }

    function cancel(uint256 streamId) external nonReentrant {
        Stream storage s = streams[streamId];

        if (s.employer == address(0)) {
            revert StreamNotFound();
        }

        if (msg.sender != s.employer) {
            revert Unauthorized();
        }

        if (s.cancelled) {
            revert AlreadyCancelled();
        }

        // Accrual is zero if cancelled before startTime.
        uint256 earned = accrued(streamId);

        // Earned includes amounts already withdrawn.
        // Therefore this refunds all unearned deposited funds.
        uint256 refund = s.deposited - earned;

        s.cancelledAt = uint64(block.timestamp);
        s.cancelled = true;

        if (refund > 0) {
            (bool success,) = payable(s.employer).call{value: refund}("");

            if (!success) {
                revert TransferFailed();
            }
        }

        emit StreamCancelled(streamId, refund);
    }
}
