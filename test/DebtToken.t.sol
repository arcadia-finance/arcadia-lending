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

contract DebtTokenExtension is DebtToken {
    constructor(ERC20 asset_) DebtToken(asset_) {}

    function deposit_(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    function withdraw_(uint256 assets, address receiver, address owner_) public returns (uint256 shares) {
        shares = _withdraw(assets, receiver, owner_);
    }

    function totalAssets() public view override returns (uint256 totalDebt) {
        totalDebt = realisedDebt;
    }
}

abstract contract DebtTokenTest is Test {
    Asset asset;
    DebtTokenExtension debt;

    address creator = address(1);
    address tokenCreator = address(2);

    //Before
    constructor() {
        vm.prank(tokenCreator);
        asset = new Asset("Asset", "ASSET", 18);
    }

    //Before Each
    function setUp() public virtual {
        vm.prank(creator);
        debt = new DebtTokenExtension(asset);
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
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/

contract DepositWithdrawalTest is DebtTokenTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
    }

    function testRevert_deposit(uint256 assets, address receiver, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender deposits assets
        // Then: deposit should revert with DT_D: DEPOSIT_NOT_SUPPORTED
        vm.expectRevert("DT_D: DEPOSIT_NOT_SUPPORTED");
        debt.deposit(assets, receiver);
        vm.stopPrank();
    }

    function testRevert_deposit_ZeroShares(uint256 assets, address receiver, uint256 totalSupply, uint256 totalDebt)
        public
    {
        vm.assume(assets <= totalDebt);
        vm.assume(totalSupply > 0); //First mint new shares are issued equal to amount of assets -> error will not throw
        vm.assume(assets <= type(uint256).max / totalSupply); //Avoid overflow in next assumption

        //Will result in zero shares being created
        vm.assume(totalDebt > assets * totalSupply);

        stdstore.target(address(debt)).sig(debt.totalSupply.selector).checked_write(totalSupply);
        stdstore.target(address(debt)).sig(debt.realisedDebt.selector).checked_write(totalDebt);

        vm.expectRevert("DT_D: ZERO_SHARES");
        debt.deposit_(assets, receiver);
    }

    function testsuccess_deposit_FirstDeposit(uint256 assets, address receiver) public {
        vm.assume(assets > 0);

        debt.deposit_(assets, receiver);

        assertEq(debt.balanceOf(receiver), assets);
        assertEq(debt.totalSupply(), assets);
        assertEq(debt.realisedDebt(), assets);
    }

    function testSuccess_deposit_NotFirstDeposit(
        uint256 assets,
        address receiver,
        uint256 totalSupply,
        uint256 totalDebt
    ) public {
        vm.assume(assets <= totalDebt);
        vm.assume(assets <= type(uint256).max - totalDebt);
        vm.assume(assets > 0);
        vm.assume(totalSupply > 0); //Not first deposit
        vm.assume(assets <= type(uint256).max / totalSupply); //Avoid overflow in next assumption

        //One or more shares are created
        vm.assume(totalDebt <= assets * totalSupply);

        stdstore.target(address(debt)).sig(debt.totalSupply.selector).checked_write(totalSupply);
        stdstore.target(address(debt)).sig(debt.realisedDebt.selector).checked_write(totalDebt);

        uint256 shares = assets * totalSupply / totalDebt;
        vm.assume(shares <= type(uint256).max - totalSupply);

        debt.deposit_(assets, receiver);

        assertEq(debt.balanceOf(receiver), shares);
        assertEq(debt.totalSupply(), totalSupply + shares);
        assertEq(debt.realisedDebt(), totalDebt + assets);
    }

    function testRevert_mint(uint256 shares, address receiver, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender mint shares
        // Then: mint should revert with DT_M: MINT_NOT_SUPPORTED
        vm.expectRevert("DT_M: MINT_NOT_SUPPORTED");
        debt.mint(shares, receiver);
        vm.stopPrank();
    }

    function testRevert_withdraw(uint256 assets, address receiver, address owner, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender withdraw
        // Then: withdraw should revert with DT_W: WITHDRAW_NOT_SUPPORTED
        vm.expectRevert("DT_W: WITHDRAW_NOT_SUPPORTED");
        debt.withdraw(assets, receiver, owner);
        vm.stopPrank();
    }

    function testSuccess_withdraw(
        uint256 assetsWithdrawn,
        address owner,
        uint256 initialShares,
        uint256 totalSupply,
        uint256 totalDebt
    ) public {
        vm.assume(assetsWithdrawn <= totalDebt);
        vm.assume(totalDebt > 0);
        vm.assume(initialShares <= totalSupply);
        vm.assume(totalSupply > 0);
        vm.assume(assetsWithdrawn <= type(uint256).max / totalSupply); //Avoid overflow in next assumption

        uint256 sharesRedeemed = assetsWithdrawn * totalSupply / totalDebt;
        if (sharesRedeemed * totalDebt < assetsWithdrawn * totalSupply) {
            //Must round up
            sharesRedeemed += 1;
        }
        vm.assume(sharesRedeemed <= initialShares);

        stdstore.target(address(debt)).sig(debt.balanceOf.selector).with_key(owner).checked_write(initialShares);
        stdstore.target(address(debt)).sig(debt.totalSupply.selector).checked_write(totalSupply);
        stdstore.target(address(debt)).sig(debt.realisedDebt.selector).checked_write(totalDebt);

        debt.withdraw_(assetsWithdrawn, owner, owner);

        assertEq(debt.balanceOf(owner), initialShares - sharesRedeemed);
        assertEq(debt.totalSupply(), totalSupply - sharesRedeemed);
        assertEq(debt.realisedDebt(), totalDebt - assetsWithdrawn);
    }

    function testRevert_redeem(uint256 shares, address receiver, address owner, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender redeem shares
        // Then: redeem should revert with DT_R: REDEEM_NOT_SUPPORTED
        vm.expectRevert("DT_R: REDEEM_NOT_SUPPORTED");
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
        // Then: approve should revert with DT_A: APPROVE_NOT_SUPPORTED
        vm.expectRevert("DT_A: APPROVE_NOT_SUPPORTED");
        debt.approve(spender, amount);
        vm.stopPrank();
    }

    function testRevert_transfer(address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender transfer
        // Then: transfer should revert with DT_T: TRANSFER_NOT_SUPPORTED
        vm.expectRevert("DT_T: TRANSFER_NOT_SUPPORTED");
        debt.transfer(to, amount);
        vm.stopPrank();
    }

    function testRevert_transferFrom(address from, address to, uint256 amount, address sender) public {
        // Given: all neccesary contracts are deployed on the setup

        vm.startPrank(sender);
        // When: sender transferFrom
        // Then: transferFrom should revert with DT_TF: TRANSFERFROM_NOT_SUPPORTED
        vm.expectRevert("DT_TF: TRANSFROM_NOT_SUPPORTED");
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
        // Then: permit should revert with DT_TP: PERMIT_NOT_SUPPORTED
        vm.expectRevert("DT_TP: PERMIT_NOT_SUPPORTED");
        debt.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }
}
