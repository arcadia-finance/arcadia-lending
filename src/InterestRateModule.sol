/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import { DataTypes } from "./libraries/DataTypes.sol";

contract InterestRateModule {
    uint256 public interestRate; //18 decimals precision

    DataTypes.InterestRateConfiguration public interestRateConfig;

    /**
     * @notice Set's the configration parameters of InterestRateConfiguration struct
     * @param newConfig New set of configration parameters
     */
    function _setInterestConfig(DataTypes.InterestRateConfiguration calldata newConfig) internal {
        interestRateConfig = newConfig;
    }

    /**
     * @notice Calculates the interest rate
     * @param utilisation Utilisation rate in 5 decimal precision
     * @dev This function can only be called by the function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_)
     * @return Interest rate
     */
    function _calculateInterestRate(uint256 utilisation) internal view returns (uint256) {
        unchecked {
            if (utilisation >= interestRateConfig.utilisationThreshold) {
                // 1e23 = (uT * 1e5) * (ls * 1e18)
                uint256 lowSlopeInterest =
                    uint256(interestRateConfig.utilisationThreshold) * interestRateConfig.lowSlopePerYear;
                // 1e23 = ((uT - u) * 1e5) * (hs * 1e18)
                uint256 highSlopeInterest = uint256((utilisation - interestRateConfig.utilisationThreshold))
                    * interestRateConfig.highSlopePerYear;
                // 1e18 = (bs * 1e18) + ((lsIR * 1e23) + (hsIR * 1e23) / 1e5)
                return uint256(interestRateConfig.baseRatePerYear) + ((lowSlopeInterest + highSlopeInterest) / 100_000);
            } else {
                // 1e18 = br * 1e18 + (ls * 1e18) * (u * 1e5) / 1e5
                return uint256(
                    uint256(interestRateConfig.baseRatePerYear)
                        + ((uint256(interestRateConfig.lowSlopePerYear) * utilisation) / 100_000)
                );
            }
        }
    }

    /**
     * @notice Updates the interest rate
     * @param realisedDebt_ Realised debt that calculates after substracting unrealised debt from total debt
     * @param totalRealisedLiquidity_ Total realised liquidity
     * @dev This function is only be called by the function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_),
     * calculates the interest rate, if the totalRealisedLiquidity_ is zero then utilisation is zero
     */
    function _updateInterestRate(uint256 realisedDebt_, uint256 totalRealisedLiquidity_) internal {
        uint256 utilisation;
        if (totalRealisedLiquidity_ > 0) {
            utilisation = (100_000 * realisedDebt_) / totalRealisedLiquidity_;
        }
        interestRate = _calculateInterestRate(utilisation);
    }
}
