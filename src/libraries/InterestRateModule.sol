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

    DataTypes.InterestRateConfiguration public interestRateConfig;

    /**
     * @notice Set's the configration parameters of InterestRateConfiguration struct
     * @param newConfig New set of configration parameters
     */

    function setInterestConfig(DataTypes.InterestRateConfiguration calldata newConfig) external onlyOwner {
        interestRateConfig = newConfig;
    }

    /**
     * @notice Calculates the interest rate
     * @param utilisation Utilisation rate
     * @dev This function is only be called by the function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_)
     * @return Interest rate
     */
    function calculateInterestRate(uint256 utilisation) internal view returns (uint256) {
        if (utilisation >= interestRateConfig.utilisationThreshold) {
            uint256 lowSlopeInterest = interestRateConfig.utilisationThreshold * (interestRateConfig.lowSlope / 10 ** 5);
            uint256 highSlopeInterest =
                (utilisation - interestRateConfig.utilisationThreshold) * (interestRateConfig.highSlope / 10 ** 5);
            return uint256(interestRateConfig.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            return uint256(interestRateConfig.baseRate + ((interestRateConfig.lowSlope / 10 ** 5) * utilisation));
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
        uint256 utilisation;
        if (totalRealisedLiquidity_ > 0) {
            utilisation = (10 ** 5 * realisedDebt_) / totalRealisedLiquidity_;
        } else {
            utilisation = 0;
        }

        interestRate = calculateInterestRate(utilisation);
    }
}
