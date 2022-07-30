// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
//import "../lib/solmate/src/tokens/ERC20.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";

contract LiquidityPool is ERC4626, Owned {

    ERC4626 liquidityPool;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        ERC4626 _liquidityPool
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {
        liquidityPool = _liquidityPool;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return liquidityPool.maxWithdraw(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
