// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import { IEVC } from "evc-playground/vaults/VaultBase.sol";
import { RepoBaseVault } from "./RepoBaseVault.sol";
import { IStandardizedYield } from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import { IPYieldToken } from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { IPMarketV3 } from "@pendle/core/contracts/interfaces/IPMarketV3.sol";
import { PYIndexLib } from "@pendle/core/contracts/core/StandardizedYield/PYIndex.sol";
import { PtUsdOracle } from "./PtUsdOracle.sol";
import { PendlePtOracleLib } from "@pendle/core/contracts/oracles/PendleLpOracleLib.sol";
import { IFixedYieldCollateralVault } from "./interfaces/IFixedYieldCollateralVault.sol";
import { IERC20, ERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MarketApproxPtOutLib, ApproxParams } from "@pendle/core/contracts/router/base/MarketApproxLib.sol";

error REPO__CollateralExpired();
error REPO__ZeroAmount();
error REPO__InvalidTerm();
error REPO__WrongToken();
error REPO__MaxLoanExceeded();
error REPO__RepayFailed();
error REPO__LiquidationImpaired();
error REPO__SlippageToHigh();
error REPO__LoanTermNotExpired();
error InvalidCollateralFactor();
error REPO__NotEnoughCollateralPledged();
error ViolatorStatusCheckDeferred();
error ControllerDisabled();

/// @title RepoVaultBorrowable 
/// @notice implements the vault containing borrowable assets for the REPO protocol.
/// @author yielddev
contract RepoVaultBorrowable is RepoBaseVault {
    using Math for uint256;
    using MarketApproxPtOutLib for *;
    using PendlePtOracleLib for IPMarketV3;
    using PYIndexLib for IPYieldToken;
    mapping(address => uint256) private _owed;
    mapping(address => mapping(uint256 => Repo)) public repos;
    mapping(address => uint256) public loans;
    mapping(address => uint256) public pledgedCollateral;
    // mapping(address => uint256) public collateralFactor;

    uint256 internal _totalBorrowed;
    uint256 internal _totalPledgedCollateral;
    uint256 private COLLATERAL_FACTOR_SCALE = 1_000_000;
    uint256 private RATE_PERCISION = 1_000_000; // 0.01 of a basis point
    uint256 public LTV = 990_000; // 99% LTV
    uint256 private MARKET_EPS = 10**15; //0,1%

    PtUsdOracle public oracle;
    IPPrincipalToken public collateral;
    IFixedYieldCollateralVault public collateralVault;
    address public market;

    bytes internal constant EMPTY_BYTES = abi.encode();

    event Borrow(address indexed borrower, address indexed receiver, uint256 assets);
    event Repay(address indexed borrower, address indexed receiver, uint256 assets);
    struct Repo {
        uint256 collateralAmount;
        uint256 repurchasePrice;
        uint256 termExpires;
    }

    constructor(
        IEVC _evc,
        IERC20 _asset,
        address _collateralVault,
        address _collateralAsset,
        address _oracle,
        address _market
    ) RepoBaseVault(
            _evc,
            _asset,
            "REPO BORROW",
            "REPOB"
        ) {
        collateralVault = IFixedYieldCollateralVault(_collateralVault);
        collateral = IPPrincipalToken(_collateralAsset);
        oracle = PtUsdOracle(_oracle);
        market = _market;
    }

    function getRepoLoan(address account, uint256 loandIndex) external view returns (uint256 collateral, uint256 repurchasePrice, uint256 term) {
        Repo memory repo = repos[account][loandIndex];
        return (repo.collateralAmount, repo.repurchasePrice, repo.termExpires);
    }
    function borrow(uint256 assets, uint256 term, address receiver) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        if (assets == 0) revert REPO__ZeroAmount();
        if (term < 1 days) revert REPO__InvalidTerm();

        receiver = _getAccountOwner(receiver);

        uint256 loanAmount = assets + getTermFeeForAmount(assets, term);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        uint256 collateralValueRequired = loanAmount * RATE_PERCISION / LTV;
        uint256 collateralNominalRequired = collateralValueRequired * 1 ether / (oracle.getPtPrice());
        writeRepoLoan(msgSender, collateralNominalRequired, loanAmount, term);
        emit Borrow(msgSender, receiver, loanAmount);
        _totalAssets -= assets;
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function renewRepoLoan(
        address _borrower,
        uint256 _loanIndex,
        uint256 _partialPayoff,
        uint256 _newTerm
    ) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();
        createVaultSnapshot();
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        if (_newTerm < 1 days) revert REPO__InvalidTerm();

        Repo memory repo = repos[_borrower][_loanIndex];
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), _partialPayoff);
        _totalAssets += _partialPayoff; // cancel out utilization before calculating new loan
        uint256 termFee = getTermFeeForAmount(repo.repurchasePrice-_partialPayoff, _newTerm);
        uint256 newRepurchasePrice = (repo.repurchasePrice - _partialPayoff) + termFee;
        // previous loan is paid off
        loans[_borrower] -= 1;
        pledgedCollateral[_borrower] -= repo.collateralAmount;
        _decreaseOwed(_borrower, repo.repurchasePrice);
        // new loan is written
        writeRepoLoan(_borrower, repo.collateralAmount, newRepurchasePrice, _newTerm);
        requireAccountAndVaultStatusCheck(msgSender);

    }

    function openTradeBaseForPT(
        uint256 _PTAmount,
        uint256 _term,
        uint256 _minPtOut,
        address receiver
    ) public callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        // sanity check: the violator must be under control of the EVC
        if (!isControllerEnabled(receiver, address(this))) revert ControllerDisabled();
        createVaultSnapshot();

        if (_term < 1 days) revert REPO__InvalidTerm();
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        receiver = _getAccountOwner(receiver);

        uint256 markPrice = oracle.getPtPrice();
        uint256 ptMarketValue = markPrice * _PTAmount / 1 ether; 

        uint256 netPtOut = swapExactTokenForPt(
            ptMarketValue, _PTAmount, _minPtOut, asset()
        );

        // the maximum loan value for the collateral purchased
        uint256 maxLoan = maxLoanValue(netPtOut*markPrice / 1 ether);
        // the Maximum borrowable against the collateral for the term (haircut)
        uint256 borrowAmount = getMaxBorrow(netPtOut*markPrice / 1 ether, _term); 

        // write a repurchase agreement for maxLoan at term against netPtOut
        writeRepoLoan(msgSender, netPtOut, maxLoan, _term);
        // User must the transactions total minus the total amount they were able to borrow against the collateral 
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), ptMarketValue-borrowAmount);

        // move collateral into vault on behalf of the user
        IERC20(collateral).approve(address(collateralVault), netPtOut);
        collateralVault.deposit(netPtOut, receiver);

        // assets in the pool reduced by borrowAmount
        _totalAssets -= borrowAmount;

        // do account checks
        requireAccountAndVaultStatusCheck(msgSender);

    }

    function repurchaseAndSellPt(
        address borrower,
        address receiver,
        uint256 _loanIndex
    ) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();

        createVaultSnapshot();

        receiver = _getAccountOwner(receiver);
        Repo memory repo = repos[borrower][_loanIndex];
        liquidateCollateralShares(address(collateralVault), borrower, address(this), repo.collateralAmount);
        forgiveAccountStatusCheck(borrower);
        collateralVault.withdraw(repo.collateralAmount, address(this), address(this));
        uint256 sale_amount = _sellPtForToken(repo.collateralAmount, address(asset()));
        if (sale_amount > repo.repurchasePrice) {
            uint256 profit = sale_amount - repo.repurchasePrice;
            if (profit > 0) {
                SafeERC20.safeTransfer(IERC20(asset()), receiver, profit);
            }

            _decreaseOwed(borrower, repo.repurchasePrice);
            _totalAssets += repo.repurchasePrice;

            pledgedCollateral[borrower] -= repo.collateralAmount;
            _totalPledgedCollateral -= repo.collateralAmount;
            loans[borrower] -= 1;
            delete repos[borrower][_loanIndex];
        } else {
            revert REPO__LiquidationImpaired();
        }
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function swapExactTokenForPt(
        uint256 netTokenIn,
        uint256 _PtAmount,
        uint256 _minPtOut,
        address tokenIn
    ) internal returns (uint256 netPtOut){
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();
        
        IERC20(asset()).approve(address(SY), netTokenIn);
        uint256 netSyOut = SY.deposit(address(this), tokenIn, netTokenIn, 1);
        SY.approve(address(market), netSyOut);
        (netPtOut, ) = _swapExactSyForPt(address(this), netSyOut, _PtAmount, _minPtOut);
    }

    function _swapExactSyForPt(
        address receiver,
        uint256 netSyIn,
        uint256 _PtAmount,
        uint256 _minPtOut
    ) internal returns (uint256 netPtOut, uint256 netSyFee) {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();
        (netPtOut, netSyFee) = IPMarketV3(market).readState(address(this)).approxSwapExactSyForPt(
            YT.newIndex(),
            netSyIn,
            block.timestamp,
            ApproxParams({
                guessMin: _minPtOut,
                guessMax: _PtAmount,
                guessOffchain: 0,
                maxIteration: 10,
                eps: MARKET_EPS // 10**15 within 0.1%
            })
        );
        if (netPtOut < _minPtOut) revert REPO__SlippageToHigh();
        SafeERC20.safeTransfer(IERC20(SY), address(market), netSyIn);
        IPMarketV3(market).swapSyForExactPt(address(this), netPtOut, EMPTY_BYTES);
    }

    function repurchase(address receiver, uint256 _loanIndex) external callThroughEVC nonReentrant {
        address msgSender = _msgSenderForBorrow();
        if (!isControllerEnabled(receiver, address(this))) {
            revert ControllerDisabled();
        }
        Repo memory repo = repos[receiver][_loanIndex];
        createVaultSnapshot();
        SafeERC20.safeTransferFrom(IERC20(asset()), msgSender, address(this), repo.repurchasePrice);

        _totalAssets += repo.repurchasePrice;
        _totalPledgedCollateral -= repo.collateralAmount;
        pledgedCollateral[receiver] -= repo.collateralAmount;
        _decreaseOwed(receiver, repo.repurchasePrice);
        delete repos[receiver][_loanIndex];
        loans[receiver] -= 1;
        emit Repay(msgSender, receiver, repo.repurchasePrice);
        requireAccountAndVaultStatusCheck(msgSender);
    }

    function _sellPtForToken(uint256 netPtIn, address tokenOut) internal returns (uint256 netTokenOut) {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();

        uint256 netSyOut;
        uint256 fee;
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            // safeTransfer not required
            PT.transfer(address(market), netPtIn);
            (netSyOut, fee) = IPMarketV3(market).swapExactPtForSy(
                address(SY), // better gas optimization to transfer SY directly to itself and burn
                netPtIn,
                EMPTY_BYTES
            );
        }

        netTokenOut = SY.redeem(address(this), netSyOut, tokenOut, 1, true); // true burns from the SYcontract balance

    }

    /// =====================
    /// @notice allows collateral from expired repurchase agreements to be liquidated
    /// @param _borrower The address of the borrower for whom the collateral is to be liquidated
    function liquidate(address _borrower, uint256 _loanIndex) external callThroughEVC nonReentrant{
        address msgSender = _msgSenderForBorrow();
        // if (collateral.isExpired()) revert REPO__CollateralExpired();
        Repo memory repo = repos[_borrower][_loanIndex];
        if (repo.termExpires > block.timestamp) revert REPO__LoanTermNotExpired();
        // due to later violator's account check forgiveness,
        // the violator's account must be fully settled when liquidating
        if (isAccountStatusCheckDeferred(_borrower)) {
            revert ViolatorStatusCheckDeferred();
        }
        // sanity check: the violator must be under control of the EVC
        if (!isControllerEnabled(_borrower, address(this))) {
            revert ControllerDisabled();
        }

        createVaultSnapshot();

        // liquidator pays off the debt
        SafeERC20.safeTransferFrom(ERC20(asset()), msgSender, address(this), repo.repurchasePrice);

        // PT collateral shares transfered to the liquidator
        liquidateCollateralShares(address(collateralVault), _borrower, msgSender, repo.collateralAmount);
        forgiveAccountStatusCheck(_borrower);

        _totalPledgedCollateral -= repo.collateralAmount;
        _totalAssets += repo.repurchasePrice; 
        pledgedCollateral[_borrower] -= repo.collateralAmount;
        _decreaseOwed(_borrower, repo.repurchasePrice);
        loans[_borrower] -= 1;

        delete repos[_borrower][_loanIndex];
        requireAccountAndVaultStatusCheck(msgSender);
    }
    /// @notice returns the current rate for borrowing
    function getRate(uint256 _amountBorrowed, uint256 totalAssets, uint256 totalBorrowed) view public returns(uint256) {
        if (totalAssets == 0) return 677; // 6.77 basis points (0.0677%
        uint256 utilization1 = totalBorrowed * 1 ether / totalAssets+totalBorrowed;
        uint256 utilization2 = (_amountBorrowed + totalBorrowed) * 1 ether / (totalAssets + totalBorrowed);
        if (utilization2 < 0.8 ether) {
            return ( ( (20*utilization1 / 100 ether) + 677 ) + ( (20*utilization2 / 100 ether) + 677 ) )/ 2;
        } else {
            uint256 amount_below = ((0.8 ether * (totalAssets + totalBorrowed)) - totalBorrowed) / 1 ether;
            uint256 amount_above = _amountBorrowed - amount_below;
            uint256 rate_below = (20*utilization1 / 100 ether) + 677;
            uint256 rate_above = (200*utilization2 / 100 ether) + 677;
            return (rate_below * amount_below + rate_above * amount_above) / _amountBorrowed;
        }
    }

    function getTermFeeForAmount(uint256 _amount, uint256 _term) view public returns(uint256) {
        return _amount * ((getRate(_amount, _totalAssets, _totalBorrowed)*_term)) / (RATE_PERCISION * 1 days);
    }
    function maxLoanValue(uint256 _collateralValue) view public returns(uint256) {
        return _collateralValue * LTV / RATE_PERCISION;
    }

    /// @notice returns the maximum amount that can be borrowed for a given amount of collateral 
    function getMaxBorrow(uint256 _collateralValue, uint256 _term) view public returns(uint256) {
        return maxLoanValue(_collateralValue) * ((1 days * RATE_PERCISION) -  (getRate(maxLoanValue(_collateralValue), _totalAssets, _totalBorrowed)*_term)) / (RATE_PERCISION * 1 days);
    }

    function getTermFee(uint256 _collateralValue, uint256 _term) view public returns(uint256) {
        return maxLoanValue(_collateralValue) - getMaxBorrow(_collateralValue, _term);
    }

    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        return abi.encode(_totalAssets, _totalBorrowed, _totalPledgedCollateral);
    }   

    function writeRepoLoan(
        address debtor,
        uint256 collateralPledged,
        uint256 loanAmount,
        uint256 term
    ) internal {
        _increaseOwed(debtor, loanAmount);
        pledgedCollateral[debtor] += collateralPledged;
        loans[debtor] += 1;
        repos[debtor][loans[debtor]] = Repo(collateralPledged, loanAmount, block.timestamp + term);
        _totalPledgedCollateral += collateralPledged;
    }

    function doCheckVaultStatus(bytes memory oldSnapshot) internal virtual override {
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        (uint256 initialAssets, uint256 initialBorrowed, uint256 initialPledged) = abi.decode(oldSnapshot, (uint256, uint256, uint256));
        uint256 finalAsset = _totalAssets;
        uint256 finalBorrowed = _totalBorrowed;
        uint256 finalPledged = _totalPledgedCollateral;
        if (_totalBorrowed > _totalPledgedCollateral) revert REPO__NotEnoughCollateralPledged(); // vault must eventually settle to 1

    }
    
    function setEPS(uint256 _eps) external onlyOwner {
        MARKET_EPS = _eps;
    }

    function doCheckAccountStatus(address account, address[] calldata collaterals) internal view virtual override {

       uint256 collateral = IERC20(collateralVault).balanceOf(account);
       uint256 maxLoan = maxLoanValue(collateral*oracle.getPtPrice() / 1 ether);

       if (maxLoan < _owed[account]) revert REPO__MaxLoanExceeded();
       if (collateral < pledgedCollateral[account]) revert REPO__LiquidationImpaired();
       // account ok
    }

    function _decreaseOwed(address account, uint256 assets) internal virtual {
        _owed[account] = _debtOf(account) - assets;
        _totalBorrowed -= assets;
    } 
    function _increaseOwed(address account, uint256 assets) internal virtual {
        _owed[account] = _debtOf(account) + assets;
        _totalBorrowed += assets;
    }
    function _debtOf(address account) internal view virtual returns (uint256) {
        return _owed[account];
    }

    // ===========================
    /// @notice Converts assets to shares.
    /// @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
    /// rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
    /// @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
    /// @param assets The assets to convert.
    /// @return The converted shares.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 underlyingValue = totalAssets() + _totalBorrowed;
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), underlyingValue + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 underlyingValue = totalAssets() + _totalBorrowed;
        return shares.mulDiv(underlyingValue+ 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }
    /// @notice Deposits a certain amount of assets for a receiver.
    /// @param assets The assets to deposit.
    /// @param receiver The receiver of the deposit.
    /// @return shares The shares equivalent to the deposited assets.
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override callThroughEVC nonReentrant returns (uint256 shares) {
        createVaultSnapshot();
        shares = super.deposit(assets, receiver);
        _totalAssets += assets;
        requireVaultStatusCheck();

    }

    /// @notice Mints a certain amount of shares for a receiver.
    /// @param shares The shares to mint.
    /// @param receiver The receiver of the mint.
    /// @return assets The assets equivalent to the minted shares.
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override callThroughEVC nonReentrant returns (uint256 assets) {
        createVaultSnapshot();
        assets = super.mint(shares, receiver);
        _totalAssets += assets;
        requireVaultStatusCheck();
    }

    /// @notice Withdraws a certain amount of assets for a receiver.
    /// @param assets The assets to withdraw.
    /// @param receiver The receiver of the withdrawal.
    /// @param owner The owner of the assets.
    /// @return shares The shares equivalent to the withdrawn assets.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override callThroughEVC nonReentrant returns (uint256 shares) {
        createVaultSnapshot();
        shares = super.withdraw(assets, receiver, owner);
        _totalAssets -= assets;
        requireAccountAndVaultStatusCheck(owner);
    }

    /// @notice Redeems a certain amount of shares for a receiver.
    /// @param shares The shares to redeem.
    /// @param receiver The receiver of the redemption.
    /// @param owner The owner of the shares.
    /// @return assets The assets equivalent to the redeemed shares.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override callThroughEVC nonReentrant returns (uint256 assets) {
        createVaultSnapshot();
        assets = super.redeem(shares, receiver, owner);
        _totalAssets -= assets;
        requireAccountAndVaultStatusCheck(owner);
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (_convertToAssets(balanceOf(owner), Math.Rounding.Floor) > totalAssets()) {
            return totalAssets();
        } else {
            return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        }
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        if (_convertToAssets(balanceOf(owner), Math.Rounding.Floor) > totalAssets()) {
            return _convertToShares(totalAssets(), Math.Rounding.Floor);
        } else {
            return balanceOf(owner);
        }
    }
}
