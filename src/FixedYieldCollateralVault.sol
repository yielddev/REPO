// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.20;

import { VaultBase, IEVC, EVCUtil, EVCClient } from "evc-playground/vaults/VaultBase.sol";
import { Ownable, Context } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC4626, IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RepoBaseVault } from "./RepoBaseVault.sol";

/// @title FixedYieldCollateralVault
/// @author Yielddev
/// @notice Implements the Fixed Yield Collateral Vault for use in the REPO protocol.
/// @notice Holds a fixed yield collateral and puts it under the control of the EVC
contract FixedYieldCollateralVault is RepoBaseVault {
    constructor(
        IEVC _evc,
        IERC20 _asset
    ) RepoBaseVault(_evc, _asset, string.concat("Repo ", ERC20(address(_asset)).name()), string.concat("Repo ", ERC20(address(_asset)).name())){}

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


}