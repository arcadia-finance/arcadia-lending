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

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
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

    //unlock
    function testRevert_UnlockUnauthorised(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.prank(address(pool));
        tranche.lock();
        assertTrue(tranche.locked());

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        tranche.unLock();
        vm.stopPrank();
    }

    function testSuccess_Unlock() public {
        vm.prank(address(pool));
        tranche.lock();
        assertTrue(tranche.locked());

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
    function testRevert_DepositLocked(uint128 assets, address receiver) public {
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_DepositZeroShares(address receiver) public {
        vm.startPrank(liquidityProvider);
        vm.expectRevert("ZERO_SHARES");
        tranche.deposit(0, receiver);
        vm.stopPrank();
    }

    function testSuccess_Deposit(uint128 assets, address receiver) public {
        vm.assume(assets > 0);

        vm.prank(liquidityProvider);
        tranche.deposit(assets, receiver);

        assertEq(tranche.maxWithdraw(receiver), assets);
        assertEq(tranche.maxRedeem(receiver), assets);
        assertEq(tranche.totalAssets(), assets);
        assertEq(asset.balanceOf(address(pool)), assets);
    }

    //mint
    function testRevert_MintLocked(uint128 shares, address receiver) public {
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.mint(shares, receiver);
        vm.stopPrank();
    }

    function testSuccess_Mint(uint128 shares, address receiver) public {
        vm.assume(shares > 0);

        vm.prank(liquidityProvider);
        tranche.mint(shares, receiver);

        assertEq(tranche.maxWithdraw(receiver), shares);
        assertEq(tranche.maxRedeem(receiver), shares);
        assertEq(tranche.totalAssets(), shares);
        assertEq(asset.balanceOf(address(pool)), shares);
    }

    //withdraw
    function testRevert_WithdrawLocked(uint128 assets, address receiver, address owner) public {
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_WithdrawUnauthorised(uint128 assets, address receiver, address owner, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != owner);
        vm.assume(assets > 0);

        vm.prank(liquidityProvider);
        tranche.deposit(assets, owner);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_WithdrawInsufficientApproval(uint128 assetsDeposited, uint128 sharesAllowed, address receiver, address owner, address beneficiary) public {
        vm.assume(beneficiary != owner);
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < sharesAllowed);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(sharesAllowed, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_WithdrawInsufficientAssets(uint128 assetsDeposited, uint128 assetsWithdrawn, address owner, address receiver) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.startPrank(owner);
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_WithdrawByOwner(uint128 assetsDeposited, uint128 assetsWithdrawn, address owner, address receiver) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    function testSuccess_WithdrawByLimitedAuthorisedAddress(uint128 assetsDeposited, uint128 sharesAllowed, uint128 assetsWithdrawn, address receiver, address owner, address beneficiary) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(sharesAllowed >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);        
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.allowance(owner, beneficiary), sharesAllowed - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    function testSuccess_WithdrawByMaxAuthorisedAddress(uint128 assetsDeposited, uint128 assetsWithdrawn, address receiver, address owner, address beneficiary) public {
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, type(uint256).max);

        vm.startPrank(beneficiary);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.allowance(owner, beneficiary), type(uint256).max);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    //redeem
    function testRevert_RedeemLocked(uint128 shares, address receiver, address owner) public {
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.redeem(shares, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_RedeemUnauthorised(uint128 shares, address receiver, address owner, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != owner);
        vm.assume(shares > 0);

        vm.prank(liquidityProvider);
        tranche.mint(shares, owner);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(shares, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_RedeemInsufficientApproval(uint128 sharesMinted, uint128 sharesAllowed, address receiver, address owner, address beneficiary) public {
        vm.assume(beneficiary != owner);
        vm.assume(sharesMinted > 0);
        vm.assume(sharesMinted < sharesAllowed);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(sharesAllowed, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_RedeemInsufficientShares(uint128 sharesMinted, uint128 sharesRedeemed, address owner, address receiver) public {
        vm.assume(sharesMinted > 0);
        vm.assume(sharesMinted < sharesRedeemed);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.startPrank(owner);
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(sharesRedeemed, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_RedeemByOwner(uint128 sharesMinted, uint128 sharesRedeemed, address owner, address receiver) public {
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        tranche.redeem(sharesRedeemed, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }

    function testSuccess_RedeemByLimitedAuthorisedAddress(uint128 sharesMinted, uint128 sharesAllowed, uint128 sharesRedeemed, address receiver, address owner, address beneficiary) public {
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(sharesAllowed >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);        
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        tranche.redeem(sharesRedeemed, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(tranche.allowance(owner, beneficiary), sharesAllowed - sharesRedeemed);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }

    function testSuccess_RedeemByMaxAuthorisedAddress(uint128 sharesMinted, uint128 sharesRedeemed, address receiver, address owner, address beneficiary) public {
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, type(uint256).max);

        vm.startPrank(beneficiary);
        tranche.redeem(sharesRedeemed, receiver, owner);

        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(tranche.allowance(owner, beneficiary), type(uint256).max);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }
}
