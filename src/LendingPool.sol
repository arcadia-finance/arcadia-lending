/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import {Owned} from "../lib/solmate/src/auth/Owned.sol";
import {Auth} from "../lib/solmate/src/auth/Auth.sol";
import {ERC20, ERC4626} from "../lib/solmate/src/mixins/ERC4626.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./utils/LogExpMath.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ILendingPool.sol";
import {TrustedProtocol} from "./TrustedProtocol.sol";
import {DebtToken} from "./DebtToken.sol";

/**
 * @title Lending Pool
 * @author Arcadia Finance
 * @notice The Lending pool contains the main logic to provide liquidity and take or repay loans for a certain asset
 */
contract LendingPool is Owned, TrustedProtocol, DebtToken {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant YEARLY_BLOCKS = 2628000;

    uint64 public interestRate; //18 decimals precision
    uint32 public lastSyncedBlock;
    uint256 public totalWeight;
    uint256 public totalRealisedLiquidity;
    uint256 public feeWeight;

    address public treasury;
    address public liquidator;
    address public vaultFactory;

    uint256[] public weights;
    address[] public tranches;

    mapping(address => bool) public isTranche;
    mapping(address => uint256) public weight;
    mapping(address => uint256) public realisedLiquidityOf;
    mapping(address => mapping(address => uint256)) public creditAllowance;

    event CreditApproval(address indexed vault, address indexed beneficiary, uint256 amount);

    modifier onlyLiquidator() {
        require(liquidator == msg.sender, "UNAUTHORIZED");
        _;
    }

    modifier onlyTranche() {
        require(isTranche[msg.sender], "UNAUTHORIZED");
        _;
    }

    /**
     * @notice The constructor for a lending pool
     * @param _asset The underlying ERC-20 token of the Lending Pool
     * @param _treasury The address of the protocol treasury
     * @param _vaultFactory The address of the vault factory
     * @dev The name and symbol of the pool are automatically generated, based on the name and symbol of the underlying token
     */
    constructor(ERC20 _asset, address _treasury, address _vaultFactory)
        Owned(msg.sender)
        TrustedProtocol()
        DebtToken(_asset)
    {
        treasury = _treasury;
        vaultFactory = _vaultFactory;
    }

    /* //////////////////////////////////////////////////////////////
                            TRANCHES LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds a tranche to the Lending Pool
     * @param tranche The address of the Tranche
     * @param _weight The weight of the specific Tranche
     * @dev The order of the tranches is important, the most senior tranche is at index 0, the most junior at the last index.
     * @dev Each Tranche is an ERC-4626 contract
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev ToDo: For now manually add newly created tranche, do via factory in future?
     */
    function addTranche(address tranche, uint256 _weight) public onlyOwner {
        require(!isTranche[tranche], "TR_AD: Already exists");
        totalWeight += _weight;
        weights.push(_weight);
        weight[tranche] = _weight;
        tranches.push(tranche);
        isTranche[tranche] = true;
    }

    /**
     * @notice Changes the weight of a specific tranche
     * @param index The index of the Tranche for which a new weight is being set
     * @param _weight The new weight of the Tranche at the index
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev ToDo: TBD of we want the weight to be changeable?
     */
    function setWeight(uint256 index, uint256 _weight) public onlyOwner {
        require(index < tranches.length, "TR_SW: Inexisting Tranche");
        totalWeight = totalWeight - weights[index] + _weight;
        weights[index] = _weight;
        weight[tranches[index]] = _weight;
    }

    /**
     * @notice Removes the tranche at the last index (most junior)
     * @param index The index of the last Tranche
     * @param tranche The address of the last Tranche
     * @dev This function is only be called by the function _processDefault(uint256 assets), when there is a default as big (or bigger)
     * as the complete principal of the most junior tranche
     * @dev Passing the input parameters to the function saves gas compared to reading the address and index of the last tranche from memory.
     * No need to be check if index and tranche are indeed of the last tranche since function is only called by _processDefault.
     */
    function _popTranche(uint256 index, address tranche) internal {
        totalWeight -= weights[index];
        isTranche[tranche] = false;
        weights.pop();
        tranches.pop();
    }

    /* ///////////////////////////////////////////////////////////////
                    PROTOCOL FEE CONFIGURATION
    ////////////////////////////////////////////////////////////// */

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
     * (this is always msg.sender, a tranche), the second parameter is 'from':
     * (the origin of the underlying ERC-20 token, who deposits assets via a Tranche)
     */
    function depositInLendingPool(uint256 assets, address from) public onlyTranche {
        _syncInterests();

        asset.transferFrom(from, address(this), assets);

        unchecked {
            realisedLiquidityOf[msg.sender] += assets;
            totalRealisedLiquidity += assets;
        }

        _updateInterestRate();
    }

    /**
     * @notice Withdraw assets from the Lending Pool
     * @param assets the amount of assets of the underlying ERC-20 token being withdrawn
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     */
    function withdrawFromLendingPool(uint256 assets, address receiver) public {
        _syncInterests();

        require(realisedLiquidityOf[msg.sender] >= assets, "LP_WFLP: Amount exceeds balance");

        realisedLiquidityOf[msg.sender] -= assets;
        totalRealisedLiquidity -= assets;

        asset.safeTransfer(receiver, assets);

        _updateInterestRate();
    }

    /* //////////////////////////////////////////////////////////////
                            LENDING LOGIC
    ////////////////////////////////////////////////////////////// */

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
        require(IFactory(vaultFactory).isVault(vault), "LP_B: Not a vault");

        //Check allowances to send underlying to to
        if (IVault(vault).owner() != msg.sender) {
            uint256 allowed = creditAllowance[vault][msg.sender];
            if (allowed != type(uint256).max) {
                creditAllowance[vault][msg.sender] = allowed - amount;
            }
        }

        //Call vault to check if there is sufficient collateral
        require(IVault(vault).increaseMarginPosition(address(asset), amount), "LP_B: Reverted");

        //Process interests since last update
        _syncInterests();

        //Transfer fails if there is insufficient liquidity in pool
        asset.safeTransfer(to, amount);

        if (amount != 0) {
            _deposit(amount, vault);
        }

        //Update interest rates
        _updateInterestRate();
    }

    /**
     * @notice repays a loan
     * @param amount The amount of underlying ERC-20 tokens to be repaid
     * @param vault The address of the Arcadia Vault backing the loan
     * @dev ToDo: should it be possible to trigger a repay on behalf of an other account,
     * If so, work with allowances
     */
    function repay(uint256 amount, address vault) public {
        require(IFactory(vaultFactory).isVault(vault), "LP_R: Not a vault");

        //Process interests since last update
        _syncInterests();

        uint256 vaultDebt = maxWithdraw(vault);
        uint256 transferAmount = vaultDebt > amount ? amount : vaultDebt;

        asset.transferFrom(msg.sender, address(this), transferAmount);

        _withdraw(transferAmount, vault, vault);

        //Call vault to unlock collateral
        require(IVault(vault).decreaseMarginPosition(address(asset), transferAmount), "LP_R: Reverted");

        //Update interest rates
        _updateInterestRate();
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of outstanding debt in the underlying asset
     * @return totalDebt The total debt in underlying assets
     */
    function totalAssets() public view override returns (uint256 totalDebt) {
        // Avoid a second calculation of unrealised debt (expensive)
        // if interersts are already synced this block.
        if (lastSyncedBlock != uint32(block.number)) {
            totalDebt = realisedDebt + calcUnrealisedDebt();
        } else {
            totalDebt = realisedDebt;
        }
    }

    /**
     * @notice Returns the redeemable amount of liquidity in the underlying asset of an address
     * @param _of The address of the liquidity provider
     * @dev For this implementation, _of is or an address of a tranche, or an address of a treasury
     * @return liquidityOf_ The redeemable amount of liquidity
     */
    function liquidityOf(address _of) public view returns (uint256 liquidityOf_) {
        // Avoid a second calculation of unrealised debt (expensive)
        // if interersts are already synced this block.
        if (lastSyncedBlock != uint32(block.number)) {
            // The total liquidity of a tranche equals the sum of the realised liquidity
            // of the tranche, and its pending interests
            uint256 interest = calcUnrealisedDebt().mulDivUp(weight[_of], totalWeight);
            liquidityOf_ = realisedLiquidityOf[_of] + interest;
        } else {
            liquidityOf_ = realisedLiquidityOf[_of];
        }
    }

    /* //////////////////////////////////////////////////////////////
                            INTERESTS LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Syncs all unrealised debt (= interest for LP and treasury).
     * @dev Calculates the unrealised debt since last sync, and realises it by minting an aqual amount of
     * debt tokens to all debt holders and interests to LPs and the treasury
     */
    function syncInterests() external {
        _syncInterests();
    }

    /**
     * @notice Syncs all unrealised debt (= interest for LP and treasury).
     * @dev Calculates the unrealised debt since last sync, and realises it by minting an aqual amount of
     * debt tokens to all debt holders and interests to LPs and the treasury
     */
    function _syncInterests() internal {
        // Only Sync interests once per block
        if (lastSyncedBlock != uint32(block.number)) {
            uint256 unrealisedDebt = calcUnrealisedDebt();
            lastSyncedBlock = uint32(block.number);

            //Sync interests for borrowers
            unchecked {
                realisedDebt += unrealisedDebt;
            }

            //Sync interests for LPs and Protocol Treasury
            _syncInterestsToLiquidityProviders(unrealisedDebt);
        }
    }

    /**
     * @notice Calculates the unrealised debt.
     * @dev To Find the unrealised debt over an amount of time, you need to calculate D[(1+r)^x-1].
     * The base of the exponential: 1 + r, is a 18 decimals fixed point number
     * with r the yearly interest rate.
     * The exponent of the exponential: x, is a 18 decimals fixed point number.
     * The exponent x is calculated as: the amount of blocks since last sync divided by the average of
     * blocks produced over a year (using a 12s average block time).
     * _yearlyInterestRate = 1 + r expressed as 18 decimals fixed point number
     */
    function calcUnrealisedDebt() public view returns (uint256 unrealisedDebt) {
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
            unrealisedDebt = (realisedDebt * (LogExpMath.pow(base, exponent) - 1e18)) / 1e18;
        }
    }

    /**
     * @notice Syncs interest payments to the Lending providers and the treasury.
     * @param assets The total amount of underlying assets to be paid out as interests.
     * @dev The weight of each Tranche determines the relative share yield (interest payments) that goes to its Liquidity providers
     * @dev The Shares for each Tranche are rounded up, if the treasury receives the remaining shares and will hence loose
     * part of their yield due to rounding errors (neglectable small).
     */
    function _syncInterestsToLiquidityProviders(uint256 assets) internal {
        uint256 remainingAssets = assets;

        uint256 trancheShare;
        for (uint256 i; i < tranches.length;) {
            trancheShare = assets.mulDivUp(weights[i], totalWeight);
            unchecked {
                realisedLiquidityOf[tranches[i]] += trancheShare;
                remainingAssets -= trancheShare;
                ++i;
            }
        }
        unchecked {
            totalRealisedLiquidity += assets;

            // Add the remainingAssets to the treasury balance
            realisedLiquidityOf[treasury] += remainingAssets;
        }
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
     * as such interests are not accrued during the liquidation.
     * @dev After the liquidation is finished, there are two options:
     * 1) the collateral is auctioned for more than the debt position
     * and liquidator reward In this case the liquidator will transfer an equal amount
     * as the debt position to the Lending Pool.
     * 2) the collateral is auctioned for less than the debt position
     * and keeper fee -> the vault became under-collateralised and we have a default event.
     * In this case the liquidator will call settleLiquidation() to settle the deficit.
     * the Liquidator will transfer any remaining funds to the Lending Pool.
     */
    function liquidateVault(address vault, uint256 debt) public onlyLiquidator {
        _withdraw(debt, vault, vault);
    }

    /**
     * @notice Settles bad debt of liquidations.
     * @param default_ The amount of debt.that was not recouped by the auction
     * @param deficit The amount of debt that has to be repaid to the liquidator,
     * if the liquidation fee was bigger than the auction proceeds
     * @dev This function is called by the Liquidator after a liquidation is finished,
     * but only if there is bad debt.
     * @dev The liquidator will transfer the auction proceeds (the underlying asset)
     * Directly back to the liquidity pool after liquidation.
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
     * the complete tranche is locked and removed. If there is still remaining bad debt, the next Tranche starts losing capital.
     */
    function _processDefault(uint256 assets) internal {
        if (totalRealisedLiquidity < assets) {
            //Should never be possible, this means the total protocol has more debt than claimable liquidity.
            assets = totalRealisedLiquidity;
        }

        address tranche;
        uint256 maxBurned;
        for (uint256 i = tranches.length; i > 0;) {
            unchecked {
                --i;
            }
            tranche = tranches[i];
            maxBurned = realisedLiquidityOf[tranche];
            if (assets < maxBurned) {
                // burn
                realisedLiquidityOf[tranche] -= assets;
                totalRealisedLiquidity -= assets;
                break;
            } else {
                ITranche(tranche).lock();
                // burn
                realisedLiquidityOf[tranche] -= maxBurned;
                totalRealisedLiquidity -= maxBurned;
                _popTranche(i, tranche);
                unchecked {
                    assets -= maxBurned;
                }
            }
        }

        //ToDo Although it should be an impossible state if the protocol functions as it should,
        //What if there is still more liquidity in the pool than totalRealisedLiquidity, start an emergency procedure?
    }

    /* //////////////////////////////////////////////////////////////
                            VAULT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc TrustedProtocol
     */
    function openMarginAccount()
        external
        view
        override
        returns (bool success, address baseCurrency, address liquidator_)
    {
        require(IFactory(vaultFactory).isVault(msg.sender), "LP_OMA: Not a vault");
        //Todo: Check if vaultversion etc is ok
        success = true;
        baseCurrency = address(asset);
        liquidator_ = liquidator;
    }

    /**
     * @inheritdoc TrustedProtocol
     */
    function getOpenPosition(address vault) external override returns (uint128 openPosition) {
        //ToDo: When ERC-4626 is correctly implemented, It should not be necessary to first sync interests.
        _syncInterests();
        openPosition = uint128(maxWithdraw(vault));
    }
}
