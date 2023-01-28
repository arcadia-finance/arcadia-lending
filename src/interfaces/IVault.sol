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
     * @notice Called by trusted applications, checks if the Vault has sufficient free margin.
     * @param baseCurrency The Base-currency in which the vault is denominated.
     * @param amount The amount the position is increased.
     * @return success Boolean indicating if there is sufficient free margin to increase the margin position.
     */
    function increaseMarginPosition(address baseCurrency, uint256 amount) external returns (bool);

    /**
     * @notice Calls external action handler to execute and interact with external logic.
     * @param actionHandler The address of the action handler.
     * @param actionData A bytes object containing two actionAssetData structs, an address array and a bytes array.
     */
    function vaultManagementAction(address actionHandler, bytes calldata actionData) external;
}
