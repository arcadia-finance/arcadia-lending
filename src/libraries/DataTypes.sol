
/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

library DataTypes {
    // TODO: Optimize the variables
    struct InterestRateConfiguration {
        uint64 baseRate;
        uint64 lowSlope;
        uint64 highSlope;
        uint64 utilisationThreshold;
    }

}