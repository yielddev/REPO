# Repo: Short Term Liquidity Collateralized by Fixed Yield Assets

The Repo platform implements lending vaults for holders of Fixed yielding assets, specifically Pendle Principal Tokens(PT).

Pendle PT are derivatives of yield bearing tokens with the variable yields stripped, converting the PT to a fixed yield asset with a fixed maturity. 

These assets provide a predicatble liquidity event with a predicitable return. 

## Lending Vault

The Repo Vault platforms allows holders of PTs to access short term liquidity and leverage. Using the PTs as collateral, borrowers can receive a very high LTV loan against the value of their assets financed at a fixed rate for a fixed period.

These loans are underwritten as repurchase agreements, where a borrower agrees to repurchase their collateral at some time in the future for a set price greater than the amount of the loan. The difference between the repurchase price and the amount of the loan. 

Because of the nature of these agreements, it is not neccesary to liquidate borrowers based the flucuations in the value of their collateral relative to their outstanding loan since the vault is still obligated to allow the borrower to repurchase the collateral at the end of the loan term.

Instead the collateral of deliquent loans can be liquidated at any point after the loan term is expired if the borrower chooses not to refinance or repurchase their assets. The expired collateral can then be sold for the repurchase price to any liquidator.

In addition to allowing holders of PTs to access liquidity, Loans implemented in this way also allow traders to speculate on the interest rate of the underlying asset by taking a leveraged long posiiton in the PT asset thereby gaining short exposure to the yield of the underlying. 

The liquidity providers of the vault can earn a higher short term, while mainting a relatively high level of liquidity and low levels of risk due to the predictable nature of the collateral assets. Since, the collateral always settles to 1 of the underlying asset at a fixed point in the future, LPs can be certain they will never suffer a nominal impairment due to default risk. Although, security/manipulation risk still existings across all the smart contracts that the platform interacts with. Other than security or price manipulation risks, the worst case scenario that the LPs face is liquidity impairment. In this case, there are no buyers for their excess collateral and they must simply wait until maturity to receive a 1:1 ratio for the asset underlying the PT. 

## Implementation 

Our protoype implements two, single-collateral repo vaults on euler. Each offering loans of the underlying asset for a given PT. 

wstETH-PT / wstETH
aUSDC-PT / usdc

Both offering 99% LTV loans including the repo fee.

Both also include functionality for opening a maximum sized loan with a very small initial capital by receiving the loan funds and purchasing the collateral within the same transaction, similar to a flashloan, using the EVCs internal collateral managment accountChecks.

These contracts integrate directly with the pendle market AMM to easily wrap the vaults liquidity into a SY token and swap that SY token to its associated PT and then deposit the newly purhased PT into the collateral vault and write a repo loan against in from the borrowable vault. 

At the end of this process the trader is leveraged long the collateral assets. 

## Test 

```
forge test --fork-url wss://dry-wiser-frost.arbitrum-mainnet.quiknode.pro/10a1b68e940ede30082ee2d24e7b1d949276bbda/ -vvv --match-path test/RepoVaultBorrowableTrading.t.sol

forge test --fork-url wss://dry-wiser-frost.arbitrum-mainnet.quiknode.pro/10a1b68e940ede30082ee2d24e7b1d949276bbda/ -vvv --match-path test/RepoVaultBorrowable.t.sol

forge test --fork-url wss://dry-wiser-frost.arbitrum-mainnet.quiknode.pro/10a1b68e940ede30082ee2d24e7b1d949276bbda/ -vvv --match-path test/RepoVaultTestWSTETH.t.sol

```

## Usage

All usage other than Deposit/Withdraw into vaults, require `evc.enableController` and `evc.enableCollateral`

In order to borrow, the collateral must first be deposit into the `FixedYieldCollateralVault.sol`
contract. The collateral vaults maintain a 1:1 ratio between their shares and assets deposited. there purpose is simply allow the EVC to control collateral in the case of a default.

Then the RepoVaulBorrowable can simply be called with 

```
RepoVaultBorrowable.borrow(uint256 assets, uint256 term, address receiver)
```

a new loan is created and saved in a map `repos[address]` and indexed starting at 1.
financing can be renewed by executing. 

```
    RepoVaultBorrowable.renewRepoLoan(
        address _borrower,
        uint256 _loanIndex,
        uint256 _partialPayoff,
        uint256 _newTerm
    ) 
```

A loan can be closed out and repurchased with.
```
    RepoVaultBorrowable.repurchase(address receiver, uint256 _loanIndex)
```

A deliquent loan can be liquidated by anyone by simply paying the purchase price. The liquidator is simply purchasing the collateral. 

```
    RepoVaultBorrowable.liquidate(address _borrower, uint256 _loanIndex)
```

Opening a leveraged long position simply requires the borrowable vault to be an approved spender of the purchasePrice less the borrowAmount. This transaction can be executed from the vault directly.

```
    RepoVaultBorrowable.openTradeBaseForPT(
        uint256 _PTAmount, // the amount of PT to long
        uint256 _term, // the financing term
        uint256 _minPtOut, // Max slippage
        address receiver // the receiver
    )
```

To close a position a repo agreement is paid of with proceeds of a sellPt transaction. This function can by any borrower to immediately liquidate their collateral. However if the sale amount is not enough to at least pay off the loan, it will revert.

```
    RepoVaultBorrowable.repurchaseAndSellPt(
        address borrower,
        address receiver,
        uint256 _loanIndex
    )
```



