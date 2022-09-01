/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../../lib/solmate/src/tokens/ERC20.sol";

interface ILiquidityPool {
    function asset() external returns (ERC20);

    function deposit(uint256 assets, address from) external;

    function withdraw(uint256 assets, address receiver, address owner) external;
}