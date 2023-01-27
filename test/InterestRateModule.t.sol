/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/InterestRateModule.sol";

contract InterestRateModuleMockUpTest is InterestRateModule {
    //Extensions to test internal functions

    function setInterestConfig(DataTypes.InterestRateConfiguration calldata newConfig) public {
        _setInterestConfig(newConfig);
    }

    function calculateInterestRate(uint256 utilisation) public view returns (uint256) {
        return _calculateInterestRate(utilisation);
    }

    function updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_) public {
        return _updateInterestRate(realisedDebt_, totalRealisedLiquidity_);
    }
}

contract InterestRateModuleTest is Test {
    InterestRateModuleMockUpTest interest;

    //Before Each
    function setUp() public virtual {
        interest = new InterestRateModuleMockUpTest();
    }

    function testSuccess_setInterestConfig(
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_,
        uint8 utilisationThreshold_
    ) public {
        // Given: A certain InterestRateConfiguration
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRatePerYear: baseRate_,
            highSlopePerYear: highSlope_,
            lowSlopePerYear: lowSlope_,
            utilisationThreshold: utilisationThreshold_
        });
        // When: The InterestConfiguration is set
        interest.setInterestConfig(config);

        // Then: config types should be equal to fuzzed types
        (uint256 baseRatePerYear, uint256 lowSlopePerYear, uint256 highSlopePerYear, uint256 utilisationThreshold) =
            interest.interestRateConfig();
        assertEq(baseRatePerYear, baseRate_);
        assertEq(highSlopePerYear, highSlope_);
        assertEq(lowSlopePerYear, lowSlope_);
        assertEq(utilisationThreshold, utilisationThreshold_);
    }

    function testSuccess_updateInterestRate_totalRealisedLiquidityMoreThanZero(
        uint256 realisedDebt_,
        uint256 totalRealisedLiquidity_,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: totalRealisedLiquidity_ is more than equal to 0, baseRate_ is less than 100000, highSlope_ is bigger than lowSlope_
        vm.assume(totalRealisedLiquidity_ > 0);
        vm.assume(realisedDebt_ <= type(uint128).max / (10 ** 5)); //highest possible debt at 1000% over 5 years: 3402823669209384912995114146594816
        vm.assume(baseRate_ < 1 * 10 ** 5);
        vm.assume(highSlope_ > lowSlope_);

        // And: A certain InterestRateConfiguration
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRatePerYear: baseRate_,
            highSlopePerYear: highSlope_,
            lowSlopePerYear: lowSlope_,
            utilisationThreshold: 0.8 * 10 ** 5
        });

        // When: The InterestConfiguration is set
        interest.setInterestConfig(config);
        // And: The interest is set for a certain combination of realisedDebt_ and totalRealisedLiquidity_
        interest.updateInterestRate(realisedDebt_, totalRealisedLiquidity_);
        // And: actualInterestRate is interestRate from InterestRateModule contract
        uint256 actualInterestRate = interest.interestRate();

        // And: expectedUtilisation is 100_000 multiplied by realisedDebt_ and divided by totalRealisedLiquidity_
        uint256 expectedUtilisation = (100_000 * realisedDebt_) / totalRealisedLiquidity_;

        uint256 expectedInterestRate;

        if (expectedUtilisation <= config.utilisationThreshold) {
            // And: expectedInterestRate is lowSlope multiplied by expectedUtilisation, divided by 100000 and added to baseRate
            expectedInterestRate = config.baseRatePerYear + (config.lowSlopePerYear * expectedUtilisation / 100_000);
        } else {
            // And: lowSlopeInterest is utilisationThreshold multiplied by lowSlope,
            // highSlopeInterest is expectedUtilisation minus utilisationThreshold multiplied by highSlope
            uint256 lowSlopeInterest = config.utilisationThreshold * config.lowSlopePerYear;
            uint256 highSlopeInterest = (expectedUtilisation - config.utilisationThreshold) * config.highSlopePerYear;

            // And: expectedInterestRate is baseRate added to lowSlopeInterest added to highSlopeInterest divided by 100000
            expectedInterestRate = config.baseRatePerYear + ((lowSlopeInterest + highSlopeInterest) / 100_000);
        }

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testSuccess_updateInterestRate_totalRealisedLiquidityZero(
        uint256 realisedDebt_,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: totalRealisedLiquidity_ is equal to 0, baseRate_ is less than 100000, highSlope_ is bigger than lowSlope_
        uint256 totalRealisedLiquidity_ = 0;
        vm.assume(realisedDebt_ <= type(uint128).max / (10 ** 5)); //highest possible debt at 1000% over 5 years: 3402823669209384912995114146594816
        vm.assume(baseRate_ < 1 * 10 ** 5);
        vm.assume(highSlope_ > lowSlope_);

        // And: a certain InterestRateConfiguration
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRatePerYear: baseRate_,
            highSlopePerYear: highSlope_,
            lowSlopePerYear: lowSlope_,
            utilisationThreshold: 0.8 * 10 ** 5
        });

        // When: The InterestConfiguration is set
        interest.setInterestConfig(config);
        // And: The interest is set for a certain combination of realisedDebt_ and totalRealisedLiquidity_
        interest.updateInterestRate(realisedDebt_, totalRealisedLiquidity_);
        // And: actualInterestRate is interestRate from InterestRateModule contract
        uint256 actualInterestRate = interest.interestRate();

        uint256 expectedInterestRate = config.baseRatePerYear;

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testSuccess_calculateInterestRate_UnderOptimalUtilisation(
        uint256 utilisation,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: utilisation is between 0 and 80000, baseRate_ is less than 100000, highSlope_ is bigger than lowSlope_
        vm.assume(utilisation > 0);
        vm.assume(utilisation <= 0.8 * 10 ** 5);
        vm.assume(baseRate_ < 1 * 10 ** 5);
        vm.assume(highSlope_ > lowSlope_);

        // And: a certain InterestRateConfiguration
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRatePerYear: baseRate_,
            highSlopePerYear: highSlope_,
            lowSlopePerYear: lowSlope_,
            utilisationThreshold: 0.8 * 10 ** 5
        });

        // When: The InterestConfiguration is set
        interest.setInterestConfig(config);

        // And: actualInterestRate is calculateInterestRate with utilisation
        uint256 actualInterestRate = interest.calculateInterestRate(utilisation);

        // And: expectedInterestRate is lowSlope multiplied by utilisation divided by 100000 and added to baseRate
        uint256 expectedInterestRate = config.baseRatePerYear + (config.lowSlopePerYear * utilisation / 100_000);

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testSuccess_calculateInterestRate_OverOptimalUtilisation(
        uint8 utilisationShift,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: utilisation is between 80000 and 100000, highSlope_ is bigger than lowSlope_
        vm.assume(utilisationShift < 0.2 * 10 ** 5);
        vm.assume(highSlope_ > lowSlope_);

        uint256 utilisation = 0.8 * 10 ** 5 + uint256(utilisationShift);

        // And: a certain InterestRateConfiguration
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRatePerYear: baseRate_,
            highSlopePerYear: highSlope_,
            lowSlopePerYear: lowSlope_,
            utilisationThreshold: 0.8 * 10 ** 5
        });

        // When: The InterestConfiguration is set
        interest.setInterestConfig(config);

        // And: actualInterestRate is calculateInterestRate with utilisation
        uint256 actualInterestRate = interest.calculateInterestRate(utilisation);

        // And: lowSlopeInterest is utilisationThreshold multiplied by lowSlope, highSlopeInterest is utilisation minus utilisationThreshold multiplied by highSlope
        uint256 lowSlopeInterest = config.utilisationThreshold * config.lowSlopePerYear;
        uint256 highSlopeInterest = (utilisation - config.utilisationThreshold) * config.highSlopePerYear;

        // And: expectedInterestRate is baseRate added to lowSlopeInterest added to highSlopeInterest divided by divided by 100000
        uint256 expectedInterestRate = config.baseRatePerYear + ((lowSlopeInterest + highSlopeInterest) / 100_000);

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }
}
