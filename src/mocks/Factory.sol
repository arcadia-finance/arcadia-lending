/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "./Vault.sol";

contract Factory {
    mapping(address => bool) public isVault;

    constructor() {}

    function createVault(uint256 salt) external returns (address vault) {
        vault = address(
            new Vault{salt: bytes32(salt)}(
                msg.sender
            )
        );

        isVault[vault] = true;
    }
}
