/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/solmate/src/auth/Owned.sol";
import {Auth} from "../lib/solmate/src/auth/Auth.sol";
import "../lib/solmate/src/tokens/ERC20.sol";
import "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./utils/LogExpMath.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IDebtToken.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ILendingPool.sol";
import "./TrustedProtocol.sol";

/**
 * @title Lending Pool
 * @author Arcadia Finance
 * @notice The Lending pool contains the main logic to provide liquidity and take or repay loans for a certain asset
 */
contract LendingPool is Owned, TrustedProtocol {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public vaultFactory;
    ERC20 public immutable asset;

    /**
     * @notice The constructor for a lending pool
     * @param _asset The underlying ERC-20 token of the Lending Pool
     * @param _treasury The address of the protocol treasury
     * @param _vaultFactory The address of the vault factory
     * @dev The name and symbol of the pool are automatically generated, based on the name and symbol of the underlying token
     */
    constructor(
        ERC20 _asset,
        address _treasury,
        address _vaultFactory
    ) Owned(msg.sender) TrustedProtocol() {
        asset = _asset;
        treasury = _treasury;
        vaultFactory = _vaultFactory;
        name = string(abi.encodePacked("Arcadia ", _asset.name(), " Pool"));
        symbol = string(abi.encodePacked("arc", _asset.symbol()));
        decimals = _asset.decimals();
    }
    // Lending Pool Metadata
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public supplyBalances;


    /* //////////////////////////////////////////////////////////////
                            TRANCHES LOGIC
    ////////////////////////////////////////////////////////////// */

    uint256 public totalWeight;

    // Tranche
    uint256[] public weights;
    address[] public tranches;

    mapping(address => bool) public isTranche;

    modifier onlyTranche() {
        require(isTranche[msg.sender], "UNAUTHORIZED");
        _;
    }

    /**
     * @notice Adds a tranche to the Lending Pool
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
    function _popTranche(uint256 index, address tranche) internal {
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
    function testPopTranche(uint256 index, address tranche) public {
        _popTranche( index, tranche);
    }

    /* ///////////////////////////////////////////////////////////////
                    PROTOCOL FEE CONFIGURATION
    ////////////////////////////////////////////////////////////// */

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

    /* //////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Deposit assets in the Lending Pool
     * @param assets the amount of assets of the underlying ERC-20 token being deposited
     * @param from The address of the origin of the underlying ERC-20 token, who deposits assets via a Tranche
     * @dev This function can only be called by Tranches.
     * @dev IMPORTANT, this function deviates from the standard, instead of the parameter 'receiver':
     *      (this is always msg.sender, a tranche), the second parameter is 'from':
     *      (the origin of the underlying ERC-20 token, who deposits assets via a Tranche)
     */
    function deposit(uint256 assets, address from) public onlyTranche {
        _syncInterests();

        asset.safeTransferFrom(from, address(this), assets);

        supplyBalances[msg.sender] += assets;
        totalSupply += assets;

        _updateInterestRate();
    }

    /**
     * @notice Withdraw assets from the Lending Pool
     * @param assets the amount of assets of the underlying ERC-20 token being withdrawn
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     */
    function withdraw(
        uint256 assets,
        address receiver
    ) public {
        _syncInterests();

        require(supplyBalances[msg.sender] >= assets, "LP_W: Withdraw amount should be lower than the supplied balance");

        supplyBalances[msg.sender] -= assets;
        totalSupply -= assets;

        asset.safeTransfer(receiver, assets);

        _updateInterestRate();
    }

    /* //////////////////////////////////////////////////////////////
                            LENDING LOGIC
    ////////////////////////////////////////////////////////////// */

    event CreditApproval(address indexed vault, address indexed beneficiary, uint256 amount);

    address public debtToken;
    mapping(address => mapping(address => uint256)) public creditAllowance;

    /**
     * @notice Set the Debt Token contract of the Lending Pool
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
     * @param to The address who receives the lended out underlying tokens
     * @dev The sender might be different as the owner if they have the proper allowances
     */
    function borrow(uint256 amount, address vault, address to) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_TL: Not a vault");

        //Check allowances to send underlying to to
        if (IVault(vault).owner() != msg.sender) {
            uint256 allowed = creditAllowance[vault][msg.sender];
            if (allowed != type(uint256).max) creditAllowance[vault][msg.sender] = allowed - amount;
        }

        //Call vault to check if there is sufficient collateral
        require(IVault(vault).increaseMarginPosition(address(asset), amount), 'LP_TL: Reverted');

        //Process interests since last update
        _syncInterests();

        //Transfer fails if there is insufficient liquidity in pool
        asset.safeTransfer(to, amount);

        if (amount != 0) ERC4626(debtToken).deposit(amount, vault);

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
    function repay(uint256 amount, address vault) public {

        require(IFactory(vaultFactory).isVault(vault), "LP_RL: Not a vault");

        //Process interests since last update
        _syncInterests();

        uint256 totalDebt = ERC4626(debtToken).maxWithdraw(vault);
        uint256 transferAmount = totalDebt > amount ? amount : totalDebt;

        asset.safeTransferFrom(msg.sender, address(this), transferAmount);

        ERC4626(debtToken).withdraw(transferAmount, vault, vault);

        //Call vault to unlock collateral
        require(IVault(vault).decreaseMarginPosition(address(asset), transferAmount), 'LP_RL: Reverted');

        //Update interest rates
        _updateInterestRate();
    }

    /* //////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
    ////////////////////////////////////////////////////////////// */

    //ToDo: optimise storage allocations
    uint64 public interestRate; //18 decimals precision
    uint32 public lastSyncedBlock;
    uint256 public constant YEARLY_BLOCKS = 2628000;

    /** 
     * @notice Syncs all unrealised debt (= interest for LP and treasury).
     * @dev Calculates the unrealised debt since last sync, and realises it by minting an aqual amount of
     *      debt tokens to all debt holders and interests to LPs and the treasury
    */
    function syncInterests() external {
        _syncInterests();
    }

    /** 
     * @notice Syncs all unrealised debt (= interest for LP and treasury).
     * @dev Calculates the unrealised debt since last sync, and realises it by minting an aqual amount of
     *      debt tokens to all debt holders and interests to LPs and the treasury
    */
    function _syncInterests() internal {
        uint256 unrealisedDebt = uint256(_calcUnrealisedDebt());

        //Sync interests for borrowers
        IDebtToken(debtToken).syncInterests(unrealisedDebt);

        //Sync interests for LPs and Protocol Treasury
        _syncInterestsToLendingPool(unrealisedDebt);
    }

    /** 
     * @notice Calculates the unrealised debt.
     * @dev To Find the unrealised debt over an amount of time, you need to calculate D[(1+r)^x-1].
     *      The base of the exponential: 1 + r, is a 18 decimals fixed point number
     *      with r the yearly interest rate.
     *      The exponent of the exponential: x, is a 18 decimals fixed point number.
     *      The exponent x is calculated as: the amount of blocks since last sync divided by the average of 
     *      blocks produced over a year (using a 12s average block time).
     *      _yearlyInterestRate = 1 + r expressed as 18 decimals fixed point number
     */
    function _calcUnrealisedDebt() internal returns (uint256 unrealisedDebt) {
        uint256 realisedDebt = ERC4626(debtToken).totalAssets();

        uint256 base;
        uint256 exponent;

        unchecked {
            //gas: can't overflow for reasonable interest rates
            base = 1e18 + interestRate;

            //gas: only overflows when blocks.number > 894262060268226281981748468
            //in practice: assumption that delta of blocks < 341640000 (150 years)
            //as foreseen in LogExpMath lib
            exponent = ((block.number - lastSyncedBlock) * 1e18) / YEARLY_BLOCKS;

            //gas: taking an imaginary worst-case scenario with max interest of 1000%
            //over a period of 5 years
            //this won't overflow as long as opendebt < 3402823669209384912995114146594816
            //which is 3.4 million billion *10**18 decimals

            unrealisedDebt = 
                (realisedDebt * (LogExpMath.pow(base, exponent) - 1e18)) /
                    1e18
            ;
        }

        lastSyncedBlock = uint32(block.number);
    }

    //todo: Function only for testing purposes, to delete as soon as foundry allows to test internal functions.
    function testCalcUnrealisedDebt() public returns (uint256 unrealisedDebt) {
        unrealisedDebt = _calcUnrealisedDebt();
    }

    /** 
     * @notice Syncs interest payments to the Lending providers and the treasury.
     * @param assets The total amount of underlying assets to be paid out as interests.
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev The Shares for each Tranche are rounded up, if the treasury receives the remaining shares and will hence loose
     *      part of their yield due to rounding errors (neglectable small).
     */
    function _syncInterestsToLendingPool(uint256 assets) internal {
        uint256 remainingAssets = assets;

        for (uint256 i; i < tranches.length; ) {
            uint256 trancheShare = assets.mulDivUp(weights[i], totalWeight);
            supplyBalances[tranches[i]] += trancheShare;
            unchecked {
                remainingAssets -= trancheShare;
                ++i;
            }
        }
        totalSupply += assets - remainingAssets;

        // Add the remainingAssets to the treasury balance
        supplyBalances[treasury] += remainingAssets;
        totalSupply += remainingAssets;
        
    }

    //todo: Function only for testing purposes, to delete as soon as foundry allows to test internal functions.
    function testSyncInterestsToLendingPool(uint256 assets) public onlyOwner {
        _syncInterestsToLendingPool(assets);
    }

    /* //////////////////////////////////////////////////////////////
                        INTEREST RATE LOGIC
    ////////////////////////////////////////////////////////////// */

    function updateInterestRate(uint64 _interestRate) external onlyOwner {
        //Todo: Remove function after _updateInterestRate() is implemented
        interestRate = _interestRate; //with 18 decimals precision
    }

    function _updateInterestRate() internal {
        //ToDo
    }

    /* //////////////////////////////////////////////////////////////
                        LIQUIDATION LOGIC
    ////////////////////////////////////////////////////////////// */

    address public liquidator;

    modifier onlyLiquidator() {
        require(liquidator == msg.sender, "UNAUTHORIZED");
        _;
    }

    /**
     * @notice Set's the contract address of the liquidator.
     * @param _liquidator The contract address of the liquidator
     */
    function setLiquidator(address _liquidator) public onlyOwner {
        liquidator = _liquidator;
    }

    /**
     * @notice Starts the liquidation of a vault.
     * @param vault The contract address of the liquidator.
     * @param debt The amount of debt that was issued.
     * @dev At the start of the liquidation the debt tokens are already burned,
     *      as such interests are not accrued during the liquidation.
     * @dev After the liquidation is finished, there are two options:
     *        1) the collateral is auctioned for more than the debt position
     *           and liquidator reward In this case the liquidator will transfer an equal amount
     *           as the debt position to the Lending Pool.
     *        2) the collateral is auctioned for less than the debt position
     *           and keeper fee -> the vault became under-collateralised and we have a default event.
     *           In this case the liquidator will call settleLiquidation() to settle the deficit.
     *           the Liquidator will transfer any remaining funds to the Lending Pool.
     */
    function liquidateVault(address vault, uint256 debt) public onlyLiquidator {
        ERC4626(debtToken).withdraw(debt, vault, vault);
    }

    /**
     * @notice Settles bad debt of liquidations.
     * @param default_ The amount of debt.that was not recouped by the auction
     * @param deficit The amount of debt that has to be repaid to the liquidator,
     *                if the liquidation fee was bigger than the auction proceeds
     * @dev This function is called by the Liquidator after a liquidation is finished,
     *      but only if there is bad debt.
     * @dev The liquidator will transfer the auction proceeds (the underlying asset)
     *      Directly back to the liquidity pool after liquidation.
     */
    function settleLiquidation(uint256 default_, uint256 deficit) public onlyLiquidator {
        if (deficit != 0) {
            //ToDo: The unhappy flow when there is not enough liquidity in the pool
            asset.transfer(liquidator, deficit);
        }
        _processDefault(default_);
    }

    /**
     * @notice Handles the bookkeeping in case of bad debt (Vault became undercollateralised).
     * @param assets The total amount of underlying assets that need to be written off as bad debt.
     * @dev The order of the tranches is important, the most senior tranche is at index 0, the most junior at the last index.
     * @dev The most junior tranche will loose its underlying capital first. If all liquidty of a certain Tranche is written off,
     *      the complete tranche is locked and removed. If there is still remaining bad debt, the next Tranche starts losing capital.
     */
    function _processDefault(uint256 assets) internal {
        if (totalSupply < assets) {
            //Should never be possible, this means the total protocol has more debt than claimable liquidity.
            assets = totalSupply;
        }

        for (uint256 i = tranches.length; i > 0; ) {
            unchecked {--i;}
            address tranche = tranches[i];
            uint256 maxBurned = supplyBalances[tranche];
            if (assets < maxBurned) {
                // burn
                supplyBalances[tranche] -= assets;
                totalSupply -= assets;
                break;
            } else {
                ITranche(tranche).lock();
                // burn
                supplyBalances[tranche] -= maxBurned;
                totalSupply -= maxBurned;
                _popTranche(i, tranche);
                unchecked {
                    assets -= maxBurned;
                }
            }
        }

        //ToDo Although it should be an impossible state if the protocol functions as it should,
        //What if there is still more liquidity in the pool than totalSupply, start an emergency procedure?

    }

    //todo: Function only for testing purposes, to delete as soon as foundry allows to test internal functions.
    function testProcessDefault(uint256 assets) public onlyOwner {
        _processDefault(assets);
    }

    /* //////////////////////////////////////////////////////////////
                            VAULT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc TrustedProtocol
     */
    function openMarginAccount() external override view returns (bool success, address baseCurrency, address liquidator_) {
        require(IFactory(vaultFactory).isVault(msg.sender), "LP_OMA: Not a vault");
        //Todo: Check if vaultversion etc is ok
        success = true;
        baseCurrency = address(asset);
        liquidator_ = liquidator;
    }

    /**
     * @inheritdoc TrustedProtocol
     */
    function getOpenPosition(address vault) external override returns(uint128 openPosition) {
        //ToDo: When ERC-4626 is correctly implemented, It should not be necessary to first sync interests.
        _syncInterests();
        openPosition = uint128(ERC4626(debtToken).maxWithdraw(vault));
    }

}
