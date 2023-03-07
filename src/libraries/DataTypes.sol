/**
 * Created by Arcadia Finance
 *     https://www.arcadia.finance
 *
 *     SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

library DataTypes {
    /**
     * A struct with the set of interest rate configuration parameters:
     * - baseRatePerYear The interest rate when utilisation is 0.
     * - lowSlopePerYear The slope of the first curve, defined as the delta in interest rate for a delta in utilisation of 100%.
     * - highSlopePerYear The slope of the second curve, defined as the delta in interest rate for a delta in utilisation of 100%.
     * - utilisationThreshold the optimal utilisation, where we go from the flat first curve to the steeper second curve.
     */
    struct InterestRateConfiguration {
        uint72 baseRatePerYear; //18 decimals precision.
        uint72 lowSlopePerYear; //18 decimals precision.
        uint72 highSlopePerYear; //18 decimals precision.
        uint40 utilisationThreshold; //5 decimal precision.
    }
}
