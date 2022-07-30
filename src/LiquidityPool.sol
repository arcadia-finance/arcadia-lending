// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
//import "../lib/solmate/src/tokens/ERC20.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";

contract LiquidityPool is ERC4626, Owned {

    address[] tranches;
    uint256[] weights;
    uint256 totalWeight;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        return super.deposit(assets, receiver);
    }

    //For now manually add newly created tranche, do via factory in future?
    function addTranche(address tranche, uint256 weight) public onlyOwner {
        totalWeight += weight;
        weights.push(weight);
        tranches.push(tranche);
    }

    function setWeight(uint256 index, uint256 weight) public onlyOwner {
        weights[index] = weight;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
