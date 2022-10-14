/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import {Owned} from "../../lib/solmate/src/auth/Owned.sol";
import "./DataTypes.sol";

abstract contract InterestRateModule is Owned {

    uint256 public interestRate; //18 decimals precision

    DataTypes.InterestRateConfiguration internal config;

    function setInterestConfig(DataTypes.InterestRateConfiguration memory newConfig) external onlyOwner{
        config = newConfig;
    }

    // TODO: Add safe math
    function calculateInterestRate(uint256 utilisation) internal returns(uint256){
        if (utilisation >= config.utilisationThreshold) {
            uint256 lowSlopeInterest = uint256(config.utilisationThreshold * config.lowSlope);
            uint256 highSlopeInterest = uint256((utilisation - config.utilisationThreshold) * config.highSlope);
            return uint256(config.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            return uint256(config.baseRate + config.lowSlope * utilisation);
        }
    }

    function _updateInterestRate(uint256 utilisation) internal {
        //ToDo
        uint256 interestRate_ = calculateInterestRate(utilisation);
        interestRate = interestRate_;
    }

}