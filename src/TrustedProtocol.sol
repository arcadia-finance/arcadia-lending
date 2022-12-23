/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

/**
 * @title Trusted Protocol implementation
 * @author Arcadia Finance
 * @notice This contract contains the minimum functionality a Trusted Protocol, interacting with Arcadia Vaults, needs to implement.
 * @dev For the implementation of Arcadia Vaults, see: https://github.com/arcadia-finance/arcadia-vaults
 */
abstract contract TrustedProtocol {
    mapping(uint256 => bool) public isValidVersion;

    constructor() {}

    /**
     * @notice Sets a vault version to valid
     * @param vaultVersion The version current version of the vault
     */
    function _addVaultVersion(uint256 vaultVersion) internal {
        isValidVersion[vaultVersion] = true;
    }

    /**
     * @notice Sets a vault version to invalid
     * @param vaultVersion The version current version of the vault
     */
    function _removeVaultVersion(uint256 vaultVersion) internal {
        isValidVersion[vaultVersion] = false;
    }

    /**
     * @notice Checks if vault fulfills all requirements and returns application settings.
     * @param vaultVersion The current version of the vault
     * @return success Bool indicating if all requirements are met.
     * @return baseCurrency The base currency of the application.
     * @return liquidator The liquidator of the application.
     */
    function openMarginAccount(uint256 vaultVersion)
        external
        virtual
        returns (bool success, address baseCurrency, address liquidator);

    /**
     * @notice Returns the open position of the vault.
     * @param vault The vault address.
     * @return openPosition The open position of the vault.
     */
    function getOpenPosition(address vault) external view virtual returns (uint256 openPosition);
}
