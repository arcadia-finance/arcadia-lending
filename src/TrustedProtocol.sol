/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

abstract contract TrustedProtocol {
    constructor() {}

    function openMarginAccount() external virtual returns (bool success, address baseCurrency, address liquidator);

    function getOpenPosition(address vault) external virtual returns(uint128 openPosition);

}