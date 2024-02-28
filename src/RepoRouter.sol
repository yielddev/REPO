// // SPDX-License-Identifier: GPL-2.0-or-later

// pragma solidity 0.8.20;
// import { RepoVault } from "./RepoVault.sol";
// import { PtUsdOracle } from "./PtUsdOracle.sol";
// import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
// import { IStandardizedYield } from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
// import { IPMarketV3 } from "@pendle/core/contracts/interfaces/IPMarketV3.sol";

// // SY aUDC 0x50288c30c37FA1Ec6167a31E575EA8632645dE20
// contract RepoRouter is IERC3156FlashBorrower {
//     RepoVault public repoVault;
//     PtUsdOracle public oracle;
//     IStandardizedYield public SY;
//     IPMarketV3 public market;
//     constructor(
//         address _repoVault,
//         address _ptUsdOracle,
//         address _SY,
//         address _market
//     ) {
//         repoVault = RepoVault(_repoVault);
//         SY = IStandardizedYield(_SY);
//         market = IPMarketV3(_market);
//         oracle = PtUsdOracle(_ptUsdOracle);

//     }

//     function leveragedLong(uint256 _PTamount, uint256 _term) external {
//         uint256 ptMarketValue = PtUsdOracle(repoVault.oracle()).getPtPrice() * _PTamount;
//         uint256 maxLoanValue = repoVault.getMaxLoanValue(ptMarketValue, _term);
//         uint256 getMaxBorrow = repoVault.getMaxBorrow(ptMarketValue, _term);
//         uint256 termFee = maxLoanValue - getMaxBorrow; 
//         // Flash loan maxLoanValue
//         repoVault.flashLoan(address(this), address(repoVault.asset()), maxLoanValue, EMPTY_BYTES);
//         // purchase PT
//         // repovault.borrow borrow amount
//         // borrowamount + term fee = repay flashloan
// //        repoVault.deposit(_PTamount, msg.sender);
//     }

//     function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata _params) external override {
//         require(msg.sender == address(repoVault), "RepoRouter: Only RepoVault can call this function");
//         require(_initiator == address(this), "RepoRouter: Initiator is not this contract");
//         require(_token == address(repoVault.asset()), "RepoRouter: Token is not PT");
//         //require(_fee == 0, "RepoRouter: Fee is not 0");
//         //require(_params.length == 0, "RepoRouter: Params is not 0");
//         // do something
//         //SY base deposit  amout should be amount+ fee, 
//         SY.deposit(address(this), _token, _amount, tokensOut);
//         // sell SY for PT
//         // Flash Loan Data Needs
//         // exactPT to buy (_PTamount) 
//         // receiver: of the repo loan 
//         // term: of the repo loan
//         // 
//         market.swapSyForExactPt(address(this), exactPt, EMPTY_BYTES);
//         repoVault.borrow(exactPt, _term, receiver);
//         IERC20(_token).approve(address(repoVault), _amount + _flashLoanfee);
//         return keccak256("IERC3156FlashBorrower.onFlashLoan");
//     }

// }