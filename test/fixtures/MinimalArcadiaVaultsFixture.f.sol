/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >0.8.10;

import "../../../lib/forge-std/src/Test.sol";

import "../../Factory.sol";
import "../../Proxy.sol";
import "../../Vault.sol";
import {ERC20Mock} from "../../mockups/ERC20SolmateMock.sol";
import "../../AssetRegistry/MainRegistry.sol";
import "../../AssetRegistry/StandardERC20PricingModule.sol";
import "../../Liquidator.sol";
import "../../OracleHub.sol";
import "../../utils/Constants.sol";
import "../../mockups/ArcadiaOracle.sol";
import ".././fixtures/ArcadiaOracleFixture.f.sol";

contract DeployArcadiaVaults is Test {
    Factory public factory;
    Vault public vault;
    Vault public proxy;
    address public proxyAddr;
    ERC20Mock public collateral;
    ERC20Mock public baseCurrency;
    OracleHub public oracleHub;
    ArcadiaOracle public oracleCollateralToUsd;
    ArcadiaOracle public oracleBaseCurrencyToUsd;
    MainRegistry public mainRegistry;
    StandardERC20PricingModule public standardERC20PricingModule;
    Liquidator public liquidator;

    address public creatorAddress = address(1);
    address public tokenCreatorAddress = address(2);
    address public oracleOwner = address(3);
    address public unprivilegedAddress = address(4);
    address public vaultOwner = address(6);
    address public liquidityProvider = address(7);

    uint8 collateralDecimals = 18;
    uint8 baseCurrencyDecimals = 18;

    uint8 oracleCollateralToUsdDecimals = 1;
    uint8 oracleBaseCurrencyToUsdDecimals = 1;

    uint256 rateCollateralToUsd = 1 * 10 ** oracleCollateralToUsdDecimals;
    uint256 rateBaseCurrencyToUsd = 1 * 10 ** oracleBaseCurrencyToUsdDecimals;

    address[] public oracleCollateralToUsdArr = new address[](1);
    address[] public oracleBaseCurrencyToUsdArr = new address[](1);

    uint16 public collateralFactor = RiskConstants.DEFAULT_COLLATERAL_FACTOR;
    uint16 public liquidationFactor = RiskConstants.DEFAULT_LIQUIDATION_FACTOR;

    PricingModule.RiskVarInput[] emptyRiskVarInput;
    PricingModule.RiskVarInput[] riskVars;

    // FIXTURES
    ArcadiaOracleFixture arcadiaOracleFixture = new ArcadiaOracleFixture(oracleOwner);

    //this is a before
    constructor() {
        //Deploy tokens
        vm.startPrank(tokenCreatorAddress);
        collateral = new ERC20Mock("Collateral", "COLL", collateralDecimals);
        baseCurrency = new ERC20Mock("Base Currency", "BACU", baseCurrencyDecimals);
        vm.stopPrank();

        //Deploi Oracles
        oracleCollateralToUsd = arcadiaOracleFixture.initMockedOracle(oracleCollateralToUsdDecimals, "COLL / USD");

        oracleCollateralToUsdArr[0] = address(oracleCollateralToUsd);

        vm.startPrank(oracleOwner);
        oracleCollateralToUsd.transmit(int256(rateCollateralToUsd));
        oracleBaseCurrencyToUsd.transmit(int256(rateBaseCurrencyToUsd));
        vm.stopPrank();

        //Deploy Arcadia Vaults contracts
        vm.startPrank(creatorAddress);
        oracleHub = new OracleHub();
        factory = new Factory();

        oracleHub.addOracle(
            OracleHub.OracleInformation({
                oracleUnit: uint64(10 ** oracleCollateralToUsdDecimals),
                baseAssetBaseCurrency: 0,
                quoteAsset: "COLL",
                baseAsset: "USD",
                oracle: address(oracleCollateralToUsd),
                quoteAssetAddress: address(collateral),
                baseAssetIsBaseCurrency: true
            })
        );

        mainRegistry = new MainRegistry(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                baseCurrencyToUsdOracle: 0x0000000000000000000000000000000000000000,
                baseCurrencyLabel: "USD",
                baseCurrencyUnitCorrection: uint64(10**(18 - Constants.usdDecimals))
            })
        );
        mainRegistry.addBaseCurrency(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: uint64(10 ** oracleBaseCurrencyToUsdDecimals),
                assetAddress: address(baseCurrency),
                baseCurrencyToUsdOracle: address(oracleBaseCurrencyToUsd),
                baseCurrencyLabel: "BACU",
                baseCurrencyUnitCorrection: uint64(10 ** (18 - baseCurrencyDecimals))
            })
        );

        standardERC20PricingModule = new StandardERC20PricingModule(
            address(mainRegistry),
            address(oracleHub)
        );

        mainRegistry.addPricingModule(address(standardERC20PricingModule));

        riskVars.push(
            PricingModule.RiskVarInput({
                baseCurrency: 0,
                asset: address(0),
                collateralFactor: collateralFactor,
                liquidationFactor: liquidationFactor
            })
        );
        riskVars.push(
            PricingModule.RiskVarInput({
                baseCurrency: 1,
                asset: address(0),
                collateralFactor: collateralFactor,
                liquidationFactor: liquidationFactor
            })
        );

        PricingModule.RiskVarInput[] memory riskVars_ = riskVars;

        standardERC20PricingModule.addAsset(address(collateral), oracleCollateralToUsdArr, riskVars_, type(uint128).max);

        vault = new Vault();
        factory.setNewVaultInfo(address(mainRegistry), address(vault), Constants.upgradeProof1To2);
        factory.confirmNewVaultInfo();
        mainRegistry.setFactory(address(factory));
        vm.stopPrank();
    }
}
