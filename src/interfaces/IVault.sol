/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface IVault {
    /**
     * @notice Returns the address of the owner of the Vault.
     */
    function owner() external view returns (address);

    /**
     * @notice Checks if the Vault is healthy and still has free margin.
     * @param amount The amount with which the position is increased.
     * @param totalOpenDebt The total open Debt against the Vault.
     * @return success Boolean indicating if there is sufficient margin to back a certain amount of Debt.
     * @dev Only one of the vaules can be non-zero, or we check on a certain increase of debt, or we check on a total amount of debt.
     */
    function isVaultHealthy(uint256 amount, uint256 totalOpenDebt) external view returns (bool);

    /**
     * @notice Calls external action handler to execute and interact with external logic.
     * @param actionHandler The address of the action handler.
     * @param actionData A bytes object containing two actionAssetData structs, an address array and a bytes array.
     */
    function vaultManagementAction(address actionHandler, bytes calldata actionData) external;
}
