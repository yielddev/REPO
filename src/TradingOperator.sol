// pragma solidity 0.8.20;

// contract YieldTradeRouter {
//     constructor() {}

//     function openTradeBaseForPt(
//         uint256 _PTAmount,
//         uint256 _term,
//         uint256 _minPtOut,
//         address receiver,
//         address market,
//         address repoVault,
//         ) external {
//         address msgSender = _msgSenderForBorrow();
//         // due to later violator's account check forgiveness,
//         // the violator's account must be fully settled when liquidating
//         if (isAccountStatusCheckDeferred(violator)) {
//             revert ViolatorStatusCheckDeferred();
//         }

//         // sanity check: the violator must be under control of the EVC
//         if (!isControllerEnabled(violator, address(this))) {
//             revert ControllerDisabled();
//         }

//         createVaultSnapshot();

//         uint256 ptMarketValue = IPMarketV3(market).getPtToAssetRate(uint32(1 days)) * _PTAmount / 1 ether;
//         RepoVaultBorrowable(repoVault).borrow(ptMarketValue, _term, receiver);
//         forgiveAccountStatusCheck(violator);
//         // user now has the maxBorrow amount of ptMarketValue
//         // transfer ptMarketValue to this contract
//         SafeERC20(RepoVaultBorrowable(repoVault).asset()).safeTransferFrom(msg.sender, address(this), ptMarketValue);
//         // swap it for exact Pt
//         uint256 netPtOut = swapExactTokenForPt(
//             ptMarketValue, _PTAmount, _minPtOut, market, RepoVaultBorrowable(repoVault).asset()
//         );
        
//         // now user must deposit the netPtOut to the collateral vault
//         collateralVault.deposit(receiver, netPtOut);
//         // do account checks
//         requireAccountAndVaultStatusCheck(msgSender);
//     } 
//     function swapExactTokenForPt(
//         uint256 netTokenIn,
//         uint256 _PtAmount,
//         uint256 _minPtOut,
//         address market,
//         address tokenIn
//     ) internal returns (uint256 netPtOut){
//         (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();
//         uint256 netSyOut = SY.deposit(address(this), tokenIn, netTokenIn, 1);
//         SY.approve(address(market), netSyOut);
//         (netPtOut, ) = _swapExactSyForPt(address(this), netSyOut, _PtAmount, _minPtOut, market);
//         console.log("swapExactTokenForPt: %s", netPtOut);
//     }
//     function _swapExactSyForPt(
//         address receiver,
//         uint256 netSyIn,
//         uint256 _PtAmount,
//         uint256 _minPtOut,
//         address market
//     ) internal returns (uint256 netPtOut, uint256 netSyFee) {
//         (IStandardizedYield SY, IPPrincipalToken PT, IPYieldToken YT) = IPMarketV3(market).readTokens();
//         (netPtOut, netSyFee) = IPMarketV3(market).readState(address(this)).approxSwapExactSyForPt(
//             YT.newIndex(),
//             netSyIn,
//             block.timestamp,
//             ApproxParams({
//                 guessMin: _minPtOut,
//                 guessMax: _PtAmount,
//                 guessOffchain: 0,
//                 maxIteration: 10,
//                 eps: 10**15 // within 0.1%
//             })
//         );
//         if (netPtOut < _minPtOut) revert REPO__SlippageToHigh();
//         SafeTransferLib.safeTransfer(address(SY), address(market), netSyIn);
//         market.swapSyForExactPt(receiver, netPtOut, EMPTY_BYTES);
//     }
// }