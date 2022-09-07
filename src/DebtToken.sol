/** 
    Created by Arcadia Finance
    https://www.arcadia.finance
    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import "./interfaces/ILendingPool.sol";
import "./LendingPool.sol";

/**
 * @title Debt Token
 * @author Arcadia Finance
 * @notice The Logic to do the debt accounting for a lending pool for a certain ERC20 token
 * @dev Protocol is according the ERC4626 standard, with a certain ERC20 as underlying
 */
contract DebtToken is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    LendingPool lendingPool;

    /**
     * @notice The constructor for the debt token
     * @param _lendingPool the Lending Pool of the underlying ERC-20 token, with the lending logic.
     */
    constructor(
        LendingPool _lendingPool
    ) ERC4626(
        ILendingPool(address(_lendingPool)).asset(),
        string(abi.encodePacked("Arcadia ", ILendingPool(address(_lendingPool)).asset().name(), " Debt")),
        string(abi.encodePacked("darc", ILendingPool(address(_lendingPool)).asset().symbol()))
    ) Owned(msg.sender) {
        lendingPool = _lendingPool;
    }

    modifier onlyLendingPool() {
        require(address(lendingPool) == msg.sender, "UNAUTHORIZED");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            DEBT LOGIC
    //////////////////////////////////////////////////////////////*/
    uint256 public totalDebt;

    /**
     * @notice Returns the total amount of outstanding debt in the underlying asset
     * @return totalDebt The total debt in underlying assets
     */
    function totalAssets() public view override returns (uint256) {
        return totalDebt;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @param assets The amount of assets of the underlying ERC-20 token being loaned out
     * @param receiver The Arcadia vault with collateral covering the loan
     * @return shares The corresponding amount of debt shares minted
     * @dev Only the Lending Pool can issue debt
     */
    function deposit(uint256 assets, address receiver) public override onlyLendingPool returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        totalDebt += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256, address) public pure override returns (uint256) {
        revert('MINT_NOT_SUPPORTED');
    }

    /**
     * @notice Modification of the standard ERC-4626 withdraw implementation
     * @param assets The amount of assets of the underlying ERC-20 token being paid back
     * @param receiver Will always be the Lending Pool
     * @param owner_ The Arcadia vault with collateral covering the loan
     * @return shares The corresponding amount of debt shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override onlyLendingPool returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(owner_, shares);

        totalDebt -= assets;

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);

    }

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert('REDEEM_NOT_SUPPORTED');
    }

    /*//////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Realises interest for all open debt positions
     * @param assets The total amount of assets of the underlying ERC-20 tokens that needs to be paid as interests
     * @dev Calculation of the amount of interests since last sync is done in the Lending Pool.
     *      After calculation, the Lending Pool pays out the interests to the Liquidity Providers,
     *      and calls this Debt Token contract to add the intersts to the outstanding debt.
     */
    function syncInterests(uint256 assets) public onlyLendingPool {
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

    /* //////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    ////////////////////////////////////////////////////////////// */

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
