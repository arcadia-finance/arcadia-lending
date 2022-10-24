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

        debt = DebtToken(address(pool));

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

contract DepositWithdrawalTest is DebtTokenTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_deposit(uint256 assets, address receiver, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender deposits assets
        // Then: deposit should revert with DEPOSIT_NOT_SUPPORTED
        vm.expectRevert("DEPOSIT_NOT_SUPPORTED");
        pool.deposit(assets, receiver);
        vm.stopPrank();
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

    function testRevert_withdraw(uint256 assets, address receiver, address owner, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender withdraw
        // Then: withdraw should revert with WITHDRAW_NOT_SUPPORTED
        vm.expectRevert("WITHDRAW_NOT_SUPPORTED");
        debt.withdraw(assets, receiver, owner);
        vm.stopPrank();
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
    ) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender permit
        // Then: permit should revert with PERMIT_NOT_SUPPORTED
        vm.expectRevert("PERMIT_NOT_SUPPORTED");
        debt.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }
}
