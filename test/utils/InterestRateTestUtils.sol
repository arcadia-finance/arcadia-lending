/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../../src/libraries/DataTypes.sol";

library InterestRateTestUtils {

    function calculateInterestRate(uint256 utilisation, DataTypes.InterestRateConfiguration memory config) public returns (uint64){
        if (utilisation >= config.utilisationThreshold) {
            uint256 lowSlopeInterest = uint256(config.utilisationThreshold * config.lowSlope);
            uint256 highSlopeInterest = uint256((utilisation - config.utilisationThreshold) * config.highSlope);
            return uint64(config.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            return uint64(config.baseRate + config.lowSlope * utilisation);
        }
    }
}