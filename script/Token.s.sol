// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {console} from "forge-std/console.sol";

contract TokenScript is Script {
    uint256 public deployerPrivateKey;
    address public deployer;

    function run() public {
        
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        Token token = new Token();

        console.log("Token deployed to:", address(token));
        vm.stopBroadcast();
    }
}