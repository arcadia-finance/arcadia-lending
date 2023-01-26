/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface ILiquidator {
    function startAuction(address vault, uint256 openDebt) external;
}
