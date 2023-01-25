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
import {TrustedCreditor} from "./TrustedCreditor.sol";
import {DebtToken} from "./DebtToken.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {InterestRateModule} from "./InterestRateModule.sol";
import {Guardian} from "./security/Guardian.sol";

/**
 * @title Lending Pool
 * @author Arcadia Finance
 * @notice The Lending pool contains the main logic to provide liquidity and take or repay loans for a certain asset
 */
contract LendingPool is Guardian, TrustedCreditor, DebtToken, InterestRateModule {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // @dev based on 365 days * 24 hours * 60 minutes * 60 seconds, leap years ignored
    uint256 public constant YEARLY_SECONDS = 31_536_000;

    uint32 public lastSyncedTimestamp;
    uint8 public originationFee; //4 decimals precision (10 equals 0.001 or 0.1%)
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
    event Borrow(address indexed vault, bytes3 indexed referrer, uint256 amount);

    modifier onlyLiquidator() {
        require(liquidator == msg.sender, "UNAUTHORIZED");
        _;
    }

    modifier onlyTranche() {
        require(isTranche[msg.sender], "UNAUTHORIZED");
        _;
    }

    modifier processInterests() {
        _syncInterests();
        _;
        //_updateInterestRate() modifies the state (effect), but can safely be called after interactions
        //Cannot be exploited by re-entrancy attack
        _updateInterestRate(realisedDebt, totalRealisedLiquidity);
    }

    /**
     * @notice The constructor for a lending pool
     * @param asset_ The underlying ERC-20 token of the Lending Pool
     * @param treasury_ The address of the protocol treasury
     * @param vaultFactory_ The address of the vault factory
     * @dev The name and symbol of the pool are automatically generated, based on the name and symbol of the underlying token
     */
    constructor(ERC20 asset_, address treasury_, address vaultFactory_)
        Guardian()
        TrustedCreditor()
        DebtToken(asset_)
    {
        treasury = treasury_;
        vaultFactory = vaultFactory_;
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
     * @dev Setting feeWeight to a very high value will cause the protocol to collect all interest fees from that moment on.
     * Although this will affect the future profits of liquidity providers, no funds nor realized interest is at risk for LPs.
     */
    function setFeeWeight(uint256 _feeWeight) external onlyOwner {
        totalWeight = totalWeight - feeWeight + _feeWeight;
        feeWeight = _feeWeight;
    }

    /**
     * @notice Sets new treasury address
     * @param treasury_ The new address of the treasury
     */
    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
    }

    /**
     * @notice Sets the new origination fee
     * @param originationFee_ The new origination fee
     */
    function setOriginationFee(uint8 originationFee_) external onlyOwner {
        originationFee = uint8(originationFee_);
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
    function depositInLendingPool(uint256 assets, address from)
        public
        whenDepositNotPaused
        onlyTranche
        processInterests
    {
        // Need to transfer before minting or ERC777s could reenter.
        // Address(this) is trusted -> no risk on re-entrancy attack after transfer
        asset.transferFrom(from, address(this), assets);

        unchecked {
            realisedLiquidityOf[msg.sender] += assets;
            totalRealisedLiquidity += assets;
        }
    }

    /**
     * @notice Withdraw assets from the Lending Pool
     * @param assets the amount of assets of the underlying ERC-20 token being withdrawn
     * @param receiver The address of the receiver of the underlying ERC-20 tokens
     */
    function withdrawFromLendingPool(uint256 assets, address receiver) public whenWithdrawNotPaused processInterests {
        require(realisedLiquidityOf[msg.sender] >= assets, "LP_WFLP: Amount exceeds balance");

        realisedLiquidityOf[msg.sender] -= assets;
        totalRealisedLiquidity -= assets;

        asset.safeTransfer(receiver, assets);
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
     * @notice Takes out a loan backed by collateral in an Arcadia Vault
     * @param amount The amount of underlying ERC-20 tokens to be lent out
     * @param vault The address of the Arcadia Vault backing the loan
     * @param to The address who receives the lended out underlying tokens
     * @dev The sender might be different as the owner if they have the proper allowances
     */
    function borrow(uint256 amount, address vault, address to, bytes3 referrer)
        public
        whenBorrowNotPaused
        processInterests
    {
        require(IFactory(vaultFactory).isVault(vault), "LP_B: Not a vault");

        uint256 amountWithFee = amount + (amount * originationFee) / 10_000;

        //Check allowances to take debt
        if (IVault(vault).owner() != msg.sender) {
            uint256 allowed = creditAllowance[vault][msg.sender];
            if (allowed != type(uint256).max) {
                creditAllowance[vault][msg.sender] = allowed - amountWithFee;
            }
        }

        //Call vault to check if there is sufficient collateral.
        //If so calculate and store the liquidation threshold.
        require(IVault(vault).increaseMarginPosition(address(asset), amountWithFee), "LP_B: Reverted");

        //Mint debt tokens to the vault
        if (amountWithFee != 0) {
            _deposit(amountWithFee, vault);

            //Transfer fails if there is insufficient liquidity in the pool
            asset.safeTransfer(to, amount);

            realisedLiquidityOf[treasury] += amountWithFee - amount;

            emit Borrow(vault, referrer, amountWithFee);
        }
    }

    /**
     * @notice repays a loan
     * @param amount The amount of underlying ERC-20 tokens to be repaid
     * @param vault The address of the Arcadia Vault backing the loan
     */
    function repay(uint256 amount, address vault) public whenRepayNotPaused processInterests {
        require(IFactory(vaultFactory).isVault(vault), "LP_R: Not a vault");

        uint256 vaultDebt = maxWithdraw(vault);
        uint256 transferAmount = vaultDebt > amount ? amount : vaultDebt;

        // Need to transfer before burning debt or ERC777s could reenter.
        // Address(this) is trusted -> no risk on re-entrancy attack after transfer
        asset.transferFrom(msg.sender, address(this), transferAmount);

        _withdraw(transferAmount, vault, vault);
    }

    /* //////////////////////////////////////////////////////////////
                        LEVERAGED ACTIONS LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Execute and interact with external logic on leverage.
     * @param amountBorrowed The amount of underlying ERC-20 tokens to be lent out
     * @param vault The address of the Arcadia Vault backing the loan
     * @param actionHandler the address of the action handler to call
     * @param actionData a bytes object containing two actionAssetData structs, an address array and a bytes array
     * @dev The sender might be different as the owner if they have the proper allowances.
     * @dev vaultManagementAction() works similar to flash loans, this function optimistically calls external logic and checks for the vault state at the very end.
     */
    function doActionWithLeverage(
        uint256 amountBorrowed,
        address vault,
        address actionHandler,
        bytes calldata actionData,
        bytes3 referrer
    ) public whenBorrowNotPaused processInterests {
        require(IFactory(vaultFactory).isVault(vault), "LP_DAWL: Not a vault");

        uint256 amountBorrowedWithFee = amountBorrowed + (amountBorrowed * originationFee) / 10_000;

        //Check allowances to take debt
        if (IVault(vault).owner() != msg.sender) {
            uint256 allowed = creditAllowance[vault][msg.sender];
            if (allowed != type(uint256).max) {
                creditAllowance[vault][msg.sender] = allowed - amountBorrowedWithFee;
            }
        }

        if (amountBorrowedWithFee != 0) {
            //Mint debt tokens to the vault, debt must be minted Before the actions in the vault are performed.
            _deposit(amountBorrowedWithFee, vault);

            //Send Borrowed funds to the actionHandler
            asset.safeTransfer(actionHandler, amountBorrowed);

            realisedLiquidityOf[treasury] += amountBorrowedWithFee - amountBorrowed;

            emit Borrow(vault, referrer, amountBorrowedWithFee);
        }

        //The actionhandler will use the borrowed funds (optionally with additional assets previously deposited in the Vault)
        //to excecute one or more actions (swap, deposit, mint...).
        //Next the actionhandler will deposit any of the remaining funds or any of the recipient token
        //resulting from the actions back into the vault.
        //As last step, after all assets are deposited back into the vault a final health check is done:
        //The Collateral Value of all assets in the vault is bigger than the total liabilities against the vault (including the margin taken during this function).
        IVault(vault).vaultManagementAction(actionHandler, actionData);
    }

    /* //////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the total amount of outstanding debt in the underlying asset
     * @return totalDebt The total debt in underlying assets
     */
    function totalAssets() public view override returns (uint256 totalDebt) {
        // Avoid a second calculation of unrealised debt (expensive)
        // if interersts are already synced this block.
        if (lastSyncedTimestamp != uint32(block.timestamp)) {
            totalDebt = realisedDebt + calcUnrealisedDebt();
        } else {
            totalDebt = realisedDebt;
        }
    }

    /**
     * @notice Returns the redeemable amount of liquidity in the underlying asset of an address
     * @param owner_ The address of the liquidity provider
     * @dev For this implementation, owner_ is or an address of a tranche, or an address of a treasury
     * @return assets The redeemable amount of liquidity in the underlying asset
     */
    function liquidityOf(address owner_) public view returns (uint256 assets) {
        // Avoid a second calculation of unrealised debt (expensive)
        // if interersts are already synced this block.
        if (lastSyncedTimestamp != uint32(block.timestamp)) {
            // The total liquidity of a tranche equals the sum of the realised liquidity
            // of the tranche, and its pending interests
            uint256 interest = calcUnrealisedDebt().mulDivUp(weight[owner_], totalWeight);
            assets = realisedLiquidityOf[owner_] + interest;
        } else {
            assets = realisedLiquidityOf[owner_];
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
    function _syncInterests() internal {
        // Only Sync interests once per block
        if (lastSyncedTimestamp != uint32(block.timestamp)) {
            uint256 unrealisedDebt = calcUnrealisedDebt();
            lastSyncedTimestamp = uint32(block.timestamp);

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
     * The exponent x is calculated as: the amount of seconds passed since last sync timestamp divided by the average of
     * seconds per year. _yearlyInterestRate = 1 + r expressed as 18 decimals fixed point number
     */
    function calcUnrealisedDebt() public view returns (uint256 unrealisedDebt) {
        uint256 base;
        uint256 exponent;

        unchecked {
            //gas: can't overflow for reasonable interest rates
            base = 1e18 + interestRate;

            //gas: only overflows when (block.timestamp - lastSyncedBlockTimestamp) > 1e59
            //in practice: exponent in LogExpMath lib is limited to 130e18,
            //Corresponding to a delta of timestamps of 4099680000 (or 130 years),
            //much bigger than any realistic time difference between two syncs.
            exponent = ((block.timestamp - lastSyncedTimestamp) * 1e18) / YEARLY_SECONDS;

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
     */
    function _syncInterestsToLiquidityProviders(uint256 assets) internal {
        uint256 remainingAssets = assets;

        uint256 trancheShare;
        for (uint256 i; i < tranches.length;) {
            trancheShare = assets.mulDivDown(weights[i], totalWeight);
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

    /**
     * @notice Set's the configration parameters of InterestRateConfiguration struct
     * @param newConfig New set of configration parameters
     */
    function setInterestConfig(DataTypes.InterestRateConfiguration calldata newConfig) external onlyOwner {
        _setInterestConfig(newConfig);
    }

    /**
     * @notice Updates the interest rate
     */
    function updateInterestRate() external processInterests {}

    /* //////////////////////////////////////////////////////////////
                        LIQUIDATION LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Set's the contract address of the liquidator.
     * @param liquidator_ The contract address of the liquidator
     */
    function setLiquidator(address liquidator_) public onlyOwner {
        liquidator = liquidator_;
    }

    /**
     * @notice Called by a vault when it is being liquidated (auctioned) to repay an amount of debt.
     * @param debt The amount of debt that will be repaid.
     * @dev At the start of the liquidation the debt tokens are burned,
     * as such interests are not accrued during the liquidation.
     * @dev After the liquidation is finished, there are two options:
     * 1) the collateral is auctioned for more than the debt position
     * and liquidationInitiator reward. In this case the liquidator will transfer an equal amount
     * as the debt position to the Lending Pool.
     * 2) the collateral is auctioned for less than the debt position
     * and liquidationInitiator reward fee -> the vault became under-collateralised and we have a default event.
     * In this case the liquidator will call settleLiquidation() to settle the deficit.
     * the Liquidator will transfer any remaining funds to the Lending Pool.
     */
    function liquidateVault(uint256 debt) public override whenLiquidationNotPaused {
        //Function can only be called by Vaults with debt.
        //Only Vaults can have debt, debtTokens are non-transferrable, and only Vaults can call borrow().
        //Since DebtTokens are non-transferrable, only vaults can have debt.
        //Hence by checking that the balance of msg.sender is not 0, we know the sender is
        //indeed a vault and has debt.
        require(balanceOf[msg.sender] != 0, "LP_LV: Not a Vault with debt");

        //Remove debt from Vault (burn DebtTokens)
        _withdraw(debt, msg.sender, msg.sender);
    }

    /**
     * @notice Settles bad debt of liquidations.
     * @param default_ The amount of debt.that was not recouped by the auction
     * @param deficit The amount of debt that has to be repaid to the liquidation initiator,
     * in the edge case that the liquidation fee was bigger than the auction proceeds
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
     * @notice Sets the validity of vault version to valid
     * @param vaultVersion The version current version of the vault
     * @param valid The validity of the respective vaultVersion
     */
    function setVaultVersion(uint256 vaultVersion, bool valid) external onlyOwner {
        _setVaultVersion(vaultVersion, valid);
    }

    /**
     * @inheritdoc TrustedCreditor
     */
    function openMarginAccount(uint256 vaultVersion)
        external
        view
        override
        returns (bool success, address baseCurrency, address liquidator_)
    {
        //ToDo: Remove first check? view function that not interacts with other contracts -> doesn't matter that sender is not a vault
        require(IFactory(vaultFactory).isVault(msg.sender), "LP_OMA: Not a vault");

        if (isValidVersion[vaultVersion]) {
            success = true;
            baseCurrency = address(asset);
            liquidator_ = liquidator;
        }
    }

    /**
     * @inheritdoc TrustedCreditor
     */
    function getOpenPosition(address vault) external view override returns (uint256 openPosition) {
        openPosition = maxWithdraw(vault);
    }
}
