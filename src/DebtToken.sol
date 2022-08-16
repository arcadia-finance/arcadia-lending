// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";

contract DebtToken is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    ERC4626 liquidityPool;

    constructor(
        ERC4626 _liquidityPool
    ) ERC4626(
        _liquidityPool.asset(),
        string(abi.encodePacked("Arcadia ", _liquidityPool.asset().name(), " Debt")),
        string(abi.encodePacked("darc", _liquidityPool.asset().symbol()))
    ) Owned(msg.sender) {
        liquidityPool = _liquidityPool;
    }

    modifier onlyLiquidityPool() {
        require(address(liquidityPool) == msg.sender, "UNAUTHORIZED");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            DEBT LOGIC
    //////////////////////////////////////////////////////////////*/
    uint256 public totalDebt;

    function totalAssets() public view override returns (uint256) {
        return totalDebt;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public override onlyLiquidityPool returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        totalDebt += assets;

        emit Deposit(msg.sender, receiver, assets, shares);

        //afterDeposit(assets, shares);

    }

    function mint(uint256, address) public pure override returns (uint256) {
        revert('MINT_NOT_SUPPORTED');
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public override onlyLiquidityPool returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(_owner, shares);

        totalDebt -= assets;

        emit Withdraw(msg.sender, receiver, _owner, assets, shares);

    }

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert('REDEEM_NOT_SUPPORTED');
    }

    /*//////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
    //////////////////////////////////////////////////////////////*/

    function syncInterests(uint256 assets) public onlyLiquidityPool {
        totalDebt += assets;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address, uint256) public pure override returns (bool) {
        revert('APPROVE_NOT_SUPPORTED');
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert('TRANSFER_NOT_SUPPORTED');
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert('TRANSFERFROM_NOT_SUPPORTED');
    }

    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) public pure override {
        revert('PERMIT_NOT_SUPPORTED');
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
