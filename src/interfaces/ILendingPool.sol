/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

import "../../lib/solmate/src/tokens/ERC20.sol";

interface ILendingPool {
    function supplyBalances(address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function asset() external returns (ERC20);

    function deposit(uint256 assets, address from) external;

    function withdraw(uint256 assets, address receiver) external;
}
