/**
 * Created by Arcadia Finance
 *     https://www.arcadia.finance
 * 
 *     SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

library DataTypes {
    struct InterestRateConfiguration {
        uint256 baseRate; //18 decimals precision
        uint256 lowSlope; //18 decimals precision
        uint256 highSlope; //18 decimals precision
        uint256 utilisationThreshold; //5 decimal precision
    }
}
