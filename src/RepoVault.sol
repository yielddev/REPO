pragma solidity 0.8.20;
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IStandardizedYield } from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import { IPYieldToken } from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { IPMarket } from "@pendle/core/contracts/interfaces/IPMarket.sol";
import { PtUsdOracle } from "./PtUsdOracle.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

error REPO__CollateralExpired();
error REPO__ZeroAmount();
error REPO__InvalidTerm();
error REPO__WrongToken();
error REPO__MaxLoanExceeded();
error REPO__RepayFailed();
error REPO__LiquidationImpaired();
// ausdc market 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5

/// @title RepoVault
/// @author yielddev
/// @notice This implements a ERC4626 vault that allows for repo loans with PT as collateral
contract RepoVault is ERC4626, IERC3156FlashLender {
    using SafeTransferLib for IERC20;
    using Math for uint256;
    IPPrincipalToken public collateral;
    uint256 private RATE_PERCISION = 1_000_000;
    uint256 public LTV = 990_000; // 99% LTV
    uint256 outstandingValue;
    bytes internal constant EMPTY_BYTES = abi.encode();
    address public market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    PtUsdOracle public oracle;

    mapping(address => Repo) public repos;
    struct Repo {
        uint256 collateralAmount;
        uint256 repurchasePrice;
        uint256 termExpires;
    }
    constructor(address _depositToken, address _pt, address _oracle) ERC4626(IERC20(_depositToken)) ERC20("RepoVault", "RV"){
        collateral = IPPrincipalToken(_pt);
        oracle = PtUsdOracle(_oracle);
    }

    // Built in deposit function is provide liquidity
    /// 
    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(asset())) revert REPO__WrongToken();
        return IERC20(token).balanceOf(address(this));
    }
    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        return amount * 10 / 1_000_000; // 0.1 basis points flashloan fee
    }
    /// @inheritdoc IERC3156FlashLender
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
        SafeTransferLib.safeTransfer(address(asset()), address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != keccak256("IERC3156FlashBorrower.onFlashLoan")) revert REPO__RepayFailed();

        SafeTransferLib.safeTransferFrom(address(asset()), address(receiver), address(this), totalDebt);
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
    ) public {
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        if (_collateralAmount == 0) revert REPO__ZeroAmount();
        if (_term < 1 days) revert REPO__InvalidTerm();

        SafeTransferLib.safeTransferFrom(address(collateral), msg.sender, address(this), _collateralAmount);
        uint256 collateralValue =  _collateralAmount* oracle.getPtPrice() / 1 ether; //_collateralAmount * 97 / 100; // Check precision
        //uint256 maxBorrow = getMaxBorrow(collateralValue, _term); //collateralValue - fee;
        //uint256 borrow = _borrowAmount <= maxBorrow ? _borrowAmount : maxBorrow;
        // should probably be an NFT

        uint256 maxBorrow = getMaxBorrow(collateralValue, _term);
        if (maxBorrow > IERC20(asset()).balanceOf(address(this))) revert REPO__MaxLoanExceeded();
        repos[receiver] = Repo(_collateralAmount, maxLoanValue(collateralValue), block.timestamp+_term);
        outstandingValue += maxLoanValue(collateralValue);
        SafeTransferLib.safeTransfer(asset(),receiver, maxBorrow); 
    }

    /// @notice Allows a user to repurchase their collateral aka repay the loan
    /// @dev must be executed by the receiver of the original loan
    function repurchase() public {
        Repo memory repo = repos[msg.sender];
        SafeTransferLib.safeTransferFrom(address(asset()), msg.sender, address(this), repo.repurchasePrice);
        SafeTransferLib.safeTransfer(address(collateral), msg.sender, repo.collateralAmount);
        outstandingValue -= repo.repurchasePrice;
        delete repos[msg.sender];
    }

    /// @notice allows collateral from expired repurchase agreements to be liquidated
    /// @param _borrower The address of the borrower for whom the collateral is to be liquidated
    function liquidate(address _borrower) public {
        Repo memory repo = repos[msg.sender];
        require(repo.termExpires < block.timestamp, "RepoVault: Term not expired"); 
        // liquidate 

        if(_sellPtForToken(repo.collateralAmount, address(asset())) < repo.repurchasePrice) revert REPO__LiquidationImpaired();
        outstandingValue -= repo.repurchasePrice;
        delete repos[msg.sender];
    }

    // withdraw function is to withdraw liquidity: built in

    function _sellPtForToken(uint256 netPtIn, address tokenOut) internal returns (uint256 netTokenOut) {
        (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market).readTokens();

        uint256 netSyOut;
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            // safeTransfer not required
            PT.transfer(market, netPtIn);
            (netSyOut, ) = IPMarket(market).swapExactPtForSy(
                address(SY), // better gas optimization to transfer SY directly to itself and burn
                netPtIn,
                EMPTY_BYTES
            );
        }

        netTokenOut = SY.redeem(address(this), netSyOut, tokenOut, 0, true);
    }
    /// @notice returns the current rate for borrowing
    function getRate() view public returns(uint256) {
        return 300; // 3 basis points 
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
        if (collateral.isExpired()) {
            return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        } else {
            return _convertToAssets(maxRedeem(owner), Math.Rounding.Floor);
        }
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        if (collateral.isExpired()) {
            return balanceOf(owner);
        } else {
            return balanceOf(owner).mulDiv(totalAssets(), (totalAssets()+outstandingValue), Math.Rounding.Floor);
        }
    }

}