// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Script.sol";

import {LiquidityPool} from "src/LiquidityPool.sol";

contract LiquidityPoolScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        //new LiquidityPool();
    }
}
