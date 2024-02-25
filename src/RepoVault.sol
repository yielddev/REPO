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

error REPO__CollateralExpired();
error REPO__ZeroAmount();
error REPO__InvalidTerm();
error REPO__WrongToken();
error REPO__MaxLoanExceeded();
error REPO__RepayFailed();
// ausdc market 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5

contract RepoVault is ERC4626, IERC3156FlashLender {
    IPPrincipalToken public collateral;
    uint256 private RATE_PERCISION = 1_000_000;
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
    function maxFlashLoan(address token) public view override returns (uint256) {
        if (token != address(asset())) revert REPO__WrongToken();
        return IERC20(token).balanceOf(address(this));
    }
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        return amount * 10 / 1_000_000; // 0.1 basis points flashloan fee
    }
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
    function borrow(
        uint256 _collateralAmount,
        uint256 _borrowAmount,
        uint256 _term,
        address receiver
    ) public {
        if (collateral.isExpired()) revert REPO__CollateralExpired();
        if (_collateralAmount == 0 || _borrowAmount == 0) revert REPO__ZeroAmount();
        if (_term < 1 days) revert REPO__InvalidTerm();

        // require amount > 0 
        // Trusted preset, vetted token
        // remove this comment when confirmed safeTransfer not required
        collateral.transferFrom(msg.sender, address(this), _collateralAmount);
        uint256 collateralValue =  _collateralAmount* oracle.getPtPrice() / 1 ether;//_collateralAmount * 97 / 100; // Check precision
        uint256 maxBorrow = getMaxBorrow(collateralValue, _term); //collateralValue - fee;
        uint256 borrow = _borrowAmount <= maxBorrow ? _borrowAmount : maxBorrow;
        // Should probably be an NFT

        repos[receiver] = Repo(_collateralAmount, collateralValue, block.timestamp+_term);
        IERC20(asset()).transfer(receiver, borrow); // change to safe?
    }

    function repurchase() public {
        Repo memory repo = repos[msg.sender];
//        require(repo.termExpires < block.timestamp, "RepoVault: Term not expired");
        IERC20(asset()).transferFrom(msg.sender, address(this), repo.repurchasePrice);
        collateral.transfer(msg.sender, repo.collateralAmount);
        delete repos[msg.sender];
    }

    function liquidate(address _borrower) public {
        Repo memory repo = repos[msg.sender];
        require(repo.termExpires < block.timestamp, "RepoVault: Term not expired"); 
        // liquidate 
        // _sellPtForToken(market, repo.collateralAmount, expectedTokenOut);
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
    function getRate() view public returns(uint256) {
        return 300; // 3 basis points 
    }

    function getMaxBorrow(uint256 _collateralValue, uint256 _term) view public returns(uint256) {
        return _collateralValue - (_collateralValue * getRate() * _term) / (RATE_PERCISION * 1 days);
    }

    function getCollateralRequired(uint256 _borrowAmount, uint256 _term) view public returns(uint256) {
        // double check this
        return (_borrowAmount * RATE_PERCISION * 1 days) / (getRate() * _term);
    }


}