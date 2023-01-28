/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity >=0.4.22 <0.9.0;

interface IFactory {
    /**
     * @notice View function returning if an address is a vault
     * @param vault The address to be checked.
     * @return bool Whether the address is a vault or not.
     */
    function isVault(address vault) external view returns (bool);

    /**
     * @notice Returns the owner of a vault.
     * @param vault The Vault address.
     * @return owner_ The Vault owner.
     */
    function ownerOfVault(address vault) external view returns (address);
}
