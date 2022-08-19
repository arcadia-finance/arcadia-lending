/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
 pragma solidity ^0.8.13;

 contract Vault {

    address public owner;
    uint256 public totalValue;
    uint256 public lockedValue;
    address public baseCurrency;

    constructor(address _owner) payable {
        owner = _owner;
    }

    function setTotalValue(uint256 _totalValue) external {
        totalValue = _totalValue;
    }

    function lockCollateral(uint256 amount, address) external returns (bool) {
        if (totalValue - lockedValue >= amount) {
            lockedValue += amount;
            return true;
        } else {
            return false;
        }
    }

 }
