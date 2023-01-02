/**
 * Created by Arcadia Finance
 *     https://www.arcadia.finance
 *     SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../../lib/ds-test/src/test.sol";
import "../../lib/forge-std/src/Script.sol";
import "../../lib/forge-std/src/console.sol";
import "../../lib/forge-std/src/Vm.sol";

import "../DebtToken.sol";
import "../LendingPool.sol";
import "../Tranche.sol";
import "../TrustedProtocol.sol";

import "../mocks/Factory.sol";

import "./interfaces/IERC20.sol";

contract DeployScript is DSTest, Script {
    ERC20 asset;
    Factory factory;
    LendingPool pool;
    Tranche srTranche;
    Tranche jrTranche;
    DebtToken debt;

    //Before
    constructor() {
        asset = ERC20(0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43);
    }

    //Before Each
    function run() public {
        vm.startBroadcast();
        factory = new Factory();
        pool = new LendingPool(ERC20(asset), 0x12e463251Bc79677FD980aA6c301d5Fb85101cCb, address(factory));
        srTranche = new Tranche(address(pool), "Senior", "SR");
        jrTranche = new Tranche(address(pool), "Junior", "JR");

        pool.setVaultVersion(1, true);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 50);
        pool.setFeeWeight(10);
        vm.stopPrank();
    }
}
