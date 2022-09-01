/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

interface IVault {
    function owner() external view returns (address);

    function lockCollateral(uint256 amount, address baseCurrency) external returns (bool);

    function unlockCollateral(uint256 amount, address baseCurrency) external returns (bool);
}