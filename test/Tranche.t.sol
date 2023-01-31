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

abstract contract TrancheTest is Test {
    Asset asset;
    Factory factory;
    LendingPool pool;
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
    function setUp() public virtual {
        vm.startPrank(creator);
        pool = new LendingPool(asset, treasury, address(factory), address(0));

        tranche = new Tranche(address(pool), "Senior", "SR");
        pool.addTranche(address(tranche), 50, 0);
        vm.stopPrank();

        debt = DebtToken(address(pool));

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
    }
}

/*//////////////////////////////////////////////////////////////
                        DEPLOYMENT
//////////////////////////////////////////////////////////////*/
contract DeploymentTest is TrancheTest {
    function setUp() public override {
        super.setUp();
    }

    //Deployment
    function testSucces_Deployment() public {
        assertEq(tranche.name(), string("Senior Arcadia Asset"));
        assertEq(tranche.symbol(), string("SRarcASSET"));
        assertEq(tranche.decimals(), 18);
        assertEq(address(tranche.lendingPool()), address(pool));
    }
}

/*//////////////////////////////////////////////////////////////
                    LOCKING LOGIC
//////////////////////////////////////////////////////////////*/
contract LockingTest is TrancheTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
    }

    function testRevert_lock_Unauthorised(address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not pool
        vm.assume(unprivilegedAddress != address(pool));

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress lock

        // Then: lock reverts with "T_L: UNAUTHORIZED"
        vm.expectRevert("T_L: UNAUTHORIZED");
        tranche.lock();
        vm.stopPrank();
    }

    function testSuccess_lock() public {
        // Given: auction is ongoing
        vm.prank(address(pool));
        tranche.setAuctionInProgress(true);

        // When: pool lock
        vm.prank(address(pool));
        tranche.lock();

        // Then: locked should return true
        assertTrue(tranche.locked());
        assertFalse(tranche.auctionInProgress());
    }

    function testRevert_unlock_Unauthorised(address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not creator, pool lock
        vm.assume(unprivilegedAddress != creator);

        vm.prank(address(pool));
        tranche.lock();
        assertTrue(tranche.locked());

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress unlock

        // Then: unlock reverts with "UNAUTHORIZED"
        vm.expectRevert("UNAUTHORIZED");
        tranche.unLock();
        vm.stopPrank();
    }

    function testSuccess_unlock() public {
        // Given: pool lock, locked returns true
        vm.prank(address(pool));
        tranche.lock();
        assertTrue(tranche.locked());

        vm.prank(creator);
        // When: creator unlock
        tranche.unLock();

        // Then: locked should return false
        assertFalse(tranche.locked());
    }

    function testRevert_setAuctionInProgress_Unauthorised(address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not pool
        vm.assume(unprivilegedAddress != address(pool));

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setAuctionInProgress
        // Then: setAuctionInProgress reverts with "T_SAIP: UNAUTHORIZED"
        vm.expectRevert("T_SAIP: UNAUTHORIZED");
        tranche.setAuctionInProgress(true);
        vm.stopPrank();
    }

    function testSuccess_setAuctionInProgress(bool set) public {
        vm.startPrank(address(pool));
        tranche.setAuctionInProgress(set);
        vm.stopPrank();

        assertEq(tranche.auctionInProgress(), set);
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/
contract DepositAndWithdrawalTest is TrancheTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_deposit_Locked(uint128 assets, address receiver) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        // When: liquidityProvider deposit

        // Then: deposit should revert with "TRANCHE: LOCKED"
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_deposit_ZeroShares(address receiver) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(liquidityProvider);
        // When: liquidityProvider deposit 0

        // Then: deposit should revert with "T_D: ZERO_SHARES"
        vm.expectRevert("T_D: ZERO_SHARES");
        tranche.deposit(0, receiver);
        vm.stopPrank();
    }

    function testRevert_deposit_AuctionInProgress(uint128 assets, address receiver) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.setAuctionInProgress(true);

        vm.startPrank(liquidityProvider);
        // When: liquidityProvider deposit

        // Then: deposit should revert with "TRANCHE: LOCKED"
        vm.expectRevert("TRANCHE: AUCTION IN PROGRESS");
        tranche.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testSuccess_deposit(uint128 assets, address receiver) public {
        // Given: assets bigger than 0
        vm.assume(assets > 0);

        vm.prank(liquidityProvider);
        // When: liquidityProvider deposit assets
        tranche.deposit(assets, receiver);

        // Then: receiver maxWithdraw and maxRedeem should be assets, totalAssets and balanceOf pool should be assets
        assertEq(tranche.maxWithdraw(receiver), assets);
        assertEq(tranche.maxRedeem(receiver), assets);
        assertEq(tranche.totalAssets(), assets);
        assertEq(asset.balanceOf(address(pool)), assets);
    }

    function testSuccess_deposit_sync(uint128 assets, address receiver) public {
        // Given: assets bigger than 0
        vm.assume(assets > 0);

        uint256 timeNow = block.timestamp;

        vm.prank(liquidityProvider);
        tranche.deposit(assets/3, receiver);

        vm.prank(liquidityProvider);
        tranche.deposit(assets/3, receiver);

        vm.warp(500);

        vm.prank(liquidityProvider);
        vm.expectCall(address(pool), abi.encodeWithSignature("liquidityOfAndSync(address)", address(tranche)));
        tranche.deposit(assets/3, receiver);

    }

    function testRevert_mint_Locked(uint128 shares, address receiver) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        // When: liquidityProvider mint

        // Then: mint should revert with "TRANCHE: LOCKED"
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.mint(shares, receiver);
        vm.stopPrank();
    }

    function testSuccess_mint(uint128 shares, address receiver) public {
        // Given: shares more than 0
        vm.assume(shares > 0);

        vm.prank(liquidityProvider);
        // When: liquidityProvider mint shares
        tranche.mint(shares, receiver);

        // Then receiver maxWithdraw and maxRedeem should be shares, totalAssets should be shares, balanceOf pool should be shares
        assertEq(tranche.maxWithdraw(receiver), shares);
        assertEq(tranche.maxRedeem(receiver), shares);
        assertEq(tranche.totalAssets(), shares);
        assertEq(asset.balanceOf(address(pool)), shares);
    }

    function testRevert_withdraw_Locked(uint128 assets, address receiver, address owner) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.lock();

        vm.startPrank(liquidityProvider);
        // When: liquidityProvider withdraw

        // Then: withdraw should revert with "TRANCHE: LOCKED"
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_withdraw_AuctionInProgress(uint128 assets, address receiver, address owner) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.setAuctionInProgress(true);

        vm.startPrank(liquidityProvider);
        // When: liquidityProvider deposit

        // Then: deposit should revert with "TRANCHE: LOCKED"
        vm.expectRevert("TRANCHE: AUCTION IN PROGRESS");
        tranche.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_withdraw_Unauthorised(
        uint128 assets,
        address receiver,
        address owner,
        address unprivilegedAddress
    ) public {
        // Given: unprivilegedAddress is not owner, assets bigger than 0, liquidityProvider deposit assets
        vm.assume(unprivilegedAddress != owner);
        vm.assume(assets > 0);

        vm.prank(liquidityProvider);
        tranche.deposit(assets, owner);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress withdraw

        // Then: withdraw should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_withdraw_InsufficientApproval(
        uint128 assetsDeposited,
        uint128 sharesAllowed,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: beneficiary is not owner, assetsDeposited is bigger than 0 and less than sharesAllowed, liquidityProvider deposit assetsDeposited, owner approve beneficiary
        vm.assume(beneficiary != owner);
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < sharesAllowed);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        // When: beneficiary withdraw

        // Then: withdraw should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(sharesAllowed, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_withdraw_InsufficientAssets(
        uint128 assetsDeposited,
        uint128 assetsWithdrawn,
        address owner,
        address receiver
    ) public {
        // Given: assetsDeposited should be bigger than 0, less than assetsWithdrawn, liquidityProvider deposit assetsDeposited
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.prank(liquidityProvider);
        tranche.deposit(assetsDeposited, owner);

        vm.startPrank(owner);
        // When: owner withdraw

        // Then: withdraw should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.withdraw(assetsWithdrawn, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_withdraw_ByOwner(
        uint128 assetsDeposited,
        uint128 assetsWithdrawn,
        address owner,
        address receiver
    ) public {
        // Given: assetsDeposited bigger than 0 and assetsWithdrawn, receiver is not pool or liquidityProvider
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));

        vm.prank(liquidityProvider);
        // When: liquidityProvider deposit assetsDeposited, owner withdraw assetsWithdrawn
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        // Then: balanceOf pool, totalAssets, owner maxWithdraw and owner maxRedeem should be assetsDeposited minus assetsWithdrawn, balanceOf receiver should be assetsWithdrawn
        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    function testSuccess_withdraw_ByLimitedAuthorisedAddress(
        uint128 assetsDeposited,
        uint128 sharesAllowed,
        uint128 assetsWithdrawn,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: assetsDeposited bigger than 0 and assetsWithdrawn, sharesAllowed bigger than equal to assetsWithdrawn,
        // receiver is not pool or liquidityProvider, beneficiary is not owner
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(sharesAllowed >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        // When: liquidityProvider deposit assetsDeposited, owner approve beneficiary, beneficiary withdraw assetsWithdrawn
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        // Then: balanceOf pool, allowance, totalAssets, owner maxWithdraw and owner maxRedeem should be assetsDeposited minus assetsWithdrawn, balanceOf receiver should be assetsWithdrawn
        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.allowance(owner, beneficiary), sharesAllowed - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    function testSuccess_withdraw_ByMaxAuthorisedAddress(
        uint128 assetsDeposited,
        uint128 assetsWithdrawn,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: assetsDeposited is bigger than 0 and assetsWithdrawn, receiver is not liquidityProvider,
        // receiver is not pool, beneficiary is not owner
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsDeposited >= assetsWithdrawn);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        // When: liquidityProvider deposit assetsDeposited, owner approve beneficiary, beneficiary withdraw assetsWithdrawn
        tranche.deposit(assetsDeposited, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, type(uint256).max);

        vm.startPrank(beneficiary);
        tranche.withdraw(assetsWithdrawn, receiver, owner);

        // Then: owner maxWithdraw, maxRedeem, totalAssets, balanceOf pool should be equal to ssetsDeposited minus assetsWithdrawn,
        // allowance should be equal to max value, balanceOf receiver should be equal to assetsWithdrawn
        assertEq(tranche.maxWithdraw(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.maxRedeem(owner), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.totalAssets(), assetsDeposited - assetsWithdrawn);
        assertEq(tranche.allowance(owner, beneficiary), type(uint256).max);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }

    function testRevert_redeem_Locked(uint128 shares, address receiver, address owner) public {
        // Given: pool lock
        vm.prank(address(pool));
        tranche.lock();

        // When: liquidityProvider redeem
        // Then: redeem should revert with "TRANCHE: LOCKED"
        vm.startPrank(liquidityProvider);
        vm.expectRevert("TRANCHE: LOCKED");
        tranche.redeem(shares, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_redeem_ZeroAssets(address receiver, address owner) public {
        vm.startPrank(liquidityProvider);
        vm.expectRevert("T_R: ZERO_ASSETS");
        tranche.redeem(0, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_redeem_Unauthorised(
        uint128 shares,
        address receiver,
        address owner,
        address unprivilegedAddress
    ) public {
        // Given: unprivilegedAddress is not owner, shares bigger than 0, liquidityProvider mint shares
        vm.assume(unprivilegedAddress != owner);
        vm.assume(shares > 0);

        vm.prank(liquidityProvider);
        tranche.mint(shares, owner);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress redeem

        // Then: redeem should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(shares, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_redeem_InsufficientApproval(
        uint128 sharesMinted,
        uint128 sharesAllowed,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: beneficiary is not owner, sharesMinted bigger than 0 and less than sharesAllowed, liquidityProvider mint shares, owner approve beneficiary
        vm.assume(beneficiary != owner);
        vm.assume(sharesMinted > 0);
        vm.assume(sharesMinted < sharesAllowed);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        // When: beneficiary redeem

        // Then: redeem should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(sharesAllowed, receiver, owner);
        vm.stopPrank();
    }

    function testRevert_redeem_InsufficientShares(
        uint128 sharesMinted,
        uint128 sharesRedeemed,
        address owner,
        address receiver
    ) public {
        // Given: sharesMinted bigger than 0, sharesMinted less than sharesRedeemed, liquidityProvider mint sharesMinted
        vm.assume(sharesMinted > 0);
        vm.assume(sharesMinted < sharesRedeemed);

        vm.prank(liquidityProvider);
        tranche.mint(sharesMinted, owner);

        vm.startPrank(owner);
        // When: beneficiary redeem sharesRedeemed

        // Then: redeem should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        tranche.redeem(sharesRedeemed, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_redeem_ByOwner(uint128 sharesMinted, uint128 sharesRedeemed, address owner, address receiver)
        public
    {
        // Given: sharesMinted and sharesRedeemed bigger than 0, sharesMinted bigger than sharesRedeemed, receiver is not liquidityProvider, receiver is not pool
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));

        vm.prank(liquidityProvider);
        // When: liquidityProvider mint sharesMinted,owner redeem sharesRedeemed
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        tranche.redeem(sharesRedeemed, receiver, owner);

        // Then: owner maxWithdraw and maxRedeem, totalAssets, balanceOf pool should be equal to sharesMinted minus sharesRedeemed, balanceOf receiver should be equal to sharesRedeemed
        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }

    function testSuccess_redeem_ByLimitedAuthorisedAddress(
        uint128 sharesMinted,
        uint128 sharesAllowed,
        uint128 sharesRedeemed,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: sharesMinted and sharesRedeemed bigger than 0, sharesMinted bigger than equal sharesRedeemed, sharesAllowed bigger than equal sharesRedeemed,
        // receiver is not liquidityProvider, receiver is not pool, beneficiary is not owner
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(sharesAllowed >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        // When: liquidityProvider mint sharesMinted
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        // And: owner approve
        tranche.approve(beneficiary, sharesAllowed);

        vm.startPrank(beneficiary);
        // And: beneficiary redeem sharesRedeemed
        tranche.redeem(sharesRedeemed, receiver, owner);

        // Then: owner maxWithdraw and maxRedeem, totalAssets, balanceOf pool should be equal to sharesMinted minus sharesRedeemed, balanceOf receiver should be equal to sharesRedeemed
        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(tranche.allowance(owner, beneficiary), sharesAllowed - sharesRedeemed);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }

    function testSuccess_redeem_ByMaxAuthorisedAddress(
        uint128 sharesMinted,
        uint128 sharesRedeemed,
        address receiver,
        address owner,
        address beneficiary
    ) public {
        // Given: sharesMinted and sharesRedeemed bigger than 0, sharesMinted bigger sharesRedeemed, receiver is not liquidityProvider, receiver is not pool, beneficiary is not owner
        vm.assume(sharesMinted > 0);
        vm.assume(sharesRedeemed > 0);
        vm.assume(sharesMinted >= sharesRedeemed);
        vm.assume(receiver != liquidityProvider);
        vm.assume(receiver != address(pool));
        vm.assume(beneficiary != owner);

        vm.prank(liquidityProvider);
        // When: liquidityProvider mint sharesMinted
        tranche.mint(sharesMinted, owner);

        vm.prank(owner);
        // And: owner approve
        tranche.approve(beneficiary, type(uint256).max);

        vm.startPrank(beneficiary);
        // And: beneficiary redeem sharesRedeemed
        tranche.redeem(sharesRedeemed, receiver, owner);

        // Then: owner maxWithdraw and maxRedeem, totalAssets, balanceOf pool should be equal to sharesMinted minus sharesRedeemed, balanceOf receiver should be equal to sharesRedeemed
        assertEq(tranche.maxWithdraw(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.maxRedeem(owner), sharesMinted - sharesRedeemed);
        assertEq(tranche.totalAssets(), sharesMinted - sharesRedeemed);
        assertEq(tranche.allowance(owner, beneficiary), type(uint256).max);
        assertEq(asset.balanceOf(address(pool)), sharesMinted - sharesRedeemed);
        assertEq(asset.balanceOf(receiver), sharesRedeemed);
    }
}

/*//////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
//////////////////////////////////////////////////////////////*/
contract AccountingTest is TrancheTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
    }

    function testSuccess_totalAssets(uint128 assets) public {
        stdstore.target(address(pool)).sig(pool.realisedLiquidityOf.selector).with_key(address(tranche)).checked_write(
            assets
        );

        assertEq(tranche.totalAssets(), assets);
    }
}
