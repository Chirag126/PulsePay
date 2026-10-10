// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SalaryStream} from "../src/SalaryStream.sol";

contract DeploySalaryStream is Script {
    function run() external returns (SalaryStream deployed) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        deployed = new SalaryStream();
        vm.stopBroadcast();

        console2.log("SalaryStream deployed at:", address(deployed));
    }
}
