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

    constructor(address creator) Owned(creator){}

    function _calculateInterestRate(uint64 utilisation) public view returns(uint64){
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

    //Helper functions
    function testSuccess_calculateInterestRate_UnderOptimalUtilisation(uint64 utilisation) public {
        vm.assume(utilisation > 0);
        vm.assume(utilisation <= 80);


        vm.startPrank(creator);
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRate: 1,
            highSlope: 2,
            lowSlope: 1,
            utilisationThreshold: 80
        });
        
        interest.setInterestConfig(config);
        
        uint64 actualInterestRate = interest._calculateInterestRate(utilisation);
        vm.stopPrank();

        uint64 expectedInterestRate = uint64(config.baseRate + config.lowSlope * utilisation);

        assertEq(actualInterestRate, expectedInterestRate);
    }

    function testSuccess_calculateInterestRate_OverOptimalUtilisation(uint64 utilisation) public {
        vm.assume(utilisation > 80);
        vm.assume(utilisation <= 100);

        vm.startPrank(creator);
        DataTypes.InterestRateConfiguration memory config = DataTypes.InterestRateConfiguration({
            baseRate: 1,
            highSlope: 2,
            lowSlope: 1,
            utilisationThreshold: 80
        });
        
        interest.setInterestConfig(config);
        
        uint64 actualInterestRate = interest._calculateInterestRate(utilisation);
        vm.stopPrank();

        uint64 lowSlopeInterest = uint64(config.utilisationThreshold * config.lowSlope);
        uint64 highSlopeInterest = uint64((utilisation - config.utilisationThreshold) * config.highSlope);

        uint64 expectedInterestRate = uint64(config.baseRate + lowSlopeInterest + highSlopeInterest);

        assertEq(actualInterestRate, expectedInterestRate);
    }
    
}