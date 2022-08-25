// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/LiquidityPool.sol";
import "../src/mocks/Asset.sol";
import "../src/mocks/Factory.sol";
import "../src/Tranche.sol";
import "../src/DebtToken.sol";

abstract contract TrancheTest is Test {

    Asset asset;
    Factory factory;
    LiquidityPool pool;
    Tranche tranche;
    Tranche jrTranche;
    DebtToken debt;
    Vault vault;

    address creator = address(1);
    address tokenCreator = address(2);
    address liquidator = address(3);
    address treasury = address(4);
    address vaultOwner = address(5);
    address liquidityProvider = address(6);

    //Before
    constructor() {
        vm.startPrank(tokenCreator);
        asset = new Asset("Asset", "ASSET", 18);
        asset.mint(liquidityProvider, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(creator);
        factory = new Factory();
        vm.stopPrank();
    }

    //Before Each
    function setUp() virtual public {
        vm.startPrank(creator);
        pool = new LiquidityPool(asset, liquidator, treasury, address(factory));

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));

        tranche = new Tranche(pool, "Senior", "SR");
        pool.addTranche(address(tranche), 50);
        vm.stopPrank();
    }
}

/*//////////////////////////////////////////////////////////////
                        DEPLOYMENT
//////////////////////////////////////////////////////////////*/
contract DeploymentTest is TrancheTest {

    function setUp() override public {
        super.setUp();
    }

    //Deployment
    function testSucces_Deployment() public {
        assertEq(tranche.name(), string("Senior Arcadia Asset"));
        assertEq(tranche.symbol(), string("SRarcASSET"));
        assertEq(tranche.decimals(), 18);
        assertEq(address(tranche.liquidityPool()), address(pool));
    }
}

/*//////////////////////////////////////////////////////////////
                    LOCKING LOGIC
//////////////////////////////////////////////////////////////*/
contract LockingTest is TrancheTest {

    function setUp() override public {
        super.setUp();
    }

    //lock
    function testRevert_LockUnauthorised(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(pool));

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        tranche.lock();
        vm.stopPrank();
    }

    function testSuccess_Lock() public {
        vm.prank(address(pool));
        tranche.lock();

        assertTrue(tranche.locked());
    }

    //unclock
    function testRevert_UnlockUnauthorised(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        tranche.unLock();
        vm.stopPrank();
    }

    function testSuccess_Unlock() public {
        vm.prank(address(pool));
        tranche.lock();

        vm.prank(creator);
        tranche.unLock();

        assertFalse(tranche.locked());
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/
contract DepositAndWithdrawalTest is TrancheTest {

    function setUp() override public {
        super.setUp();
    }

    //deposit
    function testRevert_DepositLocked() public {}

    function testRevert_DepositZeroShares() public {}

    function testSuccess_Deposit() public {}

    //mint
    function testRevert_MintLocked() public {}

    function testSuccess_Mint() public {}

    //withdraw
    function testRevert_WithdrawLocked() public {}

    function testRevert_WithdrawUnauthorised() public {}

    function testRevert_WithdrawInsufficientApproval() public {}

    function testSuccess_WithdrawByOwner() public {}

    function testSuccess_WithdrawByLimitedAuthorisedAddress() public {}

    function testSuccess_WithdrawByMaxAuthorisedAddress() public {}

    //redeem
    function testRevert_RedeemLocked() public {}

    function testRevert_RedeemUnauthorised() public {}

    function testRevert_RedeemInsufficientApproval() public {}

    function testSuccess_RedeemByOwner() public {}

    function testSuccess_RedeemByLimitedAuthorisedAddress() public {}

    function testSuccess_RedeemByMaxAuthorisedAddress() public {}
}
