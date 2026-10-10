// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SalaryStream} from "../src/SalaryStream.sol";

contract SalaryStreamTest is Test {
    SalaryStream internal salary;
    address internal employer = address(0xA11CE);
    address internal employee = address(0xB0B);
    address internal stranger = address(0xCAFE);

    function setUp() public {
        salary = new SalaryStream();
        vm.deal(employer, 100 ether);
        vm.deal(employee, 1 ether);
        vm.deal(stranger, 1 ether);
    }

    function testCreateStreamAndAccrue() public {
        vm.prank(employer);
        uint256 id = salary.createStream{value: 10 ether}(employee, 100);

        assertEq(id, 1);
        assertEq(salary.claimable(id), 0);

        vm.warp(block.timestamp + 50);
        assertEq(salary.claimable(id), 5 ether);
    }

    function testEmployeeCanWithdrawAccruedSalary() public {
        vm.prank(employer);
        uint256 id = salary.createStream{value: 10 ether}(employee, 100);

        vm.warp(block.timestamp + 40);
        uint256 beforeBalance = employee.balance;

        vm.prank(employee);
        salary.withdraw(id);

        assertEq(employee.balance - beforeBalance, 4 ether);
        assertEq(salary.claimable(id), 0);
    }

    function testStrangerCannotWithdraw() public {
        vm.prank(employer);
        uint256 id = salary.createStream{value: 10 ether}(employee, 100);

        vm.warp(block.timestamp + 50);
        vm.prank(stranger);
        vm.expectRevert(SalaryStream.Unauthorized.selector);
        salary.withdraw(id);
    }

    function testEmployerCanCancelAndRefundUnvestedFunds() public {
        vm.prank(employer);
        uint256 id = salary.createStream{value: 10 ether}(employee, 100);

        vm.warp(block.timestamp + 40);
        uint256 beforeBalance = employer.balance;

        vm.prank(employer);
        salary.cancel(id);

        assertEq(employer.balance - beforeBalance, 6 ether);
        assertEq(salary.claimable(id), 4 ether);
    }
}
