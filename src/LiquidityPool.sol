// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import {Auth} from "../lib/solmate/src/auth/Auth.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import "./interfaces/ITranche.sol";


contract LiquidityPool is ERC4626, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

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
        address _liquidator,
        address _feeCollector
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {
        liquidator = _liquidator;
        feeCollector = _feeCollector;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANCHES LOGIC
    //////////////////////////////////////////////////////////////*/

    //For now manually add newly created tranche, do via factory in future?
    function addTranche(address tranche, uint256 weight) public onlyOwner {
        totalWeight += weight;
        weights.push(weight);
        tranches.push(tranche);
        isTranche[tranche] = true;
        asset.approve(tranche, type(uint256).max); //todo Avoid approve if we send tokens via LP instead of tranche on redeems
    }

    function removeLastTranche(uint256 index, address tranche) internal {
        totalWeight -= weights[index];
        isTranche[tranche] = false;
        weights.pop();
        tranches.pop();
    }

    function setWeight(uint256 index, uint256 weight) public onlyOwner {
        totalWeight = totalWeight - weights[index] + weight;
        weights[index] = weight;
    }

    /*///////////////////////////////////////////////////////////////
                           FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    uint256 public feeWeight;
    address public feeCollector;

    function setFeeWeight(uint256 _feeWeight) external onlyOwner {
        totalWeight = totalWeight - feeWeight + _feeWeight;
        feeWeight = _feeWeight;
    }

    function setFeeCollector(address newFeeCollector) external onlyOwner {
        feeCollector = newFeeCollector;
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

        totalHoldings += assets;    
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        require(isTranche[receiver], "NO_TRANCHE");
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        totalHoldings += assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = super.withdraw(assets, receiver, owner);
        totalHoldings -= assets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        totalHoldings -= assets;
    }

    function depositViaTranche(uint256 assets) external onlyTranche {
        uint256 shares = previewDeposit(assets);
        // Check for rounding error since we round down in previewDeposit.
        require(shares != 0, "ZERO_SHARES");

        _mint(msg.sender, shares);

        totalHoldings += assets;
    }

    function withdrawViaTranche(uint256 assets) external onlyTranche {
        uint256 shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(owner, shares);

        totalHoldings -= assets;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public totalHoldings;

    function totalAssets() public view override returns (uint256) {
        return totalHoldings;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _processInterests(uint256 assets) internal {
        uint256 shares = previewDeposit(assets);
        uint256 remainingShares = shares;

        for (uint256 i; i < tranches.length; ) {
            uint256 trancheShare = shares.mulDivUp(weights[i], totalWeight);
            _mint(tranches[i], trancheShare);
            unchecked {
                remainingShares -= remainingShares;
                ++i;
            }
        }

        _mint(feeCollector, remainingShares);

        totalHoldings += assets;
        
    }

    function testProcessInterests(uint256 assets) public onlyOwner {
        _processInterests(assets);
    }

    /*//////////////////////////////////////////////////////////////
                            LOAN DEFAULT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _processDefault(uint256 assets) internal {
        if (totalHoldings < assets) {
            //Should never be possible
            assets = totalHoldings;
        }

        totalHoldings -= assets;

        uint256 shares = convertToShares(assets);

        for (uint256 i = tranches.length-1; i >= 0; ) {
            address tranche = tranches[i];
            uint256 maxShares = maxRedeem(tranche);
            if (shares < maxShares) {
                _burn(tranche, shares);
                break;
            } else {
                ITranche(tranche).lock();
                _burn(tranche, maxShares);
                removeLastTranche(i, tranche);
                unchecked {
                    shares -= maxShares;
                }
            }

            unchecked {
                --i;
            }
        }

    }

    function testProcessDefault(uint256 assets) public onlyOwner {
        _processDefault(assets);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
