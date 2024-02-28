pragma solidity 0.8.20;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IStandardizedYield } from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import { IPYieldToken } from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { IPMarketV3 } from "@pendle/core/contracts/interfaces/IPMarketV3.sol";
import { PtUsdOracle } from "./PtUsdOracle.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/console.sol";
import { PendlePtOracleLib } from "@pendle/core/contracts/oracles/PendleLpOracleLib.sol";
import { PYIndexLib } from "@pendle/core/contracts/core/StandardizedYield/PYIndex.sol";
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
// ausdc market 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5

/// @title RepoVault
/// @author yielddev
/// @notice This implements a ERC4626 vault that allows for repo loans with PT as collateral
contract RepoVault is ERC4626, IERC3156FlashLender {
    using SafeTransferLib for IERC20;
    using Math for uint256;
    using PendlePtOracleLib for IPMarketV3;
    using PYIndexLib for IPYieldToken;
    using MarketApproxPtOutLib for *;

    IPPrincipalToken public collateral;
    PtUsdOracle public oracle;
    IStandardizedYield public SY;
    IPYieldToken public YT;
    IPMarketV3 public market;

    uint256 private RATE_PERCISION = 1_000_000; // 0.01 of a basis point
    uint256 public LTV = 990_000; // 99% LTV
    uint256 public outstandingValue;
    bytes internal constant EMPTY_BYTES = abi.encode();

    mapping(address => mapping(uint256 => Repo)) public repos;
    mapping(address => uint256) public loans;
    struct Repo {
        uint256 collateralAmount;
        uint256 repurchasePrice;
        uint256 termExpires;
    }

    constructor(
        address _depositToken,
        address _pt,
        address _SY,
        address _market,
        address _oracle
    ) ERC4626(IERC20(_depositToken)) ERC20("RepoVault", "RV"){
        collateral = IPPrincipalToken(_pt);
        SY = IStandardizedYield(_SY);
        YT = IPYieldToken(collateral.YT());
        market = IPMarketV3(_market);
        oracle = PtUsdOracle(_oracle);

    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(asset()) && token != address(collateral)) revert REPO__WrongToken();
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        return amount * 10 / 1_000_000; // 0.1 basis points flashloan fee
    }

    function goLong(
        uint256 _PTamount,
        uint256 _term,
        uint256 _minPtOut
    ) external {
        uint256 ptMarketValue = market.getPtToAssetRate(uint32(1 minutes)) * _PTamount / 1 ether;
        uint256 maxLoan = maxLoanValue(ptMarketValue);
        uint256 borrowAmount = getMaxBorrow(ptMarketValue, _term);
        uint256 balanceBefore_trade = IERC20(asset()).balanceOf(address(this));

        // Transfer initial margin from user
        SafeTransferLib.safeTransferFrom(asset(), msg.sender, address(this), ptMarketValue - borrowAmount);

        IERC20(asset()).approve(address(SY), ptMarketValue);
        uint256 netPtOut = swapExactTokenForPt(ptMarketValue, _PTamount, _minPtOut);
        // Maybe just fuck this part, seems off
        if (netPtOut > _PTamount) {
            uint256 remainder = _sellPtForToken(netPtOut - _PTamount, address(asset()));
            maxLoan -= remainder; //loan is partially paid off by remainder, term fee is still technically paid on remainder
        }
        //
        uint256 balanceAfter_trade = IERC20(asset()).balanceOf(address(this));
        if (balanceBefore_trade-balanceAfter_trade > borrowAmount) revert REPO__MaxLoanExceeded();

        loans[msg.sender] += 1;
        repos[msg.sender][loans[msg.sender]] = Repo(netPtOut, maxLoan, block.timestamp+_term);
        outstandingValue += maxLoan;
        
    }

    /// 
    /// @param _loanIndex index for which of the users loans to close
    function closeLong(uint256 _loanIndex) external { 
        Repo memory repo = repos[msg.sender][_loanIndex];
        uint256 sale_amount = _sellPtForToken(repo.collateralAmount, address(asset()));
        if (sale_amount > repo.repurchasePrice) {
            uint256 profit = sale_amount - repo.repurchasePrice;
            if (profit > 0) {
                SafeTransferLib.safeTransfer(asset(), msg.sender, profit);
            }
            outstandingValue -= repo.repurchasePrice;
            loans[msg.sender] -= 1;
            delete repos[msg.sender][_loanIndex];
        } else {
            revert REPO__LiquidationImpaired();
        }
    }

    function rolloverLoan(uint256 _loanIndex, uint256 _partialPayoff, uint256 _newTerm) external {
        Repo memory repo = repos[msg.sender][_loanIndex];
        // techincally the repurchasePrice is the amount lent to the user
        SafeTransferLib.safeTransferFrom(address(asset()), msg.sender, address(this), _partialPayoff);
        uint256 termFee = getTermFeeForAmount(repo.repurchasePrice-_partialPayoff, _newTerm);
        uint256 newRepurchasePrice = repo.repurchasePrice-_partialPayoff + termFee;
        // if the new loan amount violates the max LTV then revert
        if (newRepurchasePrice > maxLoanValue((repo.collateralAmount * oracle.getPtPrice() / 1 ether))) revert REPO__MaxLoanExceeded();
        repo.repurchasePrice = newRepurchasePrice;
        repo.termExpires += _newTerm;
        outstandingValue += termFee;
        outstandingValue -= (_partialPayoff);
    }
    /// @inheritdoc IERC3156FlashLender
    /// @notice allows a user to flash loan USDC or PT from the vault
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool)
    {
        if (amount > maxFlashLoan(token)) revert REPO__MaxLoanExceeded();

        uint256 fee = flashFee(token, amount);
        uint256 totalDebt = amount + fee;
        SafeTransferLib.safeTransfer(address(token), address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != keccak256("IERC3156FlashBorrower.onFlashLoan")) revert REPO__RepayFailed();

        SafeTransferLib.safeTransferFrom(address(token), address(receiver), address(this), totalDebt);
        return true;
    }
    /// @notice Allows a user to borrow usdc using PT as collateral
    /// @param _collateralAmount The amount of collateral to deposit
    /// @param _term The term of the repurchase agreement
    /// @param receiver The receiver of the borrowed assets
    function borrow(
        uint256 _collateralAmount,
        uint256 _term,
        address receiver
    ) external {
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        if (_collateralAmount == 0) revert REPO__ZeroAmount();
        if (_term < 1 days) revert REPO__InvalidTerm();

        SafeTransferLib.safeTransferFrom(address(collateral), msg.sender, address(this), _collateralAmount);
        uint256 collateralValue =  _collateralAmount* oracle.getPtPrice() / 1 ether; //_collateralAmount * 97 / 100; // Check precision
        uint256 maxBorrow = getMaxBorrow(collateralValue, _term);
        
        if (maxBorrow > IERC20(asset()).balanceOf(address(this))) revert REPO__MaxLoanExceeded();

        loans[receiver] += 1;
        repos[receiver][loans[receiver]] = Repo(_collateralAmount, maxLoanValue(collateralValue), block.timestamp+_term);
        outstandingValue += maxLoanValue(collateralValue);
        SafeTransferLib.safeTransfer(asset(), receiver, maxBorrow); 
    }

    /// @notice Allows a user to repurchase their collateral aka repay the loan
    /// @dev must be executed by the receiver of the original loan in full
    function repurchase(uint256 _loanIndex) public {
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        Repo memory repo = repos[msg.sender][_loanIndex];
        SafeTransferLib.safeTransferFrom(address(asset()), msg.sender, address(this), repo.repurchasePrice);
        SafeTransferLib.safeTransfer(address(collateral), msg.sender, repo.collateralAmount);
        outstandingValue -= repo.repurchasePrice;
        loans[msg.sender] -= 1;
        delete repos[msg.sender][_loanIndex];
    }

    /// @notice allows collateral from expired repurchase agreements to be liquidated
    /// @param _borrower The address of the borrower for whom the collateral is to be liquidated
    function liquidate(address _borrower, uint256 _loanIndex) public {
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        Repo memory repo = repos[_borrower][_loanIndex];
        if (repo.termExpires > block.timestamp) revert REPO__LoanTermNotExpired();
        // liquidate if liquidation proceeds are less than loan amount, the pool will hold onto collateral
        uint256 proceeds = _sellPtForToken(repo.collateralAmount, address(asset()));
        if (proceeds < repo.repurchasePrice) revert REPO__LiquidationImpaired();

        // liquidator get half of the profits
        SafeTransferLib.safeTransfer(address(asset()), msg.sender, (proceeds-repo.repurchasePrice) / 2);
        outstandingValue -= repo.repurchasePrice;
        loans[_borrower] -= 1;
        delete repos[_borrower][_loanIndex];
    }

    function swapExactTokenForPt(uint256 netTokenIn, uint256 _PtAmount, uint256 _minPtOut) internal returns (uint256 netPtOut){
        uint256 netSyOut = SY.deposit(address(this), address(asset()), netTokenIn, 1);
        SY.approve(address(market), netSyOut);
        (netPtOut, ) = _swapExactSyForPt(address(this), netSyOut, _PtAmount, _minPtOut);
        console.log("swapExactTokenForPt: %s", netPtOut);
    }

    function _swapExactSyForPt(address receiver, uint256 netSyIn, uint256 _PtAmount, uint256 _minPtOut) internal returns (uint256 netPtOut, uint256 netSyFee) {
        (netPtOut, netSyFee) = market.readState(address(this)).approxSwapExactSyForPt(
            YT.newIndex(),
            netSyIn,
            block.timestamp,
            ApproxParams({
                guessMin: _minPtOut,
                guessMax: _PtAmount,
                guessOffchain: 0,
                maxIteration: 10,
                eps: 10**15 // within 0.1%
            })
        );
        if (netPtOut < _minPtOut) revert REPO__SlippageToHigh();
        SafeTransferLib.safeTransfer(address(SY), address(market), netSyIn);
        market.swapSyForExactPt(receiver, netPtOut, EMPTY_BYTES);
    }

    // withdraw function is to withdraw liquidity: built in

    function _sellPtForToken(uint256 netPtIn, address tokenOut) internal returns (uint256 netTokenOut) {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();

        uint256 netSyOut;
        uint256 fee;
        console.log(netPtIn);
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
            console.log("netSyOut close position: %s", netSyOut);
            console.log("close fee: %s", fee);
        }

        netTokenOut = SY.redeem(address(this), netSyOut, tokenOut, 1, true); // true burns from the SYcontract balance

    }
    /// @notice returns the current rate for borrowing
    function getRate() view public returns(uint256) {
        return 300; // 3 basis points 
    }

    function getTermFeeForAmount(uint256 _amount, uint256 _term) view public returns(uint256) {
        return _amount * ((getRate()*_term)) / (RATE_PERCISION * 1 days);
    }
    function maxLoanValue(uint256 _collateralValue) view public returns(uint256) {
        return _collateralValue * LTV / RATE_PERCISION;
    }
    /// @notice returns the maximum amount that can be borrowed for a given amount of collateral 
    function getMaxBorrow(uint256 _collateralValue, uint256 _term) view public returns(uint256) {
        return maxLoanValue(_collateralValue) * ((1 days * RATE_PERCISION) -  (getRate()*_term)) / (RATE_PERCISION * 1 days);
        //return _collateralValue - (_collateralValue * getRate() * _term) / (RATE_PERCISION * 1 days);

    }
    function getTermFee(uint256 _collateralValue, uint256 _term) view public returns(uint256) {
        return maxLoanValue(_collateralValue) - getMaxBorrow(_collateralValue, _term);
    }
    /// DOESNT WORK TODO: Fix and test 
    function getCollateralRequired(uint256 _borrowAmount, uint256 _term) view public returns(uint256) {
        // double check this
        return (_borrowAmount * RATE_PERCISION * 1 days) / (getRate() * _term);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 underlyingValue = totalAssets() + outstandingValue;
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), underlyingValue + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 underlyingValue = totalAssets() + outstandingValue;
        return shares.mulDiv(underlyingValue+ 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }
    /** @dev See {IERC4626-maxWithdraw}. */
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