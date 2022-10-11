/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import {ERC20, ERC4626} from "../lib/solmate/src/mixins/ERC4626.sol";

/**
 * @title Debt Token
 * @author Arcadia Finance
 * @notice The Logic to do the debt accounting for a lending pool for a certain ERC20 token
 * @dev Protocol is according the ERC4626 standard, with a certain ERC20 as underlying
 */
abstract contract DebtToken is ERC4626 {
    uint256 public realisedDebt;

    /**
     * @notice The constructor for the debt token
     * @param asset The underlying ERC-20 token in which the debt is denominated
     */
    constructor(ERC20 asset)
        ERC4626(
            asset,
            string(abi.encodePacked("Arcadia ", asset.name(), " Debt")),
            string(abi.encodePacked("darc", asset.symbol()))
        )
    {}

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of outstanding debt in the underlying asset
     * @return totalDebt The total debt in underlying assets
     */
    function totalAssets() public view virtual override returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @dev No public deposit allowed
     */
    function deposit(uint256, address) public pure override returns (uint256) {
        revert("DEPOSIT_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @param assets The amount of assets of the underlying ERC-20 token being loaned out
     * @param receiver The Arcadia vault with collateral covering the loan
     * @return shares The corresponding amount of debt shares minted
     * @dev Only the Lending Pool (which inherits this contract) can issue debt
     */
    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        realisedDebt += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @dev No public mint allowed
     */
    function mint(uint256, address) public pure override returns (uint256) {
        revert("MINT_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 withdraw implementation
     * @dev No public withdraw allowed
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert("WITHDRAW_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 withdraw implementation
     * @param assets The amount of assets of the underlying ERC-20 token being paid back
     * @param receiver Will always be the Lending Pool
     * @param owner_ The Arcadia vault with collateral covering the loan
     * @return shares The corresponding amount of debt shares redeemed
     * @dev Only the Lending Pool (which inherits this contract) can issue debt
     */
    function _withdraw(uint256 assets, address receiver, address owner_) internal returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(owner_, shares);

        realisedDebt -= assets;

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /**
     * @notice Modification of the standard ERC-4626 redeem implementation
     * @dev No public redeem allowed
     */
    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert("REDEEM_NOT_SUPPORTED");
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modification of the standard ERC-4626 approve implementation
     * @dev No public approve allowed
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("APPROVE_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 transfer implementation
     * @dev No public transfer allowed
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 transferFrom implementation
     * @dev No public transferFrom allowed
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("TRANSFERFROM_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 permit implementation
     * @dev No public permit allowed
     */
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) public pure override {
        revert("PERMIT_NOT_SUPPORTED");
    }

    /* //////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    ////////////////////////////////////////////////////////////// */

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
