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
            // 1e18 = (uT * 1e5) * (ls * 1e18) / 1e5
            uint256 lowSlopeInterest = interestRateConfig.utilisationThreshold * interestRateConfig.lowSlope / 100_000;
            // 1e18 = ((uT - u) * 1e5) * (hs * 1e18) / 1e5
            uint256 highSlopeInterest =
                (utilisation - interestRateConfig.utilisationThreshold) * (interestRateConfig.highSlope / 100_000);
            // 1e18 = (bs * 1e18) + (lsIR * 1e18) + (hsIR * 1e18)
            return uint256(interestRateConfig.baseRate + lowSlopeInterest + highSlopeInterest);
        } else {
            // 1e18 = br * 1e18 + (ls * 1e18) * (u * 1e5) / 1e5
            return uint256(interestRateConfig.baseRate + ((interestRateConfig.lowSlope * utilisation) / 100_000));
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
            utilisation = (100_000 * realisedDebt_) / totalRealisedLiquidity_;
        } else {
            utilisation = 0;
        }

        interestRate = calculateInterestRate(utilisation);
    }
}
