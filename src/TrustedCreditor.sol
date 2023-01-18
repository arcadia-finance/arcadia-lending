/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

/**
 * @title Trusted Creditor implementation
 * @author Arcadia Finance
 * @notice This contract contains the minimum functionality a Trusted Creditor, interacting with Arcadia Vaults, needs to implement.
 * @dev For the implementation of Arcadia Vaults, see: https://github.com/arcadia-finance/arcadia-vaults
 */
abstract contract TrustedCreditor {
    mapping(uint256 => bool) public isValidVersion;

    constructor() {}

    /* //////////////////////////////////////////////////////////////
                        LIQUIDATION LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Called by a vault when it is being liquidated (auctioned) to repay an amount of debt.
     * @param debt The amount of debt that will be repaid after the auction.
     */
    function liquidateVault(uint256 debt) public virtual;

    /* //////////////////////////////////////////////////////////////
                            VAULT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets the validity of vault version to valid
     * @param vaultVersion The version current version of the vault
     * @param valid The validity of the respective vaultVersion
     */
    function _setVaultVersion(uint256 vaultVersion, bool valid) internal {
        isValidVersion[vaultVersion] = valid;
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
