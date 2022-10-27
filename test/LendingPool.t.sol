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
//import "./utils/InterestRateTestUtils.sol";

contract LendingPoolExtension is LendingPool {
    //Extensions to test internal functions
    constructor(ERC20 _asset, address _treasury, address _vaultFactory) LendingPool(_asset, _treasury, _vaultFactory) {}

    function testPopTranche(uint256 index, address tranche) public {
        _popTranche(index, tranche);
    }

    function testSyncInterestsToLendingPool(uint256 assets) public onlyOwner {
        _syncInterestsToLiquidityProviders(assets);
    }

    function testProcessDefault(uint256 assets) public onlyOwner {
        _processDefault(assets);
    }
}

abstract contract LendingPoolTest is Test {
    Asset asset;
    Factory factory;
    LendingPoolExtension pool;
    Tranche srTranche;
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
        pool = new LendingPoolExtension(asset, treasury, address(factory));
        srTranche = new Tranche(address(pool), "Senior", "SR");
        jrTranche = new Tranche(address(pool), "Junior", "JR");
        vm.stopPrank();

        debt = DebtToken(address(pool));
    }

    //Helper functions
    function calcUnrealisedDebtChecked(uint64 interestRate, uint24 deltaBlocks, uint256 realisedDebt)
        internal
        view
        returns (uint256 unrealisedDebt)
    {
        uint256 base = 1e18 + uint256(interestRate);
        uint256 exponent = uint256(deltaBlocks) * 1e18 / pool.YEARLY_BLOCKS();
        unrealisedDebt = (uint256(realisedDebt) * (LogExpMath.pow(base, exponent) - 1e18)) / 1e18;
    }
}

/*//////////////////////////////////////////////////////////////
                        DEPLOYMENT
//////////////////////////////////////////////////////////////*/
contract DeploymentTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();
    }

    function testSuccess_deployment() public {
        assertEq(pool.name(), string("Arcadia Asset Debt"));
        assertEq(pool.symbol(), string("darcASSET"));
        assertEq(pool.decimals(), 18);
        assertEq(pool.vaultFactory(), address(factory));
        assertEq(pool.treasury(), treasury);
    }
}

/*//////////////////////////////////////////////////////////////
                        TRANCHES LOGIC
//////////////////////////////////////////////////////////////*/
contract TranchesTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_addTranche_InvalidOwner(address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not the creator
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress calls addTranche
        // Then: addTranche should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.addTranche(address(srTranche), 50);
        vm.stopPrank();
    }

    function testSuccess_addTranche_SingleTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator calls addTranche with srTranche as Tranche address and 50 as weight
        pool.addTranche(address(srTranche), 50);

        // Then: pool totalWeight should be equal to 50, weights 0 should be equal to 50,
        // weight of srTranche should be equal to 50, tranches 0 should be equal to srTranche, 
        // isTranche for srTranche should return true
        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.weight(address(srTranche)), 50);
        assertEq(pool.tranches(0), address(srTranche));
        assertTrue(pool.isTranche(address(srTranche)));
    }

    function testRevert_addTranche_SingleTrancheTwice() public {
        // Given: creator calls addTranche with srTranche and 50
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        // When: creator calls addTranche again with srTranche and 40

        // Then: addTranche should revert with TR_AD: Already exists
        vm.expectRevert("TR_AD: Already exists");
        pool.addTranche(address(srTranche), 40);
        vm.stopPrank();
    }

    function testSuccess_addTranche_MultipleTranches() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator calls addTranche for srTranche and jrTranche with 50 and 40 weights
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        // Then: pool totalWeight should be equal to 90, weights index 0 should be equal to 50,
        // weights index 1 should be equal to 40, weight of srTranche should be equal to 50,
        // weight of jrTranche should be equal to 40, tranches index 0 should be equal to srTranche,
        // tranches index 1 should be equal to jrTranche, isTranche should return true for both srTranche and jrTranche
        assertEq(pool.totalWeight(), 90);
        assertEq(pool.weights(0), 50);
        assertEq(pool.weights(1), 40);
        assertEq(pool.weight(address(srTranche)), 50);
        assertEq(pool.weight(address(jrTranche)), 40);
        assertEq(pool.tranches(0), address(srTranche));
        assertEq(pool.tranches(1), address(jrTranche));
        assertTrue(pool.isTranche(address(srTranche)));
        assertTrue(pool.isTranche(address(jrTranche)));
    }

    function testRevert_setWeight_InvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setWeight
        // Then: setWeight should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testRevert_setWeight_InexistingTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator setWeight on index 0
        // Then: setWeight should revert with TR_SW: Inexisting Tranche
        vm.expectRevert("TR_SW: Inexisting Tranche");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testSuccess_setWeight() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator calls addTranche with srTranche and 50, calss setWeight with 0 and 40
        pool.addTranche(address(srTranche), 50);
        pool.setWeight(0, 40);
        vm.stopPrank();

        // Then: totalWeight should be equal to 40, weights index 0 should return 40, weight of srTranche should return 40
        assertEq(pool.totalWeight(), 40);
        assertEq(pool.weights(0), 40);
        assertEq(pool.weight(address(srTranche)), 40);
    }

    function testSuccess_popTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator calls addTranche with srTranche and 50, jrTranche and 40
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        // And: calls testPopTranche with 1 and jrTranche
        pool.testPopTranche(1, address(jrTranche));

        // Then: pool totalWeight should be equal to 50, weights index 0 should be equal to 50,
        // tranches index 0 should be equal to srTranche, isTranche should return true for srTranche,
        // isTranche should return false for jrTranche
        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.tranches(0), address(srTranche));
        assertTrue(pool.isTranche(address(srTranche)));
        assertTrue(!pool.isTranche(address(jrTranche)));
    }
}

/*//////////////////////////////////////////////////////////////
                PROTOCOL FEE CONFIGURATION
//////////////////////////////////////////////////////////////*/
contract ProtocolFeeTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_setFeeWeight_InvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setFeeWeight

        // Then: setFeeWeight should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setFeeWeight(5);
        vm.stopPrank();
    }

    function testSuccess_setFeeWeight() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator addTranche with 50 weight, setFeeWeight 5
        pool.addTranche(address(srTranche), 50);
        pool.setFeeWeight(5);
        vm.stopPrank();

        // Then: totalWeight should be equal to 55, feeWeight should be equal to 5
        assertEq(pool.totalWeight(), 55);
        assertEq(pool.feeWeight(), 5);

        vm.startPrank(creator);
        // When: creator setFeeWeight 10
        pool.setFeeWeight(10);
        vm.stopPrank();

        // Then: totalWeight should be equal to 60, feeWeight should be equal to 10
        assertEq(pool.totalWeight(), 60);
        assertEq(pool.feeWeight(), 10);
    }

    //setTreasury
    function testRevert_setTreasury_InvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress calls setTreasury
        // Then: setTreasury should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setTreasury(creator);
        vm.stopPrank();
    }

    function testSuccess_setTreasury() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator setTreasury with creator address input
        pool.setTreasury(creator);
        vm.stopPrank();

        // Then: treasury should creators address
        assertEq(pool.treasury(), creator);
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
//////////////////////////////////////////////////////////////*/
contract DepositAndWithdrawalTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();
    }

    //deposit (without debt -> ignore _syncInterests() and _updateInterestRate())
    function testRevert_deposit_ByNonTranche(address unprivilegedAddress, uint128 assets, address from) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != address(jrTranche));
        vm.assume(unprivilegedAddress != address(srTranche));

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress deposit
        // Then: deposit should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.depositInLendingPool(assets, from);
        vm.stopPrank();
    }

    function testSuccess_deposit_FirstDepositByTranche(uint256 amount) public {
        // Given: liquidityProvider approve max value
        vm.assume(amount > 0);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit
        pool.depositInLendingPool(amount, liquidityProvider);

        // Then: supplyBalances srTranche should be amount, totatlSupply should be amount, supplyBalances pool should be amount
        assertEq(pool.realisedLiquidityOf(address(srTranche)), amount);
        assertEq(pool.totalRealisedLiquidity(), amount);
        assertEq(asset.balanceOf(address(pool)), amount);
    }

    function testSuccess_deposit_MultipleDepositsByTranches(uint256 amount0, uint256 amount1) public {
        // Given: totalAmount is amount0 added by amount1, liquidityProvider approve max value
        vm.assume(amount0 > 0);
        vm.assume(amount1 > 0);
        vm.assume(amount0 <= type(uint256).max - amount1);

        uint256 totalAmount = uint256(amount0) + uint256(amount1);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit amount0, jrTranche deposit amount1
        pool.depositInLendingPool(amount0, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.depositInLendingPool(amount1, liquidityProvider);

        // Then: supplyBalances jrTranche should be amount1, totalSupply should be totalAmount, supplyBalances pool should be totalAmount
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), amount1);
        assertEq(pool.totalRealisedLiquidity(), totalAmount);
        assertEq(asset.balanceOf(address(pool)), totalAmount);
    }

    function testRevert_withdraw_Unauthorised(uint256 assetsWithdrawn, address receiver, address unprivilegedAddress)
        public
    {
        // Given: unprivilegedAddress is not srTranche, liquidityProvider approve max value
        vm.assume(unprivilegedAddress != address(srTranche));
        vm.assume(assetsWithdrawn > 0);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit assetsWithdrawn
        pool.depositInLendingPool(assetsWithdrawn, liquidityProvider);

        vm.startPrank(unprivilegedAddress);
        // Then: withdraw by unprivilegedAddress should revert with LP_W: UNAUTHORIZED
        vm.expectRevert("LP_WFLP: Amount exceeds balance");
        pool.withdrawFromLendingPool(assetsWithdrawn, receiver);
        vm.stopPrank();
    }

    function testRevert_withdraw_InsufficientAssets(uint256 assetsDeposited, uint256 assetsWithdrawn, address receiver)
        public
    {
        // Given: assetsWithdrawn bigger than assetsDeposited, liquidityProvider approve max value
        vm.assume(assetsDeposited > 0);
        vm.assume(assetsWithdrawn > 0);
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        // When: srTranche deposit assetsDeposited
        pool.depositInLendingPool(assetsDeposited, liquidityProvider);

        // Then: withdraw assetsWithdrawn should revert
        vm.expectRevert("LP_WFLP: Amount exceeds balance");
        pool.withdrawFromLendingPool(assetsWithdrawn, receiver);
        vm.stopPrank();
    }

//Ask
    function testSuccess_withdraw(uint256 assetsDeposited, uint256 assetsWithdrawn, address receiver) public {
        // Given: assetsWithdrawn less than assetsDeposited, receiver is not pool or liquidityProvider,
        // liquidityProvider approve max value, assetsDeposited and assetsWithdrawn are bigger than 0
        vm.assume(receiver != address(pool));
        vm.assume(receiver != liquidityProvider);
        vm.assume(assetsDeposited > 0 );
        vm.assume(assetsWithdrawn > 0 );
        vm.assume(assetsDeposited > assetsWithdrawn);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        // When: srTranche deposit and withdraw
        pool.depositInLendingPool(assetsDeposited, liquidityProvider);

        pool.withdrawFromLendingPool(assetsWithdrawn, receiver);
        vm.stopPrank();

        // Then: supplyBalances srTranche, pool and totalSupply should be assetsDeposited minus assetsWithdrawn,
        // supplyBalances receiver should be assetsWithdrawn
        assertEq(pool.realisedLiquidityOf(address(srTranche)), assetsDeposited - assetsWithdrawn);
        assertEq(pool.totalRealisedLiquidity(), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }
}

/*//////////////////////////////////////////////////////////////
                    LENDING LOGIC
//////////////////////////////////////////////////////////////*/
contract LendingLogicTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();
    }

    //approveBeneficiary
    function testRevert_approveBeneficiary_NonVault(address beneficiary, uint256 amount, address nonVault) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: approveBeneficiary with nonVault input on vault

        // Then: approveBeneficiary should revert with "LP_AB: Not a vault"
        vm.expectRevert("LP_AB: Not a vault");
        pool.approveBeneficiary(beneficiary, amount, nonVault);
    }

    function testRevert_approveBeneficiary_Unauthorised(
        address beneficiary,
        uint256 amount,
        address unprivilegedAddress
    ) public {
        // Given: unprivilegedAddress is not vaultOwner
        vm.assume(unprivilegedAddress != vaultOwner);

        vm.startPrank(unprivilegedAddress);
        // When: approveBeneficiary as unprivilegedAddress

        // Then: approveBeneficiary should revert with "LP_AB: UNAUTHORIZED"
        vm.expectRevert("LP_AB: UNAUTHORIZED");
        pool.approveBeneficiary(beneficiary, amount, address(vault));
        vm.stopPrank();
    }

    function testSuccess_approveBeneficiary(address beneficiary, uint256 amount) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(vaultOwner);
        // When: approveBeneficiary as vaultOwner
        pool.approveBeneficiary(beneficiary, amount, address(vault));

        // Then: creditAllowance should be equal to amount
        assertEq(pool.creditAllowance(address(vault), beneficiary), amount);
    }

    function testRevert_borrow_NonVault(uint256 amount, address nonVault, address to) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: borrow as nonVault

        // Then: borrow should revert with "LP_B: Not a vault"
        vm.expectRevert("LP_B: Not a vault");
        pool.borrow(amount, nonVault, to);
    }

    function testRevert_borrow_Unauthorised(uint256 amount, address beneficiary, address to) public {
        // Given: beneficiary is not vaultOwner, amount is bigger than 0
        vm.assume(beneficiary != vaultOwner);

        //emit log_named_uint("amountAllowed", pool.creditAllowance(address(vault), beneficiary));

        vm.assume(amount > 0);
        vm.startPrank(beneficiary);
        // When: borrow as beneficiary

        // Then: borrow should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        pool.borrow(amount, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_borrow_InsufficientApproval(
        uint256 amountAllowed,
        uint256 amountLoaned,
        address beneficiary,
        address to
    ) public {
        // Given: beneficiary is not vaultOwner, amountAllowed is less than amountLoaned, vaultOwner approveBeneficiary
        vm.assume(beneficiary != vaultOwner);
        vm.assume(amountAllowed < amountLoaned);

        vm.prank(vaultOwner);
        pool.approveBeneficiary(beneficiary, amountAllowed, address(vault));

        vm.startPrank(beneficiary);
        // When: borrow as beneficiary

        // Then: borrow should revert with stdError.arithmeticError
        vm.expectRevert(stdError.arithmeticError);
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_borrow_InsufficientCollateral(uint256 amountLoaned, uint256 collateralValue, address to)
        public
    {
        // Given: collateralValue is less than amountLoaned, vault setTotalValue to colletrallValue
        vm.assume(collateralValue < amountLoaned);

        vault.setTotalValue(collateralValue);

        vm.startPrank(vaultOwner);
        // When: borrow amountLoaned as vaultOwner

        // Then: borrow should revert with "LP_B: Reverted"
        vm.expectRevert("LP_B: Reverted");
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_borrow_InsufficientLiquidity(
        uint256 amountLoaned,
        uint256 collateralValue,
        uint256 liquidity,
        address to
    ) public {
        // Given: collateralValue less than equal to amountLoaned, liquidity is bigger than 0 but less than amountLoaned,
        // to is not address 0, creator setDebtToken to debt, liquidityProvider approve pool to max value,
        // srTranche deposit liquidity, setTotalValue to colletralValue
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity < amountLoaned);
        vm.assume(liquidity > 0);
        vm.assume(to != address(0));

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);
        vault.setTotalValue(collateralValue);

        vm.startPrank(vaultOwner);
        // When: borrow amountLoaned as vaultOwner

        // Then: borrow should revert with "TRANSFER_FAILED"
        vm.expectRevert("TRANSFER_FAILED");
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testSuccess_borrow_ByVaultOwner(
        uint256 amountLoaned,
        uint256 collateralValue,
        uint256 liquidity,
        address to
    ) public {
        // Given: collateralValue and liquidity bigger than equal to amountLoaned, amountLoaned is bigger than 0,
        // to is not address 0 and not liquidityProvider, creator setDebtToken to debt, setTotalValue to colletralValue,
        // liquidityProvider approve pool to max value, srTranche deposit liquidity
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity >= amountLoaned);
        vm.assume(amountLoaned > 0);
        vm.assume(to != address(0));
        vm.assume(to != liquidityProvider);

        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);

        vm.startPrank(vaultOwner);
        // When: vaultOwner borrow amountLoaned
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();

        // Then: balanceOf pool should be equal to liquidity minus amountLoaned, balanceOf "to" should be equal to amountLoaned,
        // balanceOf vault should be equal to amountLoaned
        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
    }

    function testSuccess_borrow_ByLimitedAuthorisedAddress(
        uint256 amountAllowed,
        uint256 amountLoaned,
        uint256 collateralValue,
        uint256 liquidity,
        address beneficiary,
        address to
    ) public {
        // Given: amountAllowed, collateralValue and liquidity bigger than equal to amountLoaned, amountLoaned is bigger than 0,
        // amountAllowed is less than max value, beneficiary is not vaultOwner, to is not address 0 and not liquidityProvider,
        // creator setDebtToken to debt, liquidityProvider approve pool to max value, srTranche deposit liquidity,
        // vaultOwner approveBeneficiary
        vm.assume(amountAllowed >= amountLoaned);
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity >= amountLoaned);
        vm.assume(amountLoaned > 0);
        vm.assume(amountAllowed < type(uint256).max);
        vm.assume(beneficiary != vaultOwner);
        vm.assume(to != address(0));
        vm.assume(to != liquidityProvider);

        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);
        vm.prank(vaultOwner);
        pool.approveBeneficiary(beneficiary, amountAllowed, address(vault));

        vm.startPrank(beneficiary);
        // When: beneficiary borrow amountLoaned
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();

        // Then: balanceOf pool should be equal to liquidity minus amountLoaned, balanceOf "to" should be equal to amountLoaned,
        // balanceOf vault should be equal to amountLoaned, creditAllowance should be equal to amountAllowed minus amountLoaned
        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
        assertEq(pool.creditAllowance(address(vault), beneficiary), amountAllowed - amountLoaned);
    }

    function testSuccess_borrow_ByMaxAuthorisedAddress(
        uint256 amountLoaned,
        uint256 collateralValue,
        uint256 liquidity,
        address beneficiary,
        address to
    ) public {
        // Given: collateralValue and liquidity bigger than equal to amountLoaned, amountLoaned is bigger than 0,
        // beneficiary is not vaultOwner, to is not address 0 and not liquidityProvider,
        // creator setDebtToken to debt, setTotalValue to collateralValue, liquidityProvider approve pool to max value,
        // srTranche deposit liquidity, vaultOwner approveBeneficiary
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity >= amountLoaned);
        vm.assume(amountLoaned > 0);
        vm.assume(beneficiary != vaultOwner);
        vm.assume(to != address(0));
        vm.assume(to != liquidityProvider);

        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);
        vm.prank(vaultOwner);
        pool.approveBeneficiary(beneficiary, type(uint256).max, address(vault));

        vm.startPrank(beneficiary);
        // When: beneficiary borrow
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();

        // Then: balanceOf pool should be equal to liquidity minus amountLoaned, balanceOf "to" should be equal to amountLoaned,
        // balanceOf vault should be equal to amountLoaned, creditAllowance should be equal to max value
        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
        assertEq(pool.creditAllowance(address(vault), beneficiary), type(uint256).max);
    }

    function testRevert_repay_NonVault(uint256 amount, address nonVault) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: repay amount to nonVault

        // Then: repay should revert with "LP_R: Not a vault"
        vm.expectRevert("LP_R: Not a vault");
        pool.repay(amount, nonVault);
    }

    function testRevert_repay_InsufficientFunds(uint128 amountLoaned, uint256 availablefunds, address sender) public {
        // Given: amountLoaned is bigger than availablefunds, availablefunds bigger than 0,
        // sender is not zero address, liquidityProvider or vaultOwner, creator setDebtToken to debt,
        // setTotalValue to amountLoaned, liquidityProvider approve max value, transfer availablefunds,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(amountLoaned > availablefunds);
        vm.assume(availablefunds > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);

        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, availablefunds);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.depositInLendingPool(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        asset.approve(address(pool), type(uint256).max);
        // When: sender repays amountLoaned which is more than his available funds
        // Then: repay should revert with an ovcerflow
        vm.expectRevert(stdError.arithmeticError);
        pool.repay(amountLoaned, address(vault));
        vm.stopPrank();
    }

    function testSuccess_repay_AmountInferiorLoan(uint128 amountLoaned, uint256 amountRepaid, address sender) public {
        // Given: amountLoaned is bigger than amountRepaid, amountRepaid bigger than 0,
        // sender is not zero address, liquidityProvider, vaultOwner or pool, creator setDebtToken to debt,
        // setTotalValue to amountLoaned, liquidityProvider approve max value, transfer amountRepaid,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(amountLoaned > amountRepaid);
        vm.assume(amountRepaid > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);
        vm.assume(sender != address(pool));

        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, amountRepaid);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.depositInLendingPool(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        // When: sender approve pool with max value, repay amountRepaid
        asset.approve(address(pool), type(uint256).max);
        pool.repay(amountRepaid, address(vault));
        vm.stopPrank();

        // Then: balanceOf pool should be equal to amountRepaid, balanceOf sender should be equal to 0,
        // balanceOf vault should be equal to amountLoaned minus amountRepaid
        assertEq(asset.balanceOf(address(pool)), amountRepaid);
        assertEq(asset.balanceOf(sender), 0);
        assertEq(debt.balanceOf(address(vault)), amountLoaned - amountRepaid);
    }

    function testSuccess_Repay_ExactAmount(uint128 amountLoaned, address sender) public {
        // Given: amountLoaned is bigger than 0, sender is not zero address, liquidityProvider, vaultOwner or pool,
        // creator setDebtToken to debt, setTotalValue to amountLoaned, liquidityProvider approve max value, transfer amountRepaid,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(amountLoaned > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);
        vm.assume(sender != address(pool));

        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, amountLoaned);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.depositInLendingPool(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        // When: sender approve pool with max value, repay amountLoaned
        asset.approve(address(pool), type(uint256).max);
        pool.repay(amountLoaned, address(vault));
        vm.stopPrank();

        // Then: balanceOf pool should be equal to amountLoaned, balanceOf sender and vault should be equal to 0
        assertEq(asset.balanceOf(address(pool)), amountLoaned);
        assertEq(asset.balanceOf(sender), 0);
        assertEq(debt.balanceOf(address(vault)), 0);
    }

    function testSuccess_repay_AmountExceedingLoan(uint128 amountLoaned, uint128 availablefunds, address sender)
        public
    {
        // Given: availablefunds is bigger than amountLoaned, amountLoaned bigger than 0,
        // sender is not zero address, liquidityProvider, vaultOwner or pool, creator setDebtToken to debt,
        // setTotalValue to amountLoaned, liquidityProvider approve max value, transfer availablefunds,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(availablefunds > amountLoaned);
        vm.assume(amountLoaned > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);
        vm.assume(sender != address(pool));

        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, availablefunds);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.depositInLendingPool(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        // When: sender approve pool with max value, repay availablefunds
        asset.approve(address(pool), type(uint256).max);
        pool.repay(availablefunds, address(vault));
        vm.stopPrank();

        // Then: balanceOf pool should be equal to amountLoaned, balanceOf sender should be equal to availablefunds minus amountLoaned,
        // balanceOf vault should be equal to 0
        assertEq(asset.balanceOf(address(pool)), amountLoaned);
        assertEq(asset.balanceOf(sender), availablefunds - amountLoaned);
        assertEq(debt.balanceOf(address(vault)), 0);
    }
}

/*//////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
//////////////////////////////////////////////////////////////*/
contract InterestsTest is LendingPoolTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();
    }

    function testSuccess_syncInterestsToLiquidityProviders_Exact() public {
        // Given: all necessary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator testSyncInterestsToLendingPool with 100
        pool.testSyncInterestsToLendingPool(100);

        // Then: supplyBalances srTranche should be equal to 50, supplyBalances jrTranche should be equal to 40,
        // supplyBalances treasury should be equal to 10, totalSupply should be equal to 100
        assertEq(pool.realisedLiquidityOf(address(srTranche)), 50);
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), 40);
        assertEq(pool.realisedLiquidityOf(address(treasury)), 10);
        assertEq(pool.totalRealisedLiquidity(), 100);
    }

    function testSuccess_syncInterestsToLiquidityProviders_Rounded() public {
        // Given: all necessary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator testSyncInterestsToLendingPool with 99
        pool.testSyncInterestsToLendingPool(99);

        // Then: supplyBalances srTranche should be equal to 50, supplyBalances jrTranche should be equal to 40,
        // supplyBalances treasury should be equal to 9, totalRealisedLiquidity should be equal to 99
        assertEq(pool.realisedLiquidityOf(address(srTranche)), 50);
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), 40);
        assertEq(pool.realisedLiquidityOf(address(treasury)), 9);
        assertEq(pool.totalRealisedLiquidity(), 99);
    }

    function testSuccess_calcUnrealisedDebt_Unchecked(uint24 deltaBlocks, uint128 realisedDebt)
        public
    {
        // Given: deltaBlocks smaller than equal to 5 years, 
        // realisedDebt smaller than equal to than 3402823669209384912995114146594816
        vm.assume(deltaBlocks <= 13140000); //5 year
        vm.assume(realisedDebt <= type(uint128).max / (10 ** 5)); //highest possible debt at 1000% over 5 years: 3402823669209384912995114146594816

        // And: the interest rate is interestRate
        uint64 interestRate = pool.interestRate();
        uint256 loc = stdstore.target(address(pool)).sig(pool.interestRate.selector).find();
        bytes32 slot = bytes32(loc);
        //interestRate and lastSyncedBlock are packed in same slot -> encode packen and bitshift to the right
        bytes32 value = bytes32(abi.encodePacked(uint24(block.number), interestRate));
        value = value >> 168;
        vm.store(address(pool), slot, value);

        // And: the vaultOwner takes realisedDebt debt
        loc = stdstore.target(address(debt)).sig(debt.realisedDebt.selector).find();
        slot = bytes32(loc);
        value = bytes32(abi.encode(realisedDebt));
        vm.store(address(debt), slot, value);

        // When: deltaBlocks have passed
        vm.roll(block.number + deltaBlocks);

        // Then: Unrealised debt should never overflow (-> calcUnrealisedDebtChecked does never error and same calculation unched are always equal)
        uint256 expectedValue = calcUnrealisedDebtChecked(interestRate, deltaBlocks, realisedDebt);
        uint256 actualValue = pool.calcUnrealisedDebt();
        assertEq(expectedValue, actualValue);
    }

    function testSucces_syncInterests(uint24 deltaBlocks, uint128 realisedDebt) public {
        // Given: deltaBlocks than 5 years, realisedDebt than 3402823669209384912995114146594816 and bigger than 0
        vm.assume(deltaBlocks <= 13140000); //5 year
        vm.assume(realisedDebt <= type(uint128).max / (10 ** 5)); //highest possible debt at 1000% over 5 years: 3402823669209384912995114146594816
        vm.assume(realisedDebt > 0);

        // And: the vaultOwner takes realisedDebt debt
        vault.setTotalValue(realisedDebt);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(realisedDebt, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(realisedDebt, address(vault), address(vault));

        // And: deltaBlocks have passed
        vm.roll(block.number + deltaBlocks);

        // When: Intersts are synced
        pool.syncInterests();

        uint64 interestRate = pool.interestRate();
        uint256 interests = calcUnrealisedDebtChecked(interestRate, deltaBlocks, realisedDebt);

        // Then: Total redeemable interest of LP providers and total open debt of borrowers should increase with interests
        assertEq(pool.totalRealisedLiquidity(), realisedDebt + interests);
        assertEq(debt.maxWithdraw(address(vault)), realisedDebt + interests);
        assertEq(debt.maxRedeem(address(vault)), realisedDebt);
        assertEq(debt.totalAssets(), realisedDebt + interests);
    }
}

/*//////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
//////////////////////////////////////////////////////////////*/
contract AccountingTest is LendingPoolTest {
    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        vm.prank(vaultOwner);
        vault = Vault(factory.createVault(1));

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
    }

    function testSuccess_totalAssets(
        uint128 realisedDebt, 
        uint128 initialLiquidity, 
        uint24 deltaBlocks
        ) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(initialLiquidity >= realisedDebt);
        vm.assume(realisedDebt > 0);
        vm.assume(deltaBlocks <= 13140000); //5 year

        vm.prank(address(srTranche));
        pool.depositInLendingPool(type(uint128).max, liquidityProvider);
        vm.prank(creator);
        //pool.updateInterestRate();
        vault.setTotalValue(realisedDebt);

        vm.prank(vaultOwner);
        pool.borrow(realisedDebt, address(vault), vaultOwner);

        vm.roll(block.number + deltaBlocks);
        uint64 interestRate = pool.interestRate();
        uint256 unrealisedDebt = calcUnrealisedDebtChecked(interestRate, deltaBlocks, realisedDebt);
        uint256 expectedValue = realisedDebt + unrealisedDebt;

        uint256 actualValue = debt.totalAssets();

        assertEq(actualValue, expectedValue);
    }

    function testSuccess_liquidityOf(
        uint24 deltaBlocks,
        uint256 realisedDebt,
        uint256 initialLiquidity
    ) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(deltaBlocks <= 13140000); //5 year
        vm.assume(realisedDebt > 0);
        vm.assume(initialLiquidity >= realisedDebt);

        vm.prank(address(srTranche));
        pool.depositInLendingPool(initialLiquidity, liquidityProvider);
        vault.setTotalValue(realisedDebt);

        vm.prank(vaultOwner);
        pool.borrow(realisedDebt, address(vault), vaultOwner);

        // When: 
        vm.roll(block.number + deltaBlocks);
        uint64 interestRate = pool.interestRate();
        uint256 unrealisedDebt = calcUnrealisedDebtChecked(interestRate, deltaBlocks, realisedDebt);
        uint256 interest = unrealisedDebt * 50 / 90;
        if (interest * 90 < unrealisedDebt * 50) interest += 1; // interest for a tranche is rounded up
        uint256 expectedValue = initialLiquidity + interest;

        uint256 actualValue = pool.liquidityOf(address(srTranche));

        assertEq(actualValue, expectedValue);
    }

}
/* //////////////////////////////////////////////////////////////
                        INTERESTS LOGIC
////////////////////////////////////////////////////////////// */

/* //////////////////////////////////////////////////////////////
                    INTEREST RATE LOGIC
////////////////////////////////////////////////////////////// */

/*//////////////////////////////////////////////////////////////
                    LIQUIDATION LOGIC
//////////////////////////////////////////////////////////////*/
contract DefaultTest is LendingPoolTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        //Set Tranche weight on 0 so that all yield goes to treasury
        pool.addTranche(address(srTranche), 0);
        pool.addTranche(address(jrTranche), 0);
        vm.stopPrank();

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();
    }

    function testRevert_setLiquidator_Unauthorised(address liquidator_, address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not the Owner
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);

        // When: unprivilegedAddress sets the Liquidator
        // Then: setLiquidator should revert with "UNAUTHORIZED"
        vm.expectRevert("UNAUTHORIZED");
        pool.setLiquidator(liquidator_);
        vm.stopPrank();
    }

    function testSuccess_setLiquidator(address liquidator_) public {
        // Given: all neccesary contracts are deployed on the setup

        // When: The owner sets the Liquidator
        vm.prank(creator);
        pool.setLiquidator(liquidator_);

        // Then: The liquidator should be equal to liquidator_
        assertEq(liquidator_, pool.liquidator());
    }

    function testRevert_liquidateVault_Unauthorised(uint256 amountLoaned, address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not the liquidator
        vm.assume(unprivilegedAddress != liquidator);
        // And: The liquidator is set
        vm.prank(creator);
        pool.setLiquidator(liquidator);

        vm.startPrank(unprivilegedAddress);

        // When: unprivilegedAddress liquidates a vault
        // Then: setLiquidator should revert with "UNAUTHORIZED"
        vm.expectRevert("UNAUTHORIZED");
        pool.liquidateVault(address(vault), amountLoaned);
        vm.stopPrank();
    }

    function testSuccess_liquidateVault(uint128 amountLoaned) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(amountLoaned > 0);
        // And: A vault has debt
        vault.setTotalValue(amountLoaned);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.depositInLendingPool(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);
        // And: The liquidator is set
        vm.prank(creator);
        pool.setLiquidator(liquidator);

        // When: liquidator liquidates a vault
        vm.prank(liquidator);
        pool.liquidateVault(address(vault), amountLoaned);

        // Then: The debt of the vault should be zero
        assertEq(debt.balanceOf(address(vault)), 0);
        assertEq(debt.totalSupply(), 0);
    }

    function testRevert_settleLiquidation_Unauthorised(
        uint256 defaultAmount,
        uint256 deficitAmount,
        address unprivilegedAddress
    ) public {
        // Given: The liquidator is set
        vm.prank(creator);
        pool.setLiquidator(liquidator);
        // And: unprivilegedAddress is not the liquidator
        vm.assume(unprivilegedAddress != liquidator);

        vm.startPrank(unprivilegedAddress);

        // When: unprivilegedAddress settles a liquidation
        // Then: settleLiquidation should revert with "UNAUTHORIZED"
        vm.expectRevert("UNAUTHORIZED");
        pool.settleLiquidation(defaultAmount, deficitAmount);
        vm.stopPrank();
    }

    function testSuccess_settleLiquidation_ProcessDefault(uint256 defaultAmount, uint256 liquidity) public {
        // Given: provided liquidity is bigger than the default amount (Should always be true)
        vm.assume(liquidity > 0);
        vm.assume(liquidity >= defaultAmount);
        // And: Liquidity is deposited in Lending Pool
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);
        // And: The liquidator is set
        vm.prank(creator);
        pool.setLiquidator(liquidator);

        // When: Liquidator settles a liquidation
        vm.prank(liquidator);
        pool.settleLiquidation(defaultAmount, 0);

        // Then: The default amount should be discounted from the most junior tranche
        assertEq(pool.realisedLiquidityOf(address(srTranche)), liquidity - defaultAmount);
        assertEq(pool.totalRealisedLiquidity(), liquidity - defaultAmount);
    }

    function testSuccess_settleLiquidation_ProcessDeficit(
        uint256 defaultAmount,
        uint256 deficitAmount,
        uint256 liquidity
    ) public {
        // Given: Provided liquidity is bigger than the default amount (Sould always be true)
        vm.assume(liquidity >= defaultAmount);
        // And: Available liquidity is bigger than the deficit amount (ToDo: unhappy flow!!!)
        vm.assume(liquidity >= deficitAmount);
        // And: Liquidity is bigger than zero
        vm.assume(liquidity > 0);
        // And: Liquidity is deposited in Lending Pool
        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquidity, liquidityProvider);
        // And: The liquidator is set
        vm.prank(creator);
        pool.setLiquidator(liquidator);

        // When: Liquidator settles a liquidation
        vm.prank(liquidator);
        pool.settleLiquidation(defaultAmount, deficitAmount);

        // Then: The deficit amount should be transferred to the Liquidator
        assertEq(asset.balanceOf(liquidator), deficitAmount);
    }

    function testSuccess_processDefault_OneTranche(
        uint256 liquiditySenior,
        uint256 liquidityJunior,
        uint256 defaultAmount
    ) public {
        // Given: defaultAmount, liquidityJunior and liquiditySenior bigger than 0,
        // srTranche calls depositInLendingPool for liquiditySenior, jrTranche calls depositInLendingPool for liquidityJunior
        vm.assume(defaultAmount > 0);
        vm.assume(liquidityJunior > 0);
        vm.assume(liquiditySenior > 0);
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount < liquidityJunior);

        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.depositInLendingPool(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator calls testProcessDefault with defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: realisedLiquidityOf for srTranche should be liquiditySenior, realisedLiquidityOf jrTranche should be liquidityJunior minus defaultAmount,
        // totalRealisedLiquidity should be equal to totalAmount minus defaultAmount
        assertEq(pool.realisedLiquidityOf(address(srTranche)), liquiditySenior);
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), liquidityJunior - defaultAmount);
        assertEq(pool.totalRealisedLiquidity(), totalAmount - defaultAmount);
    }

    function testSuccess_processDefault_TwoTranches(
        uint256 liquiditySenior,
        uint256 liquidityJunior,
        uint256 defaultAmount
    ) public {
        // Given: srTranche deposit liquiditySenior, jrTranche deposit liquidityJunior
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount < totalAmount);
        vm.assume(defaultAmount >= liquidityJunior);

        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.depositInLendingPool(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator calls testProcessDefault with defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: supplyBalances srTranche should be totalAmount minus defaultAmount, supplyBalances jrTranche should be 0,
        // totalSupply should be equal to totalAmount minus defaultAmount, isTranche for jrTranche should return false
        assertEq(pool.realisedLiquidityOf(address(srTranche)), totalAmount - defaultAmount);
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), 0);
        assertEq(pool.totalRealisedLiquidity(), totalAmount - defaultAmount);
        assertFalse(pool.isTranche(address(jrTranche)));
    }

    function testSuccess_processDefault_AllTranches(
        uint256 liquiditySenior,
        uint256 liquidityJunior,
        uint256 defaultAmount
    ) public {
        // Given: defaultAmount, liquidityJunior and liquiditySenior bigger than 0,
        // srTranche calls depositInLendingPool for liquiditySenior, jrTranche calls depositInLendingPool for liquidityJunior
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount >= totalAmount);
        vm.assume(defaultAmount > 0);
        vm.assume(liquidityJunior > 0);
        vm.assume(liquiditySenior > 0);

        vm.prank(address(srTranche));
        pool.depositInLendingPool(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.depositInLendingPool(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator testProcessDefault defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: realisedLiquidityOf srTranche should be 0, realisedLiquidityOf jrTranche should be 0,
        // totalRealisedLiquidity should be equal to 0, isTranche for jrTranche and srTranche should return false
        assertEq(pool.realisedLiquidityOf(address(srTranche)), 0);
        assertEq(pool.realisedLiquidityOf(address(jrTranche)), 0);
        assertEq(pool.totalRealisedLiquidity(), 0);
        assertFalse(pool.isTranche(address(jrTranche)));
        assertFalse(pool.isTranche(address(srTranche)));

        //ToDo Remaining Liquidity stuck in pool now, emergency procedure?
    }
}

/* //////////////////////////////////////////////////////////////
                        VAULT LOGIC
////////////////////////////////////////////////////////////// */
contract VaultTest is LendingPoolTest {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        //Set Tranche weight on 0 so that all yield goes to treasury
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        pool.depositInLendingPool(type(uint128).max, liquidityProvider);

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();

        vm.prank(creator);
        pool.setLiquidator(liquidator);
    }

    function testRevert_openMarginAccount_NonVault(address unprivilegedAddress) public {
        // Given: sender is not a vault
        vm.assume(unprivilegedAddress != address(vault));

        // When: sender wants to open a margin account
        // Then: openMarginAccount should revert with "LP_OMA: Not a vault"
        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("LP_OMA: Not a vault");
        pool.openMarginAccount();
        vm.stopPrank();
    }

    function testSuccess_openMarginAccount() public {
        // Given: sender is a vault
        vm.startPrank(address(vault));

        // When: vault opens a margin account
        (bool success, address basecurrency, address liquidator_) = pool.openMarginAccount();

        // Then: openMarginAccount should return succes and correct contract addresses
        assertTrue(success);
        assertEq(address(asset), basecurrency);
        assertEq(liquidator, liquidator_);
    }

    function testSuccess_getOpenPosition(uint128 amountLoaned) public {
        // Given: a vault has taken out debt
        vm.assume(amountLoaned > 0);
        vault.setTotalValue(amountLoaned);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        // When: The vault fetches its open position
        uint128 openPosition = pool.getOpenPosition(address(vault));

        // Then: The open position should equal the amount loaned
        assertEq(amountLoaned, openPosition);
    }
}
