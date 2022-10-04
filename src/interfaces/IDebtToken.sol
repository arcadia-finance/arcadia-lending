/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity >=0.4.22 <0.9.0;

interface IDebtToken {

    function totalDebt() external view returns(uint256 totalDebt);

    function syncInterests(uint256 assets) external;
}
