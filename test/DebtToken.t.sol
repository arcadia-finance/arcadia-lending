/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/LendingPool.sol";
import "../src/mocks/Asset.sol";
import "../src/mocks/Factory.sol";
import "../src/Tranche.sol";
import "../src/DebtToken.sol";

abstract contract DebtTokenTest is Test {
    Asset asset;
    Factory factory;
    LendingPool pool;
    Tranche tranche;
    DebtToken debt;
    Vault vault;

    address creator = address(1);
    address tokenCreator = address(2);
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
    function setUp() public virtual {
        vm.startPrank(creator);
        pool = new LendingPool(asset, treasury, address(factory));
        pool.updateInterestRate(5 * 10 ** 16); //5% with 18 decimals precision

        debt = new DebtToken(address(pool));
        pool.setDebtToken(address(debt));

        tranche = new Tranche(address(pool), "Senior", "SR");
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
    function setUp() public override {
        super.setUp();
    }

    //Deployment
    function testSucces_Deployment() public {
        // Given: all neccesary contracts are deployed on the setup

        // When: debt is DebtToken

        // Then: debt's name should be Arcadia Asset Debt, symbol should be darcASSET,
        //       decimals should be 18, lendingPool should return pool address
        assertEq(debt.name(), string("Arcadia Asset Debt"));
        assertEq(debt.symbol(), string("darcASSET"));
        assertEq(debt.decimals(), 18);
        assertEq(address(tranche.lendingPool()), address(pool));
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/
contract DepositAndWithdrawalTest is DebtTokenTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_deposit_Unauthorised(uint128 assets, address receiver, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(pool));
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(unprivilegedAddress);
        // When: depositing with unprivilegedAddress
        // Then: deposit should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_deposit_ZeroShares(address receiver) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(address(pool));
        // When: depositing zero shares
        // Then: deposit should revert with ZERO_SHARES
        vm.expectRevert("ZERO_SHARES");
        debt.deposit(0, receiver);
        vm.stopPrank();
    }

    function testSuccess_deposit(uint128 assets, address receiver) public {
        vm.assume(assets > 0);
        // Given: all neccesary contracts are deployed on the setup

        vm.prank(address(pool));
        // When: pool deposits assets
        debt.deposit(assets, receiver);

        // Then: receiver's maxWithdraw should be equal assets, maxRedeem should be equal assets, totalAssets should be equal assets
        assertEq(debt.maxWithdraw(receiver), assets);
        assertEq(debt.maxRedeem(receiver), assets);
        assertEq(debt.totalAssets(), assets);
    }

    function testRevert_mint(uint256 shares, address receiver, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender mint shares
        // Then: mint should revert with MINT_NOT_SUPPORTED
        vm.expectRevert("MINT_NOT_SUPPORTED");
        debt.mint(shares, receiver);
        vm.stopPrank();
    }

    function testRevert_withdraw_Unauthorised(uint256 assets, address receiver, address owner, address sender) public {
        // Given: pool is not the sender
        vm.assume(sender != address(pool));

        vm.startPrank(sender);
        // When: sender withdraw
        // Then: withdraw should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_withdraw_InsufficientAssets(
        uint128 assetsDeposited,
        uint128 assetsWithdrawn,
        address receiver,
        address owner
    )
        public
    {
        // Given: assetsDeposited are bigger than 0 but less than assetsWithdrawn
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.startPrank(address(pool));
        // When: pool deposit assetsDeposited
        debt.deposit(assetsDeposited, owner);

        // Then: withdraw should revert
        vm.expectRevert(stdError.arithmeticError);
        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_withdraw(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner)
        public
    {
        // Given: assetsDeposited are bigger than 0 and bigger than or equal to assetsWithdrawn
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);

        vm.startPrank(address(pool));
        // When: pool deposit assetsDeposited, withdraw assetsWithdrawn
        debt.deposit(assetsDeposited, owner);

        debt.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();

        // Then: maxWithdraw should be equal to assetsDeposited minus assetsWithdrawn,
        // maxRedeem should be equal to assetsDeposited minus assetsWithdrawn, totalAssets should be equal to assetsDeposited minus assetsWithdrawn
        assertEq(debt.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(debt.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(debt.totalAssets(), assetsDeposited - assetsWithdrawn);
    }

    function testRevert_redeem(uint256 shares, address receiver, address owner, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender redeem shares
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
    function setUp() public override {
        super.setUp();
    }

    function testRevert_syncInterests_Unauthorised(
        uint128 assetsDeposited,
        uint128 interests,
        address owner,
        address unprivilegedAddress
    )
        public
    {
        // Given: unprivilegedAddress is not pool, assetsDeposited are bigger than zero but less than maximum uint128 value
        vm.assume(unprivilegedAddress != address(pool));

        vm.assume(assetsDeposited <= type(uint128).max);
        vm.assume(assetsDeposited > 0);

        vm.prank(address(pool));
        // When: pool deposit assetsDeposited
        debt.deposit(assetsDeposited, owner);

        vm.startPrank(unprivilegedAddress);
        // Then: unprivilegedAddress syncInterests attempt should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        debt.syncInterests(interests);
        vm.stopPrank();
    }

    function testSucces_syncInterests(uint128 assetsDeposited, uint128 interests, address owner) public {
        // Given: assetsDeposited are bigger than zero but less than equal to maximum uint256 value divided by totalAssets,
        // interests less than equal to maximum uint256 value divided by totalAssets
        vm.assume(assetsDeposited > 0);
        uint256 totalAssets = uint256(assetsDeposited) + uint256(interests);
        vm.assume(assetsDeposited <= type(uint256).max / totalAssets);
        vm.assume(interests <= type(uint256).max / totalAssets);

        vm.startPrank(address(pool));
        // When: pool deposit assetsDeposited, syncInterests with interests
        debt.deposit(assetsDeposited, owner);

        debt.syncInterests(interests);
        vm.stopPrank();

        // Then: debt's maxWithdraw should be equal to totalAssets, debt's maxRedeem should be equal to assetsDeposited, debt's totalAssets should be equal to totalAssets
        assertEq(debt.maxWithdraw(owner), totalAssets);
        assertEq(debt.maxRedeem(owner), assetsDeposited);
        assertEq(debt.totalAssets(), totalAssets);
    }
}

/*//////////////////////////////////////////////////////////////
                        TRANSFER LOGIC
//////////////////////////////////////////////////////////////*/

contract TransferTest is DebtTokenTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_approve(address spender, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender approve
        // Then: approve should revert with APPROVE_NOT_SUPPORTED
        vm.expectRevert("APPROVE_NOT_SUPPORTED");
        debt.approve(spender, amount);
        vm.stopPrank();
    }

    function testRevert_transfer(address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender transfer
        // Then: transfer should revert with TRANSFER_NOT_SUPPORTED
        vm.expectRevert("TRANSFER_NOT_SUPPORTED");
        debt.transfer(to, amount);
        vm.stopPrank();
    }

    function testRevert_transferFrom(address from, address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender transferFrom
        // Then: transferFrom should revert with TRANSFERFROM_NOT_SUPPORTED
        vm.expectRevert("TRANSFERFROM_NOT_SUPPORTED");
        debt.transferFrom(from, to, amount);
        vm.stopPrank();
    }

    function testRevert_permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address sender
    )
        public
    {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender permit
        // Then: permit should revert with PERMIT_NOT_SUPPORTED
        vm.expectRevert("PERMIT_NOT_SUPPORTED");
        debt.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }
}
