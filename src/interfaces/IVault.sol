/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface IVault {
    function owner() external view returns (address);

    function increaseMarginPosition(address baseCurrency, uint256 amount) external returns (bool);

    function decreaseMarginPosition(address baseCurrency, uint256 amount) external returns (bool);
}