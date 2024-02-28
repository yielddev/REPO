// SPDX-License-Identifier: GPL-2.0-or-later
import { PtCollateralVault } from "./PtCollateralVault.sol";

pragma solidity ^0.8.20;

contract RepoVaultBorrowable is PtCollateralVault.sol {
    constructor(
        IEVC _evc,
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) PtCollateralVault(_evc, _asset, _name, _symbol) {}
}