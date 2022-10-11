/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

import "../../lib/solmate/src/tokens/ERC20.sol";

interface ILendingPool {
    function redeemableAssetsOf(address) external view returns (uint256);

    function totalRedeemableAssets() external view returns (uint256);

    function asset() external returns (ERC20);

    function depositInLendingPool(uint256 assets, address from) external;

    function withdrawFromLendingPool(uint256 assets, address receiver) external;

    function calcUnrealisedDebt() external view returns (uint256 unrealisedDebt);

    function calcUnrealisedDebt(uint256 realisedDebt) external view returns (uint256 unrealisedDebt);
}
