// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import {Auth} from "../lib/solmate/src/auth/Auth.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IVault.sol";


contract LiquidityPool is ERC4626, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public vaultFactory;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _liquidator,
        address _feeCollector,
        address _vaultFactory
    ) ERC4626(_asset, _name, _symbol) Owned(msg.sender) {
        liquidator = _liquidator;
        feeCollector = _feeCollector;
        vaultFactory = _vaultFactory;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANCHES LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public totalWeight;
    address public liquidator;

    uint256[] public weights;
    address[] public tranches;

    mapping(address => bool) public isTranche;

    modifier onlyTranche() {
        require(isTranche[msg.sender], "UNAUTHORIZED");
        _;
    }

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

    function deposit(uint256 assets, address receiver) public override onlyTranche returns (uint256 shares) {
        syncInterests();
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        totalHoldings += assets;    
    }

    function mint(uint256 shares, address receiver) public override onlyTranche returns (uint256 assets) {
        syncInterests();
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
        syncInterests();
        shares = super.withdraw(assets, receiver, owner);
        totalHoldings -= assets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        syncInterests();
        assets = super.redeem(shares, receiver, owner);
        totalHoldings -= assets;
    }

    function depositViaTranche(uint256 assets, address from) external onlyTranche {
        syncInterests();

        uint256 shares = previewDeposit(assets);
        // Check for rounding error since we round down in previewDeposit.
        require(shares != 0, "ZERO_SHARES");

        _mint(msg.sender, shares);

        totalHoldings += assets;

        asset.safeTransferFrom(from, address(this), assets);
    }

    function withdrawViaTranche(uint256 assets) external onlyTranche {
        syncInterests();
        
        uint256 shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        _burn(msg.sender, shares);

        totalHoldings -= assets;

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            LENDING LOGIC
    //////////////////////////////////////////////////////////////*/

    address public debtToken;

    function setDebtToken(address _debtToken) external onlyOwner {
        debtToken = _debtToken;
    }

    function takeLoan(uint256 amount, address vault, address to) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_TL: Not a vault");

        //Call vault to check if there is sufficient collateral
        require(IVault(vault).lockCollateral(amount, address(asset)), 'LP_TL: Reverted');

        //Check allowances to send underlying to to

        //Process interests since last update
        syncInterests();

        //Check if there is sufficient liquidity in pool? (check or let is fail on the transfer?)
        //Update allowances
        asset.safeTransfer(to, assets);

        ERC4626(debtToken).deposit(amount, vault);

        //Update interest rates
    }

    function repayLoan(uint256 amount, address vault, address from) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_RL: Not a vault");

        //Process interests since last update
        syncInterests();

        asset.safeTransferFrom(from, address(this), assets);

        ERC4626(debtToken).withdraw(amount, from, vault);

        //Update interest rates

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

    //ToDo: optimise storage allocations
    uint64 interstRate; //18 decimals precision
    uint32 lastSyncedBlock;
    uint256 public constant YEARLY_BLOCKS = 2628000;

    function syncInterests() internal {
        uint256 unrealisedDebt = uint256(calcUnrealisedDebt());

        //Sync interests for borrowers
        IDebtToken(debtToken).syncInterests(unrealisedDebt);

        //Sync interests for LP and Protocol Treasury
        _processInterests(unrealisedDebt);
    }

    function calcUnrealisedDebt() internal returns (uint128 unrealisedDebt) {
        realisedDebt = uint128(ERC4626(debtToken).totalAssets());

        uint128 base;
        uint128 exponent;

        unchecked {
            //gas: can't overflow: 1e18 + uint64 <<< uint128
            base = uint128(1e18) + interstRate;

            //gas: only overflows when blocks.number > 894262060268226281981748468
            //in practice: assumption that delta of blocks < 341640000 (150 years)
            //as foreseen in LogExpMath lib
            exponent = uint128(
                ((block.number - lastSyncedBlock) * 1e18) / YEARLY_BLOCKS
            );

            //gas: taking an imaginary worst-case D- tier assets with max interest of 1000%
            //over a period of 5 years
            //this won't overflow as long as opendebt < 3402823669209384912995114146594816
            //which is 3.4 million billion *10**18 decimals

            unrealisedDebt = uint128(
                (realisedDebt * (LogExpMath.pow(base, exponent) - 1e18)) /
                    1e18
            );
        }
    }

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
