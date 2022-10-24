/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../../src/libraries/DataTypes.sol";

abstract contract InterestRateTestUtils {

    uint64 public interestRate; //18 decimals precision

    DataTypes.InterestRateConfiguration internal config;

    function setInterestConfig(DataTypes.InterestRateConfiguration memory newConfig) public {
        config = newConfig;
    }

    function calculateInterestRate(uint64 utilisation) public view returns (uint64){
        if (utilisation >= config.utilisationThreshold) {
            uint64 lowSlopeInterest = uint64(config.utilisationThreshold * config.lowSlope);
            uint64 highSlopeInterest = uint64((utilisation - config.utilisationThreshold) * config.highSlope);
            return uint64(config.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            return uint64(config.baseRate + config.lowSlope * utilisation);
        }
    }

    function _updateInterestRate(uint64 utilisation) public {
        uint64 interestRate_ = calculateInterestRate(utilisation);
        interestRate = interestRate_;
    }
}