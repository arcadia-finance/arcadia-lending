/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import {Owned} from "../../lib/solmate/src/auth/Owned.sol";
import {DataTypes} from "./DataTypes.sol";

abstract contract InterestRateModule is Owned {
    uint256 public interestRate; //18 decimals precision

    DataTypes.InterestRateConfiguration internal interestRateConfig;

    /**
     * @notice Set's the configration parameters of InterestRateConfiguration struct
     * @param newConfig New set of configration parameters
     */

    function setInterestConfig(DataTypes.InterestRateConfiguration memory newConfig) external onlyOwner {
        config = newConfig;
    }

    /**
     * @notice Calculates the interest rate
     * @param utilisation Utilisation rate
     * @dev This function is only be called by the function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_)
     * @return Interest rate
     */
    function calculateInterestRate(uint256 utilisation) internal view returns (uint256) {
        if (utilisation >= config.utilisationThreshold) {
            uint256 lowSlopeInterest = config.utilisationThreshold * (config.lowSlope / 10 ** 5);
            uint256 highSlopeInterest = (utilisation - config.utilisationThreshold) * (config.highSlope / 10 ** 5);
            return uint256(config.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            return uint256(config.baseRate + ((config.lowSlope / 10 ** 5) * utilisation));
        }
    }

    /**
     * @notice Updates the interest rate
     * @param realisedDebt_ Realised debt that calculates after substracting unrealised debt from total debt
     * @param totalRealisedLiquidity_ Total realised liquidity
     * @dev This function is only be called by the function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_),
     * calculates the interest rate
     */
    function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_) internal {
        uint256 utilisation = (10 ** 5 * realisedDebt_) / totalRealisedLiquidity_;

        interestRate = calculateInterestRate(utilisation);
    }
}
