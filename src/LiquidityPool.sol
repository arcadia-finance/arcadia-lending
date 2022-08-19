/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import {Auth} from "../lib/solmate/src/auth/Auth.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./utils/LogExpMath.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IVault.sol";

/**
 * @title Liquidity Pool
 * @author Arcadia Finance
 * @notice The Lending pool contains the main logic to provide liquidity and take or repay loans for a certain asset
 * @dev Protocol is according the ERC4626 standard, with a certain ERC20 as underlying
 */
contract LiquidityPool is ERC4626, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public vaultFactory;

    /**
     * @notice The constructor for a liquidity pool
     * @param _asset The underlying ERC-20 token of the Liquidity Pool
     * @param _liquidator The address of the liquidator
     * @param _treasury The address of the protocol treasury
     * @param _vaultFactory The address of the vault factory
     * @dev The name and symbol of the pool are automatically generated, based on the name and symbol of the underlying token
     */
    constructor(
        ERC20 _asset,
        address _liquidator,
        address _treasury,
        address _vaultFactory
    ) ERC4626(
        _asset,
        string(abi.encodePacked("Arcadia ", _asset.name(), " Pool")),
        string(abi.encodePacked("arc", _asset.symbol()))
    ) Owned(msg.sender) {
        liquidator = _liquidator;
        treasury = _treasury;
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

    /**
     * @notice Adds a tranche to the Liquidity Pool
     * @param tranche The address of the Tranche
     * @param weight The weight of the specific Tranche
     * @dev The order of the tranches is important, the most senior tranche is at index 0, the most junior at the last index.
     * @dev Each Tranche is an ERC-4626 contract
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev ToDo: For now manually add newly created tranche, do via factory in future?
     */
    function addTranche(address tranche, uint256 weight) public onlyOwner {
        require(!isTranche[tranche], "TR_AD: Already exists");
        totalWeight += weight;
        weights.push(weight);
        tranches.push(tranche);
        isTranche[tranche] = true;
    }

    /**
     * @notice Changes the weight of a specific tranche
     * @param index The index of the Tranche for which a new weight is being set
     * @param weight The new weight of the Tranche at the index
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev ToDo: TBD of we want the weight to be changeable?
     */
    function setWeight(uint256 index, uint256 weight) public onlyOwner {
        require(index < tranches.length, "TR_SW: Inexisting Tranche");
        totalWeight = totalWeight - weights[index] + weight;
        weights[index] = weight;
    }

    /**
     * @notice Removes the tranche at the last index (most junior)
     * @param index The index of the last Tranche
     * @param tranche The address of the last Tranche
     * @dev This function is only be called by the function _processDefault(uint256 assets), when there is a default as big (or bigger) 
     *      as the complete principal of the most junior tranche
     * @dev Passing the input parameters to the function saves gas compared to reading the address and index of the last tranche from memory.
     *      No need to be check if index and tranche are indeed of the last tranche since function is only called by _processDefault.
     */
    function removeLastTranche(uint256 index, address tranche) internal {
        totalWeight -= weights[index];
        isTranche[tranche] = false;
        weights.pop();
        tranches.pop();
    }

    /**
     * @notice Function for unit testing purposes only
     * @param index The index of the last Tranche
     * @param tranche The address of the last Tranche
     * @dev ToDo: Remove before deploying
     */
    function testRemoveLastTranche(uint256 index, address tranche) public {
        removeLastTranche( index, tranche);
    }

    /*///////////////////////////////////////////////////////////////
                    PROTOCOL FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    uint256 public feeWeight;
    address public treasury;

    /**
     * @notice Changes the weight of the protocol fee
     * @param _feeWeight The new weight of the protocol fee
     * @dev The weight the fee determines the relative share of the yield (interest payments) that goes to the protocol treasury
     * @dev ToDo: TBD of we want the weight to be changeable, should be fixed percentage of weight? Now protocol yield is ruggable
     */
    function setFeeWeight(uint256 _feeWeight) external onlyOwner {
        totalWeight = totalWeight - feeWeight + _feeWeight;
        feeWeight = _feeWeight;
    }

    /**
     * @notice Sets new treasury address
     * @param _treasury The new address of the treasury
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modification of the standard ERC-4626 deposit implementation
     * @param assets the amount of assets of the underlying ERC-20 token being deposited
     * @param from The address of the origin of the underlying ERC-20 token, who deposits assets via a Tranche
     * @return shares The corresponding amount of shares minted
     * @dev This function can only be called by Tranches.
     * @dev IMPORTANT, this function deviates from the standard, instead of the parameter 'receiver':
     *      (this is always msg.sender, a tranche), the second parameter is 'from':
     *      (the origin of the underlying ERC-20 token, who deposits assets via a Tranche)
     */
    function deposit(uint256 assets, address from) public override onlyTranche returns (uint256 shares) {
        _syncInterests();
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(from, address(this), assets);

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, msg.sender, assets, shares);

        totalHoldings += assets;

        _updateInterestRate();
    }

    /**
     * @notice Modification of the standard ERC-4626 mint implementation
     * @dev Token not mintable
     */
    function mint(uint256, address) public pure override returns (uint256) {
        revert("MINT_NOT_SUPPORTED");
    }

    /**
     * @notice Modification of the standard ERC-4626 withdraw implementation
     * @param assets the amount of assets of the underlying ERC-20 token being withdrawn
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     * @param owner_ The address of the owner of the assets being withdrawn
     * @return shares The corresponding amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override returns (uint256 shares) {
        _syncInterests();
        shares = super.withdraw(assets, receiver, owner_);
        totalHoldings -= assets;

        _updateInterestRate();
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
    ) public override returns (uint256 assets) {
        _syncInterests();
        assets = super.redeem(shares, receiver, owner_);
        totalHoldings -= assets;

        _updateInterestRate();
    }

    /*//////////////////////////////////////////////////////////////
                            LENDING LOGIC
    //////////////////////////////////////////////////////////////*/

    event CreditApproval(address indexed vault, address indexed beneficiary, uint256 amount);

    address public debtToken;
    mapping(address => mapping(address => uint256)) public creditAllowance;

    /**
     * @notice Set the Debt Token contract of the Liquidity Pool
     * @param _debtToken The address of the Debt Token
     * @dev Debt Token is an ERC-4626 contract
     * @dev ToDo: For now manually add newly created tranche, do via factory in future?
     * @dev ToDo: TBD of we want the debt token to be changeable
     */
    function setDebtToken(address _debtToken) external onlyOwner {
        debtToken = _debtToken;
    }

    /**
     * @notice Approve a beneficiacy to take out a loan against an Arcadia Vault
     * @param beneficiary The address of beneficiacy who can take out loan backed by an Arcadia Vault
     * @param amount The amount of underlying ERC-20 tokens to be lent out
     * @param vault The address of the Arcadia Vault backing the loan
     * @dev todo also implement permit (EIP-2612)?
     * @dev todo If we keep a mapping from vaultaddress to owner on factory, we can do two requires at once and avoid two call to vault
     */
    function approveBeneficiary(address beneficiary, uint256 amount, address vault) public returns (bool) {
        require(IFactory(vaultFactory).isVault(vault), "LP_AB: Not a vault");
        require(IVault(vault).owner() == msg.sender, "LP_AB: UNAUTHORIZED");

        creditAllowance[vault][beneficiary] = amount;

        emit CreditApproval(vault, beneficiary, amount);

        return true;
    }

    /**
     * @notice Takes out a loan backed by collateral of an Arcadia Vault
     * @param amount The amount of underlying ERC-20 tokens to be lent out
     * @param vault The address of the Arcadia Vault backing the loan
     * @param to The final beneficiary who receives the underlying tokens
     * @dev The sender might be different as the owner if they have the proper allowances
     */
    function takeLoan(uint256 amount, address vault, address to) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_TL: Not a vault");

        //Call vault to check if there is sufficient collateral
        require(IVault(vault).lockCollateral(amount, address(asset)), 'LP_TL: Reverted');

        //Check allowances to send underlying to to
        if (IVault(vault).owner() != msg.sender) {
            uint256 allowed = creditAllowance[vault][msg.sender];
            if (allowed != type(uint256).max) creditAllowance[vault][msg.sender] = allowed - amount;
        }

        //Process interests since last update
        _syncInterests();

        //Check if there is sufficient liquidity in pool? (check or let it fail on the transfer?)
        //Update allowances
        asset.safeTransfer(to, amount);

        ERC4626(debtToken).deposit(amount, vault);

        //Update interest rates
        _updateInterestRate();
    }

    /**
     * @notice repays a loan
     * @param amount The amount of underlying ERC-20 tokens to be repaid
     * @param vault The address of the Arcadia Vault backing the loan
     * @dev ToDo: should it be possible to trigger a repay on behalf of an other account, 
     *      If so, work with allowances
     */
    function repayLoan(uint256 amount, address vault) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_RL: Not a vault");

        //Process interests since last update
        _syncInterests();

        asset.safeTransferFrom(msg.sender, address(this), amount);

        ERC4626(debtToken).withdraw(amount, vault, vault);

        //Call vault to unlock collateral

        //Update interest rates
        _updateInterestRate();
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
    uint64 public interstRate; //18 decimals precision
    uint32 public lastSyncedBlock;
    uint256 public constant YEARLY_BLOCKS = 2628000;

    function _syncInterests() internal {
        uint256 unrealisedDebt = uint256(_calcUnrealisedDebt());

        //Sync interests for borrowers
        IDebtToken(debtToken).syncInterests(unrealisedDebt);

        //Sync interests for LPs and Protocol Treasury
        _syncInterestsToLiquidityPool(unrealisedDebt);
    }

    function _calcUnrealisedDebt() internal view returns (uint128 unrealisedDebt) {
        uint128 realisedDebt = uint128(ERC4626(debtToken).totalAssets());

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

    function _syncInterestsToLiquidityPool(uint256 assets) internal {
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

        //Protocol fee
        _mint(treasury, remainingShares);

        totalHoldings += assets;
        
    }

    function testSyncInterestsToLiquidityPool(uint256 assets) public onlyOwner {
        _syncInterestsToLiquidityPool(assets);
    }

    function _updateInterestRate() internal {
        //ToDo
        interstRate = 200000000000000000;
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
