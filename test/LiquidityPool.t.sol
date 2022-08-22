// SPDX-License-Identifier: UNLICENSED
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
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.addTranche(address(srTranche), 50);
        vm.stopPrank();
    }

    function testSuccess_AddSingleTranche() public {
        vm.prank(creator);
        pool.addTranche(address(srTranche), 50);

        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.tranches(0), address(srTranche));
        assertTrue(pool.isTranche(address(srTranche)));
    }

    function testRevert_AddSingleTrancheTwice()public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);

        vm.expectRevert("TR_AD: Already exists");
        pool.addTranche(address(srTranche), 40);
        vm.stopPrank();
    }

    function testSuccess_AddMultipleTranches() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        assertEq(pool.totalWeight(), 90);
        assertEq(pool.weights(0), 50);
        assertEq(pool.weights(1), 40);
        assertEq(pool.tranches(0), address(srTranche));
        assertEq(pool.tranches(1), address(jrTranche));
        assertTrue(pool.isTranche(address(jrTranche)));
    }

    //setWeight
    function testRevert_SetWeightInvalidOwner(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testRevert_SetWeightInexistingTranche() public {
        vm.startPrank(creator);
        vm.expectRevert("TR_SW: Inexisting Tranche");
        pool.setWeight(0, 50);
        vm.stopPrank();
    }

    function testSuccess_SetWeight() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.setWeight(0, 40);
        vm.stopPrank();

        assertEq(pool.weights(0), 40);
    }

    //removeLastTranche
    function testSucces_removeLastTranche() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.addTranche(address(jrTranche), 40);
        vm.stopPrank();

        pool.testRemoveLastTranche(1, address(jrTranche));

        assertEq(pool.totalWeight(), 50);
        assertEq(pool.weights(0), 50);
        assertEq(pool.tranches(0), address(srTranche));
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
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.setFeeWeight(5);
        vm.stopPrank();
    }

    function testSuccess_SetFeeWeight() public {
        vm.startPrank(creator);
        pool.addTranche(address(srTranche), 50);
        pool.setFeeWeight(5);
        vm.stopPrank();

        assertEq(pool.totalWeight(), 55);
        assertEq(pool.feeWeight(), 5);

        vm.startPrank(creator);
        pool.setFeeWeight(10);
        vm.stopPrank();

        assertEq(pool.totalWeight(), 60);
        assertEq(pool.feeWeight(), 10);
    }

    //setTreasury
    function testRevert_SetTreasuryInvalidOwner(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.setTreasury(creator);
        vm.stopPrank();
    }

    function testSuccess_SetTreasury() public {
        vm.startPrank(creator);
        pool.setTreasury(creator);
        vm.stopPrank();

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
        vm.assume(unprivilegedAddress != address(jrTranche));
        vm.assume(unprivilegedAddress != address(srTranche));

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.deposit(assets, from);
        vm.stopPrank();
    }

    function testRevert_ZeroShares() public {
        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        vm.expectRevert("ZERO_SHARES");
        pool.deposit(0, liquidityProvider);
        vm.stopPrank();
    }

    function testSucces_FirstDepositByTranche(uint128 amount) public {
        vm.assume(amount > 0);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        pool.deposit(amount, liquidityProvider);

        assertEq(pool.maxWithdraw(address(srTranche)), amount);
        assertEq(pool.maxRedeem(address(srTranche)), amount);
        assertEq(pool.totalAssets(), amount);
        assertEq(asset.balanceOf(address(pool)), amount);
    }

    function testSucces_MultipleDepositsByTranches(uint128 amount0, uint128 amount1) public {
        vm.assume(amount0 > 0);
        vm.assume(amount1 > 0);
        uint256 totalAmount = uint256(amount0) + uint256(amount1);
        vm.assume(amount0 <= type(uint256).max / totalAmount); //Overflow on maxWithdraw()
        vm.assume(amount1 <= type(uint256).max / totalAmount); //Overflow on maxWithdraw()

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.prank(address(srTranche));
        pool.deposit(amount0, liquidityProvider);
        vm.prank(address(jrTranche));
        pool.deposit(amount1, liquidityProvider);

        assertEq(pool.maxWithdraw(address(jrTranche)), amount1);
        assertEq(pool.maxRedeem(address(jrTranche)), amount1);
        assertEq(pool.totalAssets(), totalAmount);
        assertEq(asset.balanceOf(address(pool)), totalAmount);
    }

    //mint
    function testRevert_MintNotSupported(uint256 shares, address receiver) public {
        vm.expectRevert("MINT_NOT_SUPPORTED");
        pool.mint(shares, receiver);
    }

    //withdraw
    function testSucces_Withdraw(uint128 amount0, uint128 amount1) public {
        vm.assume(amount1 > 0);
        vm.assume(amount0 >= amount1);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        pool.deposit(amount0, liquidityProvider);
        pool.withdraw(amount1, address(srTranche), address(srTranche));

        uint256 totalAmount = uint256(amount0) - uint256(amount1);
        assertEq(pool.maxWithdraw(address(srTranche)), totalAmount);
        assertEq(pool.maxRedeem(address(srTranche)), totalAmount);
        assertEq(pool.totalAssets(), totalAmount);
        assertEq(asset.balanceOf(address(pool)), totalAmount);
    }

    //redeem
    function testSucces_Redeem(uint128 amount0, uint128 amount1) public {
        vm.assume(amount1 > 0);
        vm.assume(amount0 >= amount1);

        vm.prank(liquidityProvider);
        asset.approve(address(pool), type(uint256).max);

        vm.startPrank(address(srTranche));
        pool.deposit(amount0, liquidityProvider);
        pool.redeem(amount1, address(srTranche), address(srTranche));

        uint256 totalAmount = uint256(amount0) - uint256(amount1);
        assertEq(pool.maxWithdraw(address(srTranche)), totalAmount);
        assertEq(pool.maxRedeem(address(srTranche)), totalAmount);
        assertEq(pool.totalAssets(), totalAmount);
        assertEq(asset.balanceOf(address(pool)), totalAmount);
    }

}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LOGIC
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
        vm.assume(unprivilegedAddress != creator);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("UNAUTHORIZED");
        pool.setDebtToken(address(debt));
        vm.stopPrank();
    }

    function testSucces_SetDebtToken() public {
        vm.startPrank(creator);
        pool.setDebtToken(address(debt));
        vm.stopPrank();

        assertEq(pool.debtToken(), address(debt));
    }

    //approveBeneficiary
    function testRevert_ApproveBeneficiaryForNonVault(address beneficiary, uint256 amount, address nonVault) public {
        vm.assume(nonVault != address(vault));

        vm.expectRevert("LP_AB: Not a vault");
        pool.approveBeneficiary(beneficiary, amount, nonVault);
    }

    function testRevert_ApproveBeneficiaryUnauthorised(address beneficiary, uint256 amount, address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != vaultOwner);

        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("LP_AB: UNAUTHORIZED");
        pool.approveBeneficiary(beneficiary, amount, address(vault));
        vm.stopPrank();
    }

    function testSucces_ApproveBeneficiary(address beneficiary, uint256 amount) public {
        vm.prank(vaultOwner);
        pool.approveBeneficiary(beneficiary, amount, address(vault));

        assertEq(pool.creditAllowance(address(vault), beneficiary), amount);
    }

    //takeLoan
    function testRevert_TakeLoanAgainstNonVault(uint256 amount, address nonVault, address to) public {
        vm.assume(nonVault != address(vault));

        vm.expectRevert("LP_TL: Not a vault");
        pool.takeLoan(amount, nonVault, to);
    }

    function testRevert_TakeLoanUnauthorised(uint256 amount, address beneficiary, address to) public {
        vm.assume(beneficiary != vaultOwner);
        emit log_named_uint("amountAllowed", pool.creditAllowance(address(vault), beneficiary));

        vm.assume(amount > 0);
        vm.startPrank(beneficiary);
        vm.expectRevert(stdError.arithmeticError);
        pool.takeLoan(amount, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_TakeLoanInsufficientApproval(uint256 amountAllowed, uint256 amountLoaned, address beneficiary, address to) public {
        vm.assume(beneficiary != vaultOwner);
        vm.assume(amountAllowed < amountLoaned);

        vm.prank(vaultOwner);
        pool.approveBeneficiary(beneficiary, amountAllowed, address(vault));

        vm.startPrank(beneficiary);
        vm.expectRevert(stdError.arithmeticError);
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_TakeLoanInsufficientCollateral(uint256 amountLoaned, uint256 collateralValue, address to) public {
        vm.assume(collateralValue < amountLoaned);

        vault.setTotalValue(collateralValue);

        vm.startPrank(vaultOwner);
        vm.expectRevert("LP_TL: Reverted");
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testRevert_TakeLoanInsufficientLiquidity(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address to) public {
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
        vm.expectRevert("TRANSFER_FAILED");
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();
    }

    function testSucces_TakeLoanByVaultOwner(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address to) public {
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
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
    }

    function testSucces_TakeLoanByLimitedAuthorisedAddress(uint256 amountAllowed, uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address beneficiary, address to) public {
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
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
        assertEq(pool.creditAllowance(address(vault), beneficiary), amountAllowed - amountLoaned);
    }

    function testSucces_TakeLoanByMaxAuthorisedAddress(uint256 amountLoaned, uint256 collateralValue, uint256 liquidity, address beneficiary, address to) public {
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
        pool.takeLoan(amountLoaned, address(vault), to);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(pool)), liquidity - amountLoaned);
        assertEq(asset.balanceOf(to), amountLoaned);
        assertEq(debt.balanceOf(address(vault)), amountLoaned);
        assertEq(pool.creditAllowance(address(vault), beneficiary), type(uint256).max);
    }

    //repayLoan
    function testRevert_RepayLoanForNonVault(uint256 amount, address nonVault) public {
        vm.assume(nonVault != address(vault));

        vm.expectRevert("LP_RL: Not a vault");
        pool.repayLoan(amount, nonVault);
    }

    function testRevert_RepayLoanInsufficientFunds(uint128 amountLoaned, uint256 availablefunds, address sender) public {
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
        pool.takeLoan(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        asset.approve(address(pool), type(uint256).max);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        pool.repayLoan(amountLoaned, address(vault));
        vm.stopPrank();
    }

    function testSucces_RepayLoanAmountInferiorLoan(uint128 amountLoaned, uint256 amountRepaid, address sender) public {
        vm.assume(amountLoaned > amountRepaid);
        vm.assume(amountRepaid > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);

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
        pool.takeLoan(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        asset.approve(address(pool), type(uint256).max);
        pool.repayLoan(amountRepaid, address(vault));
        vm.stopPrank();

        assertEq(asset.balanceOf(address(pool)), amountRepaid);
        assertEq(asset.balanceOf(sender), 0);
        assertEq(debt.balanceOf(address(vault)), amountLoaned - amountRepaid);
    }

    function testSucces_RepayLoanExactAmount(uint128 amountLoaned, address sender) public {
        vm.assume(amountLoaned > 0);
        vm.assume(sender != address(0));
        vm.assume(sender != liquidityProvider);
        vm.assume(sender != vaultOwner);

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
        pool.takeLoan(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        asset.approve(address(pool), type(uint256).max);
        pool.repayLoan(amountLoaned, address(vault));
        vm.stopPrank();

        assertEq(asset.balanceOf(address(pool)), amountLoaned);
        assertEq(asset.balanceOf(sender), 0);
        assertEq(debt.balanceOf(address(vault)), 0);
    }

    function testSucces_RepayLoanAmountExceedingLoan(uint128 amountLoaned, uint128 availablefunds, address sender) public {
        vm.assume(availablefunds > amountLoaned);
        vm.assume(amountLoaned > 0);
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
        pool.takeLoan(amountLoaned, address(vault), vaultOwner);

        vm.startPrank(sender);
        asset.approve(address(pool), type(uint256).max);
        pool.repayLoan(availablefunds, address(vault));
        vm.stopPrank();

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
    function testSucces_SyncInterestsToLiquidityPoolExact() public {
        vm.prank(creator);
        pool.testSyncInterestsToLiquidityPool(100);

        assertEq(pool.maxWithdraw(address(srTranche)), 50);
        assertEq(pool.maxRedeem(address(srTranche)), 50);
        assertEq(pool.maxWithdraw(address(jrTranche)), 40);
        assertEq(pool.maxRedeem(address(jrTranche)), 40);
        assertEq(pool.maxWithdraw(treasury), 10);
        assertEq(pool.maxRedeem(treasury), 10);
        assertEq(pool.totalAssets(), 100);
    }

    function testSucces_SyncInterestsToLiquidityPoolRounded() public {
        vm.prank(creator);
        pool.testSyncInterestsToLiquidityPool(99);

        assertEq(pool.maxWithdraw(address(srTranche)), 50);
        assertEq(pool.maxRedeem(address(srTranche)), 50);
        assertEq(pool.maxWithdraw(address(jrTranche)), 40);
        assertEq(pool.maxRedeem(address(jrTranche)), 40);
        assertEq(pool.maxWithdraw(treasury), 9);
        assertEq(pool.maxRedeem(treasury), 9);
        assertEq(pool.totalAssets(), 99);
    }

    //_calcUnrealisedDebt
    function testSucces_CalcUnrealisedDebtUnchecked(uint64 interestRate, uint24 deltaBlocks, uint128 realisedDebt) public {
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
    function calcUnrealisedDebtChecked(uint64 interestRate, uint24 deltaBlocks, uint128 realisedDebt) internal returns (uint256 unrealisedDebt) {
        uint256 base = 1e18 + uint256(interestRate);
        uint256 exponent = uint256(deltaBlocks) * 1e18 / pool.YEARLY_BLOCKS();
        unrealisedDebt = 
                (uint256(realisedDebt) * (LogExpMath.pow(base, exponent) - 1e18)) /
                    1e18
            ;
    }

}
