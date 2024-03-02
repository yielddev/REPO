// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "solmate/utils/SafeTransferLib.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";

contract RepoPlatformOperator {
    IEVC public immutable evc;
    address public collateralVault;
    address public repoVault;
    constructor(
        IEVC _evc,
        address _collateralVault,
        address _repoVault
    ) {
        evc = _evc;
        collateralVault = _collateralVault;
        repoVault = _repoVault;
    }

    function approveAllVaultsOnBehalfOf(address onBehalfOfAccount) external {
        evc.enableController(onBehalfOfAccount, repoVault);
        evc.enableCollateral(onBehalfOfAccount, repoVault);
        evc.enableCollateral(onBehalfOfAccount, collateralVault);
    }
}