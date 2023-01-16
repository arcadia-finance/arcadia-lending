/**
 * Created by Arcadia Finance
 *     https://www.arcadia.finance
 *
 *     SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

library DataTypes {
    struct InterestRateConfiguration {
        uint256 baseRatePerYear; //18 decimals precision
        uint256 lowSlopePerYear; //18 decimals precision
        uint256 highSlopePerYear; //18 decimals precision
        uint256 utilisationThreshold; //5 decimal precision
    }
}
