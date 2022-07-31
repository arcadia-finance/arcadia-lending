// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";


contract LiquidityPool is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    uint256 totalWeight;
    address liquidator;

    uint256[] weights;
    address[] tranches;

    mapping(address => bool) isTranche;

    modifier onlyTranche() {
        require(isTranche[msg.sender], "UNAUTHORIZED");
        _;
    }

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _liquidator
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {
        liquidator = _liquidator;
    }

    //For now manually add newly created tranche, do via factory in future?
    function addTranche(address tranche, uint256 weight) public onlyOwner {
        totalWeight += weight;
        weights.push(weight);
        tranches.push(tranche);
        isTranche[tranche] = true;
        asset.approve(tranche, type(uint256).max);
    }

    function setWeight(uint256 index, uint256 weight) public onlyOwner {
        weights[index] = weight;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        require(isTranche[receiver], "NO_TRANCHE");
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        require(isTranche[receiver], "NO_TRANCHE");
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function depositViaTranche(uint256 assets) external onlyTranche {
        uint256 shares = previewDeposit(assets);
        // Check for rounding error since we round down in previewDeposit.
        require(shares != 0, "ZERO_SHARES");

        _mint(msg.sender, shares);
    }

    function withdrawViaTranche(uint256 assets) external onlyTranche {
        uint256 shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(owner, shares);

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
