// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/LiquidityPool.sol";
import "../src/Asset.sol";
import "../src/Tranche.sol";
import "../src/DebtToken.sol";

abstract contract LiquidityPoolTest is Test {

    Asset asset;
    LiquidityPool pool;
    Tranche srTranche;
    Tranche jrTranche;
    DebtToken debt;

    address creator = address(1);
    address liquidator = address(2);
    address feeCollector = address(3);
    address vaultFactory = address(4);

    //Before
    constructor() {
        vm.startPrank(creator);
        asset = new Asset("Asset", "ASSET", 18);
        vm.stopPrank();
    }

    //Before Each

    function setUp() virtual public {
        vm.startPrank(creator);
        pool = new LiquidityPool(asset, liquidator, feeCollector, vaultFactory);
        srTranche = new Tranche(pool, "Senior", "SR");
        jrTranche = new Tranche(pool, "Junior", "JR");
        vm.stopPrank();
    }
}

/*//////////////////////////////////////////////////////////////
                        DEPLOYMENT
//////////////////////////////////////////////////////////////*/
contract DeploymentTest is LiquidityPoolTest {

    function setUp() override public {
        super.setUp();
    }

    //Deployment
    function testDeployment() public {
        assertEq(pool.name(), string("Arcadia Asset Pool"));
        assertEq(pool.symbol(), string("arcASSET"));
        assertEq(pool.decimals(), 18);
        assertEq(pool.vaultFactory(), vaultFactory);
        assertEq(pool.liquidator(), liquidator);
        assertEq(pool.feeCollector(), feeCollector);
    }
}

/*//////////////////////////////////////////////////////////////
                        TRANCHES LOGIC
//////////////////////////////////////////////////////////////*/
contract TranchesTest is LiquidityPoolTest {

    function setUp() override public {
        super.setUp();
    }

    //addTranche
    function testRevert_AddTrancheInvalidOwner(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.addTranche(address(srTranche), 50);
        vm.stopPrank();
    }

    function testSuccess_AddSingleTranche() public {
        vm.prank(creator);
        pool.addTranche(address(srTranche), 50);

        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.tranches(0), address(srTranche));
        assertTrue(pool.isTranche(address(srTranche)));
    }

    function testRevert_AddSingleTrancheTwice()public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);

        vm.expectRevert("TR_AD: Already exists");
        pool.addTranche(address(srTranche), 40);
        vm.stopPrank();
    }

    function testSuccess_AddMultipleTranches() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        assertEq(pool.totalWeight(), 90);
        assertEq(pool.weights(0), 50);
        assertEq(pool.weights(1), 40);
        assertEq(pool.tranches(0), address(srTranche));
        assertEq(pool.tranches(1), address(jrTranche));
        assertTrue(pool.isTranche(address(jrTranche)));
    }

    //setWeight
    function testRevert_SetWeightInvalidOwner(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testRevert_SetWeightInexistingtranche() public {
        vm.startPrank(creator);
        vm.expectRevert("TR_SW: Inexisting Tranche");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testSuccess_SetWeight() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.setWeight(0, 40);
        vm.stopPrank();

        assertEq(pool.weights(0), 40);
    }

    //removeLastTranche
    

}
