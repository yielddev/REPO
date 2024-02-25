## function calls

Deposts `usdc_amount` and transfers the user appropriate amount of shares
User must have approved address(RepoVault) as a spender of usdc_amount allowance

```
RepoVault.deposit(usdc_amount, user_address)
```

Mint `shares_amount` of shares and pulls the appropriate amount of usdc from the user

```
RepoVault.mint(shares_amount, user_address)
```

Withdraws `usdc_amount` of assets and burns the appropraite amount of shares
```
RepoVault.withdraw(usdc_amount, receiver_address, owner_address)
```

Redeems (burns) `shares_amount` amount of shares and transfers the appropraite amount of assets
```
redeem(uint256 shares_amount, address receiver, address owner)
```
