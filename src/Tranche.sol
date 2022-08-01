// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import "./interfaces/ILiquidityPool.sol";

contract LiquidityPool is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    ERC4626 liquidityPool;
    bool public locked = false;

    modifier notLocked() {
        require(!locked, "LOCKED");
        _;
    }

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        ERC4626 _liquidityPool
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {
        liquidityPool = _liquidityPool;
    }

    /*//////////////////////////////////////////////////////////////
                        LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    function lock() public {
        require(msg.sender == address(liquidityPool), "UNAUTHORIZED");
        locked = true;
    }

    function unLock() public onlyOwner {
        locked = false;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override notLocked returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        ILiquidityPool(address(liquidityPool)).depositViaTranche(assets);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(liquidityPool), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        //afterDeposit(assets, shares);

    }

    function mint(uint256 shares, address receiver) public override notLocked returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.
        ILiquidityPool(address(liquidityPool)).depositViaTranche(assets);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(liquidityPool), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        //afterDeposit(assets, shares);

    }

    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public override notLocked returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
        }

        ILiquidityPool(address(liquidityPool)).withdrawViaTranche(assets);

        //beforeWithdraw(assets, shares);

        _burn(_owner, shares);

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address _owner
    ) public override notLocked returns (uint256 assets) {
        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
        ILiquidityPool(address(liquidityPool)).withdrawViaTranche(assets);

        //beforeWithdraw(assets, shares);

        _burn(_owner, shares);

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);

        asset.safeTransfer(receiver, assets);
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
