/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";

contract Tranche is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    ERC4626 public liquidityPool;
    bool public locked = false;

    modifier notLocked() {
        require(!locked, "LOCKED");
        _;
    }

    constructor(
        ERC4626 _liquidityPool,
        string memory _prefix,
        string memory _prefixSymbol
    ) ERC4626(
        _liquidityPool.asset(),
        string(abi.encodePacked(_prefix, " Arcadia ", _liquidityPool.asset().name())),
        string(abi.encodePacked(_prefixSymbol, "arc", _liquidityPool.asset().symbol()))
    ) Owned(msg.sender) {
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

        // Need to transfer (via liquidityPool.deposit()) before minting or ERC777s could reenter.
        liquidityPool.deposit(assets, msg.sender);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override notLocked returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer (via liquidityPool.deposit()) before minting or ERC777s could reenter.
        liquidityPool.deposit(assets, msg.sender);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
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

        liquidityPool.withdraw(assets, receiver, address(this));

        _burn(_owner, shares);

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);
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

        _burn(_owner, shares);

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);

        liquidityPool.withdraw(assets, receiver, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256 assets) {
        assets =  liquidityPool.maxWithdraw(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
