/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/libraries/InterestRateModule.sol";

contract InterestRateModuleMockUpTest is InterestRateModule {
    //Extensions to test internal functions

    constructor(address creator) Owned(creator) {}

    function _calculateInterestRate(uint256 utilisation) public view returns (uint256) {
        return calculateInterestRate(utilisation);
    }
}

contract InterestRateModuleTest is Test {
    InterestRateModuleMockUpTest interest;

    address creator = address(1);

    //Before Each
    function setUp() public virtual {
        vm.startPrank(creator);
        interest = new InterestRateModuleMockUpTest(address(creator));
        vm.stopPrank();
    }

    function testSuccess_calculateInterestRate_UnderOptimalUtilisation(
        uint256 utilisation,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: utilisation is between 0 and 80, InterestRateConfiguration setted as config
        vm.assume(utilisation > 0);
        vm.assume(utilisation <= 0.8 * 10e5);
        vm.assume(baseRate_ < 10000);
        vm.assume(highSlope_ > lowSlope_);

        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRate: baseRate_,
            highSlope: highSlope_,
            lowSlope: lowSlope_,
            utilisationThreshold: 0.8 * 10e5
        });

        // When: creator calls setInterestConfig with config
        vm.startPrank(creator);
        interest.setInterestConfig(config);

        // And: actualInterestRate is _calculateInterestRate with utilisation
        uint256 actualInterestRate = interest._calculateInterestRate(utilisation);
        vm.stopPrank();

        // And: expectedInterestRate is lowSlope multiplied by utilisation and added to baseRate
        uint256 expectedInterestRate = config.baseRate + ((config.lowSlope / 10 ** 5) * utilisation);

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testSuccess_calculateInterestRate_OverOptimalUtilisation(
        uint8 utilisation,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_
    ) public {
        // Given: utilisation is between 80 and 100, InterestRateConfiguration setted as config
        vm.assume(utilisation > 0.8 * 10e5);
        vm.assume(utilisation <= 1 * 10e5);
        vm.assume(highSlope_ > lowSlope_);

        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRate: baseRate_,
            highSlope: highSlope_,
            lowSlope: lowSlope_,
            utilisationThreshold: 8000
        });

        // When: creator calls setInterestConfig with config
        vm.startPrank(creator);
        interest.setInterestConfig(config);

        // And: actualInterestRate is _calculateInterestRate with utilisation
        uint256 actualInterestRate = interest._calculateInterestRate(utilisation);
        vm.stopPrank();

        // And: lowSlopeInterest is utilisationThreshold multiplied by lowSlope, highSlopeInterest is utilisation minus utilisationThreshold multiplied by highSlope
        uint256 lowSlopeInterest = config.utilisationThreshold * (config.lowSlope / 10 ** 5);
        uint256 highSlopeInterest = (utilisation - config.utilisationThreshold) * (config.highSlope / 10 ** 5);

        // And: expectedInterestRate is baseRate added to lowSlopeInterest added to highSlopeInterest
        uint256 expectedInterestRate = config.baseRate + lowSlopeInterest + highSlopeInterest;

        // Then: actualInterestRate should be equal to expectedInterestRate
        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testRevert_setInterestConfig_NonOwner(
        address unprivilegedAddress,
        uint8 baseRate_,
        uint8 highSlope_,
        uint8 lowSlope_,
        uint8 utilisationThreshold_
    ) public {
        // Given: unprivilegedAddress is not creator, InterestRateConfiguration setted as config
        vm.assume(unprivilegedAddress != creator);

        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRate: baseRate_,
            highSlope: highSlope_,
            lowSlope: lowSlope_,
            utilisationThreshold: utilisationThreshold_
        });

        vm.startPrank(unprivilegedAddress);
        // When: unprivilegedAddress calls setInterestConfig
        // Then: setInterestConfig should revert with UNAUTHORIZED
        vm.expectRevert("UNAUTHORIZED");
        interest.setInterestConfig(config);
        vm.stopPrank();
    }
}
