/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/LiquidityPool.sol";
import "../src/mocks/Asset.sol";
import "../src/mocks/Factory.sol";
import "../src/Tranche.sol";
import "../src/DebtToken.sol";

abstract contract DebtTokenTest is Test {

    Asset asset;
    Factory factory;
    LiquidityPool pool;
    Tranche tranche;
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
        pool.updateInterestRate(5 * 10**16); //5% with 18 decimals precision

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));

        tranche = new Tranche(pool, "Senior", "SR");
        pool.addTranche(address(tranche), 50);
        vm.stopPrank();

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
    }
}

/*//////////////////////////////////////////////////////////////
                        DEPLOYMENT
//////////////////////////////////////////////////////////////*/
contract DeploymentTest is DebtTokenTest {

    function setUp() override public {
        super.setUp();
    }

    //Deployment
    function testSucces_Deployment() public {
        assertEq(debt.name(), string("Arcadia Asset Debt"));
        assertEq(debt.symbol(), string("darcASSET"));
        assertEq(debt.decimals(), 18);
        assertEq(address(tranche.liquidityPool()), address(pool));
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/
contract DepositAndWithdrawalTest is DebtTokenTest {

    function setUp() override public {
        super.setUp();
    }

    //deposit
    function testRevert_DepositUnauthorised(uint128 assets, address receiver, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(pool));

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        debt.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_DepositZeroShares(address receiver) public {
        vm.startPrank(address(pool));
        vm.expectRevert("ZERO_SHARES");
        debt.deposit(0, receiver);
        vm.stopPrank();
    }

    function testSuccess_Deposit(uint128 assets, address receiver) public {
        vm.assume(assets > 0);

        vm.prank(address(pool));
        debt.deposit(assets, receiver);

        assertEq(debt.maxWithdraw(receiver), assets);
        assertEq(debt.maxRedeem(receiver), assets);
        assertEq(debt.totalAssets(), assets);
    }

    //mint
    function testRevert_Mint(uint256 shares, address receiver, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("MINT_NOT_SUPPORTED");
        debt.mint(shares, receiver);
        vm.stopPrank();
    }

    //withdraw
    function testRevert_WithdrawUnauthorised(uint256 assets, address receiver, address owner, address sender) public {
        vm.assume(sender != address(pool));

        vm.startPrank(sender);
        vm.expectRevert("UNAUTHORIZED");
        debt.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_WithdrawInsufficientAssets(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        vm.expectRevert(stdError.arithmeticError);
        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_Withdraw(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);

        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();

        assertEq(debt.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(debt.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(debt.totalAssets(), assetsDeposited - assetsWithdrawn);
    }

    //redeem
    function testRevert_Redeem(uint256 shares, address receiver, address owner, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("REDEEM_NOT_SUPPORTED");
        debt.redeem(shares, receiver, owner);
        vm.stopPrank();
    }
}

/*//////////////////////////////////////////////////////////////
                        INTERESTS LOGIC
//////////////////////////////////////////////////////////////*/
contract InterestTest is DebtTokenTest {

    function setUp() override public {
        super.setUp();
    }

    //syncInterests
    function testRevert_SyncInterestsUnauthorised(uint128 assetsDeposited, uint128 interests, address owner, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(pool));

        vm.assume(assetsDeposited <= type(uint128).max);
        vm.assume(assetsDeposited > 0);

        vm.prank(address(pool));
        debt.deposit(assetsDeposited, owner);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        debt.syncInterests(interests);
        vm.stopPrank();
    }

    function testSucces_SyncInterests(uint128 assetsDeposited, uint128 interests, address owner) public {
        vm.assume(assetsDeposited > 0);
        uint256 totalAssets = uint256(assetsDeposited) + uint256(interests);
        vm.assume(assetsDeposited <= type(uint256).max / totalAssets);
        vm.assume(interests <= type(uint256).max / totalAssets);

        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        debt.syncInterests(interests);
        vm.stopPrank();

        assertEq(debt.maxWithdraw(owner), totalAssets);
        assertEq(debt.maxRedeem(owner), assetsDeposited);
        assertEq(debt.totalAssets(), totalAssets);
    }
}

/*//////////////////////////////////////////////////////////////
                        TRANSFER LOGIC
//////////////////////////////////////////////////////////////*/

contract TransferTest is DebtTokenTest {

    function setUp() override public {
        super.setUp();
    }

    //approve
    function testRevert_Approve(address spender, uint256 amount, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("APPROVE_NOT_SUPPORTED");
        debt.approve(spender, amount);
        vm.stopPrank();
    }

    //transfer
    function testRevert_Transfer(address to, uint256 amount, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("TRANSFER_NOT_SUPPORTED");
        debt.transfer(to, amount);
        vm.stopPrank();
    }

    //transferFrom
    function testRevert_TransferFrom(address from, address to, uint256 amount, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("TRANSFERFROM_NOT_SUPPORTED");
        debt.transferFrom(from, to, amount);
        vm.stopPrank();
    }

    //permit
    function testRevert_Permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address sender) public {
        vm.startPrank(sender);
        vm.expectRevert("PERMIT_NOT_SUPPORTED");
        debt.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }

}
