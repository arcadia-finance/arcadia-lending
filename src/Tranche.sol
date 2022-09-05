/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import "./interfaces/ILiquidityPool.sol";

/**
 * @title tranche
 * @author Arcadia Finance
 * @notice The Logic to provide Liquidity for a lending pool for a certain ERC20 token
 * @dev Protocol is according the ERC4626 standard, with a certain ERC20 as underlying
 */
contract Tranche is ERC4626, Owned {
    using SafeTransferLib for ERC20;

    ERC20 public liquidityPool;
    bool public locked = false;

    modifier notLocked() {
        require(!locked, "TRANCHE: LOCKED");
        _;
    }

    /**
     * @notice The constructor for a tranche
     * @param _liquidityPool the Liquidity Pool of the underlying ERC-20 token, with the lending logic.
     * @param _prefix The prefix of the contract name (eg. Senior -> Mezzanine -> Junior)
     * @param _prefixSymbol The prefix of the contract symbol (eg. SR  -> MZ -> JR)
     * @dev The name and symbol of the tranche are automatically generated, based on the name and symbol of the underlying token
     */
    constructor(
        ERC20 _liquidityPool,
        string memory _prefix,
        string memory _prefixSymbol
    ) ERC4626(
        ILiquidityPool(address(_liquidityPool)).asset(),
        string(abi.encodePacked(_prefix, " Arcadia ", ILiquidityPool(address(_liquidityPool)).asset().name())),
        string(abi.encodePacked(_prefixSymbol, "arc", ILiquidityPool(address(_liquidityPool)).asset().symbol()))
    ) Owned(msg.sender) {
        liquidityPool = _liquidityPool;
    }

    /*//////////////////////////////////////////////////////////////
                        LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Locks the tranche in case all liquidity of the tranche is written of due to bad debt
     * @dev Only the Liquidity Pool can call this function, only trigger is a severe default event.
     */
    function lock() public {
        require(msg.sender == address(liquidityPool), "UNAUTHORIZED");
        locked = true;
    }

    /**
     * @notice Unlocks the tranche.
     * @dev Only the Owner can call this function, since tranches are locked due to complete defaults,
     *      This function will only be called to partially refund existing share-holders after a default.
     */
    function unLock() public onlyOwner {
        locked = false;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @param assets The amount of assets of the underlying ERC-20 token being deposited
     * @param receiver The address that receives the minted shares.
     * @return shares The amount of shares minted
     * @dev This contract does not directly transfers the underlying assets from the sender to the receiver.
     *      Instead it calls the deposit of the Liquidity Pool which calls the transferFrom of the underlying assets.
     *      Hence the sender should not give this contract an allowance to transfer the underlying asset but the Liquidity Pool.
     */
    function deposit(uint256 assets, address receiver) public override notLocked returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer (via liquidityPool.deposit()) before minting or ERC777s could reenter.
        ILiquidityPool(address(liquidityPool)).deposit(assets, msg.sender);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Modification of the standard ERC-4626 mint implementation
     * @param shares The amount of shares minted
     * @param receiver The address that receives the minted shares.
     * @return assets The corresponding amount of assets of the underlying ERC-20 token being deposited
     * @dev This contract does not directly transfers the underlying assets from the sender to the receiver.
     *      Instead it calls the deposit of the Liquidity Pool which calls the transferFrom of the underlying assets.
     *      Hence the sender should not give this contract an allowance to transfer the underlying asset but the Liquidity Pool.
     */
    function mint(uint256 shares, address receiver) public override notLocked returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer (via liquidityPool.deposit()) before minting or ERC777s could reenter.
        ILiquidityPool(address(liquidityPool)).deposit(assets, msg.sender);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Modification of the standard ERC-4626 withdraw implementation
     * @param assets The amount of assets of the underlying ERC-20 token being withdrawn
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     * @param owner_ The address of the owner of the assets being withdrawn
     * @return shares The corresponding amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override notLocked returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner_][msg.sender] = allowed - shares;
        }

        ILiquidityPool(address(liquidityPool)).withdraw(assets, receiver, address(this));

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /**
     * @notice Modification of the standard ERC-4626 redeem implementation
     * @param shares the amount of shares being redeemed
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     * @param owner_ The address of the owner of the shares being redeemed
     * @return assets The corresponding amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override notLocked returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner_][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);

        ILiquidityPool(address(liquidityPool)).withdraw(assets, receiver, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets, to which liquidity providers have a claim
     * @return assets The total amount of underlying assets, to which liquidity providers have a claim
     * @dev The Liquidity Pool does the accounting of the outstanding claim on liquidity per tranche.
     */
    function totalAssets() public view override returns (uint256 assets) {
        assets =  liquidityPool.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
