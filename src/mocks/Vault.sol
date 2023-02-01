/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
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

    function isVaultHealthy(uint256 amount, uint256 totalOpenDebt) external view returns (bool success) {
        if (amount != 0) {
            //Check if vault is still healthy after an increase of used margin.
            success = totalValue >= lockedValue + amount;
        } else {
            //Check if vault is healthy for a given amount of openDebt.
            success = totalValue >= totalOpenDebt;
        }
    }

    function vaultManagementAction(address actionHandler, bytes calldata actionData) external { }
}
