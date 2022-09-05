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

abstract contract LiquidityPoolTest is Test {

    Asset asset;
    Factory factory;
    LiquidityPool pool;
    Tranche srTranche;
    Tranche jrTranche;
    DebtToken debt;

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
        assertEq(pool.vaultFactory(), address(factory));
        assertEq(pool.liquidator(), liquidator);
        assertEq(pool.treasury(), treasury);
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
        // Given: unprivilegedAddress is not the creator
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress addTranche
        // Then: addTranche should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.addTranche(address(srTranche), 50);
        vm.stopPrank();
    }

    function testSuccess_AddSingleTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator addTranche, srTranche as Tranche address, 50 as weight
        pool.addTranche(address(srTranche), 50);

        // Then: pool totalWeight should be equal to 50, weights should be equal to 50, 
        // tranches address should be equal to srTranche address, isTranche with input srTranche should return true
        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.tranches(0), address(srTranche));
        assertTrue(pool.isTranche(address(srTranche)));
    }

    function testRevert_AddSingleTrancheTwice()public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator addTranche srTranche two times
        pool.addTranche(address(srTranche), 50);
        
        // Then: addTranche should revert with TR_AD: Already exists
        vm.expectRevert("TR_AD: Already exists");
        pool.addTranche(address(srTranche), 40);
        vm.stopPrank();
    }

    function testSuccess_AddMultipleTranches() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator addTranche srTranche and jrTranche, with 50 and 40 weights
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        // Then: pool totalWeight should be equal to 90, weights index 0 should be equal to 50, 
        // weights index 1 should be equal to 40, tranches address 0 should be equal to srTranche address, 
        // tranches address 1 should be equal to jrTranche address, 
        // isTranche should return true for both srTranche and jrTranche
        assertEq(pool.totalWeight(), 90);
        assertEq(pool.weights(0), 50);
        assertEq(pool.weights(1), 40);
        assertEq(pool.tranches(0), address(srTranche));
        assertEq(pool.tranches(1), address(jrTranche));
        assertTrue(pool.isTranche(address(srTranche)));
        assertTrue(pool.isTranche(address(jrTranche)));
    }

    //setWeight
    function testRevert_SetWeightInvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setWeight
        // Then: setWeight should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testRevert_SetWeightInexistingTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator setWeight on index 0
        // Then: setWeight should revert with TR_SW: Inexisting Tranche
        vm.expectRevert("TR_SW: Inexisting Tranche");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testSuccess_SetWeight() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator addTranche with 50 weight, setWeight 40 on index 0
        pool.addTranche(address(srTranche), 50);
        pool.setWeight(0, 40);
        vm.stopPrank();

        // Then: weights for index 0 should return 40
        assertEq(pool.weights(0), 40);
    }

    //popTranche
    function testSuccess_PopTranche() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator addTranche with srTranche and jrTranche, testPopTranche with index 1
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        pool.testPopTranche(1, address(jrTranche));

        // Then: pool totalWeight should be equal to 50, weights index 0 should be equal to 50, 
        // tranches address 0 should be equal to srTranche address, isTranche should return true for srTranche
        // not isTranche should return true for jrTranche
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
contract ProtocolFeeTest is LiquidityPoolTest {

    function setUp() override public {
        super.setUp();
    }

    //setFeeWeight
    function testRevert_SetFeeWeightInvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setFeeWeight

        // Then: setFeeWeight should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setFeeWeight(5);
        vm.stopPrank();
    }

    function testSuccess_SetFeeWeight() public {
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
    function testRevert_SetTreasuryInvalidOwner(address unprivilegedAddress) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setTreasury
        // Then: setTreasury should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setTreasury(creator);
        vm.stopPrank();
    }

    function testSuccess_SetTreasury() public {
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
contract DepositAndWithdrawalTest is LiquidityPoolTest {

    function setUp() override public {
        super.setUp();

        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));
        vm.stopPrank();
    }

    //deposit (without debt -> ignore _syncInterests() and _updateInterestRate())
    function testRevert_DepositByNonTranche(address unprivilegedAddress, uint128 assets, address from) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.assume(unprivilegedAddress != address(jrTranche));
        vm.assume(unprivilegedAddress != address(srTranche));

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress deposit
        // Then: deposit should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.deposit(assets, from);
        vm.stopPrank();
    }

    function testSuccess_FirstDepositByTranche(uint256 amount) public {
        // Given: liquidityProvider approve max value
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit
        pool.deposit(amount, liquidityProvider);

        // Then: balanceOf srTranche should be amount, totatlSupply should be amount, balanceOf pool should be amount
        assertEq(pool.balanceOf(address(srTranche)), amount);
        assertEq(pool.totalSupply(), amount);
        assertEq(asset.balanceOf(address(pool)), amount);
    }

    function testSuccess_MultipleDepositsByTranches(uint256 amount0, uint256 amount1) public {
        // Given: totalAmount is amount0 added by amount1, liquidityProvider approve max value
        vm.assume(amount0 <= type(uint256).max - amount1);

        uint256 totalAmount = uint256(amount0) + uint256(amount1);
        
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit amount0, jrTranche deposit amount1
        pool.deposit(amount0, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.deposit(amount1, liquidityProvider);

        // Then: balanceOf jrTranche should be amount1, totalSupply should be totalAmount, balanceOf pool should be totalAmount 
        assertEq(pool.balanceOf(address(jrTranche)), amount1);
        assertEq(pool.totalSupply(), totalAmount);
        assertEq(asset.balanceOf(address(pool)), totalAmount);
    }

    //withdraw
    function testRevert_WithdrawUnauthorised(uint256 assetsWithdrawn, address receiver, address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not srTranche, liquidityProvider approve max value
        vm.assume(unprivilegedAddress != address(srTranche));

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        // When: srTranche deposit assetsWithdrawn
        pool.deposit(assetsWithdrawn, liquidityProvider);

        vm.startPrank(unprivilegedAddress);
        // Then: withdraw by unprivilegedAddress should revert with LP_W: UNAUTHORIZED
        vm.expectRevert("LP_W: UNAUTHORIZED");
        pool.withdraw(assetsWithdrawn, receiver, address(srTranche));
        vm.stopPrank();
    }

    function testRevert_WithdrawInsufficientAssets(uint256 assetsDeposited, uint256 assetsWithdrawn, address receiver) public {
        // Given: assetsWithdrawn bigger than assetsDeposited, liquidityProvider approve max value
        vm.assume(assetsDeposited < assetsWithdrawn);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        // When: srTranche deposit assetsDeposited
        pool.deposit(assetsDeposited, liquidityProvider);

        // Then: withdraw assetsWithdrawn should revert
        vm.expectRevert(stdError.arithmeticError);
        pool.withdraw(assetsWithdrawn, receiver, address(srTranche));
        vm.stopPrank();
    }

    function testSuccess_Withdraw(uint256 assetsDeposited, uint256 assetsWithdrawn, address receiver) public {
        // Given: assetsWithdrawn less than equal assetsDeposited, receiver is not pool or liquidityProvider, 
        // liquidityProvider approve max value
        vm.assume(receiver != address(pool));
        vm.assume(receiver != liquidityProvider);
        vm.assume(assetsDeposited >= assetsWithdrawn);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        // When: srTranche deposit and withdraw
        pool.deposit(assetsDeposited, liquidityProvider);

        pool.withdraw(assetsWithdrawn, receiver, address(srTranche));
        vm.stopPrank();

        // Then: balanceOf srTranche, pool and totalSupply should be assetsDeposited minus assetsWithdrawn, 
        // balanceOf receiver should be assetsWithdrawn
        assertEq(pool.balanceOf(address(srTranche)), assetsDeposited - assetsWithdrawn);
        assertEq(pool.totalSupply(), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(address(pool)), assetsDeposited - assetsWithdrawn);
        assertEq(asset.balanceOf(receiver), assetsWithdrawn);
    }
}

/*//////////////////////////////////////////////////////////////
                    LENDING LOGIC
//////////////////////////////////////////////////////////////*/
contract LoanTest is LiquidityPoolTest {
    
    Vault vault;

    function setUp() override public {
        super.setUp();

        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);

        debt = new DebtToken(pool);
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();
    }

    //setDebtToken
    function testRevert_SetDebtTokenInvalidOwner(address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not creator
        vm.assume(unprivilegedAddress != creator);
        
        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress setDebtToken

        // Then: setDebtToken should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        pool.setDebtToken(address(debt));
        vm.stopPrank();
    }

    function testSuccess_SetDebtToken() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.startPrank(creator);
        // When: creator sets the debt as setDebtToken 
        pool.setDebtToken(address(debt));
        vm.stopPrank();

        // Then: debtToken should return debt address
        assertEq(pool.debtToken(), address(debt));
    }

    //approveBeneficiary
    function testRevert_ApproveBeneficiaryForNonVault(address beneficiary, uint256 amount, address nonVault) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: approveBeneficiary with nonVault input on vault

        // Then: approveBeneficiary should revert with "LP_AB: Not a vault"
        vm.expectRevert("LP_AB: Not a vault");
        pool.approveBeneficiary(beneficiary, amount, nonVault);
    }

    function testRevert_ApproveBeneficiaryUnauthorised(address beneficiary, uint256 amount, address unprivilegedAddress) public {
        // Given: unprivilegedAddress is not vaultOwner
        vm.assume(unprivilegedAddress != vaultOwner);

        vm.startPrank(unprivilegedAddress);
        // When: approveBeneficiary as unprivilegedAddress

        // Then: approveBeneficiary should revert with "LP_AB: UNAUTHORIZED"
        vm.expectRevert("LP_AB: UNAUTHORIZED");
        pool.approveBeneficiary(beneficiary, amount, address(vault));
        vm.stopPrank();
    }

    function testSuccess_ApproveBeneficiary(address beneficiary, uint256 amount) public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(vaultOwner);
        // When: approveBeneficiary as vaultOwner
        pool.approveBeneficiary(beneficiary, amount, address(vault));

        // Then: creditAllowance should be equal to amount
        assertEq(pool.creditAllowance(address(vault), beneficiary), amount);
    }

    //borrow
    function testRevert_BorrowAgainstNonVault(uint256 amount, address nonVault, address to) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: borrow as nonVault

        // Then: borrow should revert with "LP_TL: Not a vault"
        vm.expectRevert("LP_TL: Not a vault");
        pool.borrow(amount, nonVault, to);
    }

    function testRevert_BorrowUnauthorised(uint256 amount, address beneficiary, address to) public {
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

    function testRevert_BorrowInsufficientApproval(uint256 amountAllowed, uint256 amountLoaned, address beneficiary, address to) public {
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

    function testRevert_BorrowInsufficientCollateral(uint256 amountLoaned, uint256 collateralValue, address to) public {
        // Given: collateralValue is less than amountLoaned, vault setTotalValue to colletrallValue
        vm.assume(collateralValue < amountLoaned);

        vault.setTotalValue(collateralValue);

        vm.startPrank(vaultOwner);
        // When: borrow amountLoaned as vaultOwner

        // Then: borrow should revert with "LP_TL: Reverted"
        vm.expectRevert("LP_TL: Reverted");
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_BorrowInsufficientLiquidity(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address to) public {
        // Given: collateralValue less than equal to amountLoaned, liquidity is bigger than 0 but less than amountLoaned,
        // to is not address 0, creator setDebtToken to debt, liquidityProvider approve pool to max value,
        // srTranche deposit liquidity, setTotalValue to colletralValue
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity < amountLoaned);
        vm.assume(liquidity > 0);
        vm.assume(to != address(0));

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.deposit(liquidity, liquidityProvider);
        vault.setTotalValue(collateralValue);

        vm.startPrank(vaultOwner);
        // When: borrow amountLoaned as vaultOwner

        // Then: borrow should revert with "TRANSFER_FAILED"
        vm.expectRevert("TRANSFER_FAILED");
        pool.borrow(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testSuccess_BorrowByVaultOwner(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address to) public {
        // Given: collateralValue and liquidity bigger than equal to amountLoaned, amountLoaned is bigger than 0,
        // to is not address 0 and not liquidityProvider, creator setDebtToken to debt, setTotalValue to colletralValue, 
        // liquidityProvider approve pool to max value, srTranche deposit liquidity
        vm.assume(collateralValue >= amountLoaned);
        vm.assume(liquidity >= amountLoaned);
        vm.assume(amountLoaned > 0);
        vm.assume(to != address(0));
        vm.assume(to != liquidityProvider);

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.deposit(liquidity, liquidityProvider);

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

    function testSuccess_BorrowByLimitedAuthorisedAddress(uint256 amountAllowed, uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address beneficiary, address to) public {
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

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.deposit(liquidity, liquidityProvider);
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

    function testSuccess_BorrowByMaxAuthorisedAddress(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address beneficiary, address to) public {
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

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(collateralValue);
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(address(srTranche));
        pool.deposit(liquidity, liquidityProvider);
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

    //repay
    function testRevert_RepayForNonVault(uint256 amount, address nonVault) public {
        // Given: nonVault is not vault
        vm.assume(nonVault != address(vault));
        // When: repay amount to nonVault

        // Then: repay should revert with "LP_RL: Not a vault"
        vm.expectRevert("LP_RL: Not a vault");
        pool.repay(amount, nonVault);
    }

    function testRevert_RepayInsufficientFunds(uint128 amountLoaned, uint256 availablefunds, address sender) public {
        // Given: amountLoaned is bigger than availablefunds, availablefunds bigger than 0,
        // sender is not zero address, liquidityProvider or vaultOwner, creator setDebtToken to debt,
        // setTotalValue to amountLoaned, liquidityProvider approve max value, transfer availablefunds,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(amountLoaned > availablefunds);
        vm.assume(availablefunds > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, availablefunds);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.deposit(amountLoaned, liquidityProvider);
        vm.prank(vaultOwner);
        pool.borrow(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        // When: sender approve and repay amountLoaned
        asset.approve(address(pool), type(uint256).max);
        // Then: repay should revert with "TRANSFER_FROM_FAILED"
        vm.expectRevert("TRANSFER_FROM_FAILED");
        pool.repay(amountLoaned, address(vault));
        vm.stopPrank();
    }

    function testSuccess_RepayAmountInferiorLoan(uint128 amountLoaned, uint256 amountRepaid, address sender) public {
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

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, amountRepaid);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.deposit(amountLoaned, liquidityProvider);
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

    function testSuccess_RepayExactAmount(uint128 amountLoaned, address sender) public {
        // Given: amountLoaned is bigger than 0, sender is not zero address, liquidityProvider, vaultOwner or pool, 
        // creator setDebtToken to debt, setTotalValue to amountLoaned, liquidityProvider approve max value, transfer amountRepaid,
        // srTranche deposit amountLoaned, vaultOwner borrow amountLoaned
        vm.assume(amountLoaned > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);
        vm.assume(sender != address(pool));

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, amountLoaned);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.deposit(amountLoaned, liquidityProvider);
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

    function testSuccess_RepayAmountExceedingLoan(uint128 amountLoaned, uint128 availablefunds, address sender) public {
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

        vm.prank(creator);
        pool.setDebtToken(address(debt));
        vault.setTotalValue(amountLoaned);
        vm.startPrank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
        asset.transfer(sender, availablefunds);
        vm.stopPrank();
        vm.prank(address(srTranche));
        pool.deposit(amountLoaned, liquidityProvider);
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
contract InterestsTest is LiquidityPoolTest {
    using stdStorage for StdStorage;

    Vault vault;

    function setUp() override public {
        super.setUp();

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        vault = Vault(factory.createVault(1));
        vm.stopPrank();
    }

    //_syncInterestsToLiquidityPool
    function testSuccess_SyncInterestsToLiquidityPoolExact() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator testSyncInterestsToLiquidityPool with 100
        pool.testSyncInterestsToLiquidityPool(100);

        // Then: balanceOf srTranche should be equal to 50, balanceOf jrTranche should be equal to 40, 
        // balanceOf treasury should be equal to 10, totalSupply should be equal to 100 
        assertEq(pool.balanceOf(address(srTranche)), 50);
        assertEq(pool.balanceOf(address(jrTranche)), 40);
        assertEq(pool.balanceOf(treasury), 10);
        assertEq(pool.totalSupply(), 100);
    }

    function testSuccess_SyncInterestsToLiquidityPoolRounded() public {
        // Given: all neccesary contracts are deployed on the setup
        vm.prank(creator);
        // When: creator testSyncInterestsToLiquidityPool with 99
        pool.testSyncInterestsToLiquidityPool(99);

        // Then: balanceOf srTranche should be equal to 50, balanceOf jrTranche should be equal to 40, 
        // balanceOf treasury should be equal to 9, totalSupply should be equal to 99
        assertEq(pool.balanceOf(address(srTranche)), 50);
        assertEq(pool.balanceOf(address(jrTranche)), 40);
        assertEq(pool.balanceOf(treasury), 9);
        assertEq(pool.totalSupply(), 99);
    }

    //_calcUnrealisedDebt
    function testSuccess_CalcUnrealisedDebtUnchecked(uint64 interestRate, uint24 deltaBlocks, uint128 realisedDebt) public {
        // Given: interestRate is %1000, deltaBlocks is 5 years, realisedDebt is 3402823669209384912995114146594816
        vm.assume(interestRate <= 10 * 10**18); //1000%
        vm.assume(deltaBlocks <= 13140000); //5 year
        vm.assume(realisedDebt <= type(uint128).max / (10**5)); //highest possible debt at 1000% over 5 years: 3402823669209384912995114146594816

        uint256 loc = stdstore
            .target(address(pool))
            .sig(pool.interestRate.selector)
            .find();
        bytes32 slot = bytes32(loc);
        //interestRate and lastSyncedBlock are packed in same slot -> encode packen and bitshift to the right
        bytes32 value = bytes32(abi.encodePacked(uint24(block.number), interestRate));
        value = value >> 168;
        vm.store(address(pool), slot, value);

        loc = stdstore
            .target(address(debt))
            .sig(debt.totalDebt.selector)
            .find();
        slot = bytes32(loc);
        value = bytes32(abi.encode(realisedDebt));
        vm.store(address(debt), slot, value);

        vm.roll(block.number + deltaBlocks);

        uint256 expectedValue = calcUnrealisedDebtChecked(interestRate, deltaBlocks, realisedDebt);
        uint256 actualValue = pool.testCalcUnrealisedDebt();

        assertEq(expectedValue, actualValue);
    }
    //Helper functions
    function calcUnrealisedDebtChecked(uint64 interestRate, uint24 deltaBlocks, uint128 realisedDebt) internal view returns (uint256 unrealisedDebt) {
        uint256 base = 1e18 + uint256(interestRate);
        uint256 exponent = uint256(deltaBlocks) * 1e18 / pool.YEARLY_BLOCKS();
        unrealisedDebt = 
                (uint256(realisedDebt) * (LogExpMath.pow(base, exponent) - 1e18)) /
                    1e18
            ;
    }

}

/*//////////////////////////////////////////////////////////////
                            LOAN DEFAULT LOGIC
//////////////////////////////////////////////////////////////*/
contract DefaultTest is LiquidityPoolTest {
    using stdStorage for StdStorage;

    function setUp() override public {
        super.setUp();

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        //Set Tranche weight on 0 so that all yield goes to treasury
        pool.addTranche(address(srTranche), 0);
        pool.addTranche(address(jrTranche), 0);

        debt = new DebtToken(pool);
        pool.setDebtToken(address(debt));
        vm.stopPrank();

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);
    }

    function testSuccess_ProcessDefaultOneTranche(uint256 liquiditySenior, uint256 liquidityJunior, uint256 defaultAmount) public {
        // Given: srTranche deposit liquiditySenior, jrTranche deposit liquidityJunior
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount < liquidityJunior);

        vm.prank(address(srTranche));
        pool.deposit(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.deposit(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator testProcessDefault defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: balanceOf srTranche should be liquiditySenior, balanceOf jrTranche should be liquidityJunior minus defaultAmount,
        // totalSupply should be equal to totalAmount minus defaultAmount
        assertEq(pool.balanceOf(address(srTranche)), liquiditySenior);
        assertEq(pool.balanceOf(address(jrTranche)), liquidityJunior - defaultAmount);
        assertEq(pool.totalSupply(), totalAmount - defaultAmount);
    }

    function testSuccess_ProcessDefaultTwoTranches(uint256 liquiditySenior, uint256 liquidityJunior, uint256 defaultAmount) public {
        // Given: srTranche deposit liquiditySenior, jrTranche deposit liquidityJunior
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount < totalAmount);
        vm.assume(defaultAmount >= liquidityJunior);

        vm.prank(address(srTranche));
        pool.deposit(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.deposit(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator testProcessDefault defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: balanceOf srTranche should be totalAmount minus defaultAmount, balanceOf jrTranche should be 0,
        // totalSupply should be equal to totalAmount minus defaultAmount, isTranche for jrTranche should return false
        assertEq(pool.balanceOf(address(srTranche)), totalAmount - defaultAmount);
        assertEq(pool.balanceOf(address(jrTranche)), 0);
        assertEq(pool.totalSupply(), totalAmount - defaultAmount);
        assertFalse(pool.isTranche(address(jrTranche)));
    }

    function testSuccess_ProcessDefaultAllTranches(uint256 liquiditySenior, uint256 liquidityJunior, uint256 defaultAmount) public {
        // Given: srTranche deposit liquiditySenior, jrTranche deposit liquidityJunior
        vm.assume(liquiditySenior <= type(uint256).max - liquidityJunior);
        uint256 totalAmount = uint256(liquiditySenior) + uint256(liquidityJunior);
        vm.assume(defaultAmount >= totalAmount);

        vm.prank(address(srTranche));
        pool.deposit(liquiditySenior, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.deposit(liquidityJunior, liquidityProvider);

        vm.prank(creator);
        // When: creator testProcessDefault defaultAmount
        pool.testProcessDefault(defaultAmount);

        // Then: balanceOf srTranche should be 0, balanceOf jrTranche should be 0,
        // totalSupply should be equal to 0, isTranche for jrTranche and srTranche should return false
        assertEq(pool.balanceOf(address(srTranche)), 0);
        assertEq(pool.balanceOf(address(jrTranche)), 0);
        assertEq(pool.totalSupply(), 0);
        assertFalse(pool.isTranche(address(jrTranche)));
        assertFalse(pool.isTranche(address(srTranche)));

    //ToDo Remaining Liquidity stuck in pool now, emergency procedure?
    }

}
