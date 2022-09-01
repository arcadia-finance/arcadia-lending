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
        // Given: all neccesary contracts are deployed on the setup

        // When: debt is DebtToken

        // Then: debt's name should be Arcadia Asset Debt
        assertEq(debt.name(), string("Arcadia Asset Debt"));
        //And: debt's symbol should be darcASSET
        assertEq(debt.symbol(), string("darcASSET"));
        //And: debt's decimals should be 18
        assertEq(debt.decimals(), 18);
        //And: liquidityPool should return pool address
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
        // Given: all neccesary contracts are deployed on the setup

        // When: unprivilegedAddress is pranked
        vm.startPrank(unprivilegedAddress);
        // Then: deposit should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_DepositZeroShares(address receiver) public {
        // Given: all neccesary contracts are deployed on the setup


        // When: pool is pranked
        vm.startPrank(address(pool));
        // Then: depositing zero shares should revert with ZERO_SHARES
        vm.expectRevert("ZERO_SHARES");
        debt.deposit(0, receiver);
        vm.stopPrank();
    }

    function testSuccess_Deposit(uint128 assets, address receiver) public {
        vm.assume(assets > 0);
        // Given: all neccesary contracts are deployed on the setup

        // When: pool is pranked and deposits to debt
        vm.prank(address(pool));
        debt.deposit(assets, receiver);

        // Then: receiver's maxWithdraw should be equal assets
        assertEq(debt.maxWithdraw(receiver), assets);
        // And: receiver's maxRedeem should be equal assets
        assertEq(debt.maxRedeem(receiver), assets);
        // And: totalAssets should be equal assets
        assertEq(debt.totalAssets(), assets);
    }

    //mint
    function testRevert_Mint(uint256 shares, address receiver, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        // When: sender is pranked
        vm.startPrank(sender);
        // Then: mint should revert with MINT_NOT_SUPPORTED
        vm.expectRevert("MINT_NOT_SUPPORTED");
        debt.mint(shares, receiver);
        vm.stopPrank();
    }

    //withdraw
    function testRevert_WithdrawUnauthorised(uint256 assets, address receiver, address owner, address sender) public {
        // Given: pool is not the sender
        vm.assume(sender != address(pool));

        // When: sender is pranked
        vm.startPrank(sender);
        // Then: withdraw should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_WithdrawInsufficientAssets(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner) public {
        // Given: assetsDeposited are bigger than 0 but less than assetsWithdrawn
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        // When: pool is pranked and deposit assetsDeposited
        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        // Then: withdraw should revert
        vm.expectRevert(stdError.arithmeticError);
        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_Withdraw(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner) public {
        // Given: assetsDeposited are bigger than 0 and bigger than or equal to assetsWithdrawn
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);

        // When: pool is pranked and deposit assetsDeposited, withdraw assetsWithdrawn
        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();

        // Then: maxWithdraw should be equal to assetsDeposited minus assetsWithdrawn
        assertEq(debt.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        // And: maxRedeem should be equal to assetsDeposited minus assetsWithdrawn
        assertEq(debt.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        // And: totalAssets should be equal to assetsDeposited minus assetsWithdrawn
        assertEq(debt.totalAssets(), assetsDeposited - assetsWithdrawn);
    }

    //redeem
    function testRevert_Redeem(uint256 shares, address receiver, address owner, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        // When: sender is pranked     
        vm.startPrank(sender);
        // Then: redeem should revert with REDEEM_NOT_SUPPORTED
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
        // Given: unprivilegedAddress is not pool, assetsDeposited are bigger than zero but less than maximum uint128 value
        vm.assume(unprivilegedAddress != address(pool));

        vm.assume(assetsDeposited <= type(uint128).max);
        vm.assume(assetsDeposited > 0);

        // When: pool is pranked and deposit assetsDeposited
        vm.prank(address(pool));
        debt.deposit(assetsDeposited, owner);

        // When: unprivilegedAddress is pranked
        vm.startPrank(unprivilegedAddress);
        // Then: syncInterests should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.syncInterests(interests);
        vm.stopPrank();
    }

    function testSucces_SyncInterests(uint128 assetsDeposited, uint128 interests, address owner) public {
        // Given: assetsDeposited are bigger than zero but less than equal to maximum uint256 value divided by totalAssets,
        // interests less than equal to maximum uint256 value divided by totalAssets
        vm.assume(assetsDeposited > 0);
        uint256 totalAssets = uint256(assetsDeposited) + uint256(interests);
        vm.assume(assetsDeposited <= type(uint256).max / totalAssets);
        vm.assume(interests <= type(uint256).max / totalAssets);

        // When: pool is pranked and deposit assetsDeposited, syncInterests with interests
        vm.startPrank(address(pool));
        debt.deposit(assetsDeposited, owner);

        debt.syncInterests(interests);
        vm.stopPrank();

        // Then: debt's maxWithdraw should be equal to totalAssets
        assertEq(debt.maxWithdraw(owner), totalAssets);
        // And: debt's maxRedeem should be equal to assetsDeposited
        assertEq(debt.maxRedeem(owner), assetsDeposited);
        // And: debt's totalAssets should be equal to totalAssets
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
        // Given: all neccesary contracts are deployed on the setup
        
        // When: sender is pranked
        vm.startPrank(sender);
        // Then: approve should revert with APPROVE_NOT_SUPPORTED
        vm.expectRevert("APPROVE_NOT_SUPPORTED");
        debt.approve(spender, amount);
        vm.stopPrank();
    }

    //transfer
    function testRevert_Transfer(address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup
        
        // When: sender is pranked
        vm.startPrank(sender);
        // Then: approve should revert with TRANSFER_NOT_SUPPORTED
        vm.expectRevert("TRANSFER_NOT_SUPPORTED");
        debt.transfer(to, amount);
        vm.stopPrank();
    }

    //transferFrom
    function testRevert_TransferFrom(address from, address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup
        
        // When: sender is pranked
        vm.startPrank(sender);
        // Then: approve should revert with TRANSFERFROM_NOT_SUPPORTED
        vm.expectRevert("TRANSFERFROM_NOT_SUPPORTED");
        debt.transferFrom(from, to, amount);
        vm.stopPrank();
    }

    //permit
    function testRevert_Permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address sender) public {
        // Given: all neccesary contracts are deployed on the setup
        
        // When: sender is pranked
        vm.startPrank(sender);
        // Then: approve should revert with PERMIT_NOT_SUPPORTED
        vm.expectRevert("PERMIT_NOT_SUPPORTED");
        debt.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }

}
