/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface IVault {
    function owner() external view returns (address);

    function increaseMarginPosition(address baseCurrency, uint256 amount) external returns (bool);

    function deposit(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        uint256[] calldata assetTypes
    ) external payable;

    function vaultManagementAction(address actionHandler, bytes calldata actionData) external;
}
