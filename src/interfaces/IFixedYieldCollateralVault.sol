// SPDX-License-Identifier: GPL-2.0-or-later

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "evc/interfaces/IVault.sol";

pragma solidity 0.8.20;

interface IFixedYieldCollateralVault is IVault, IERC4626{

}