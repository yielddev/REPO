// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import { IPtUsdOracle } from "../interfaces/IPtUsdOracle.sol";
contract MockPtUsdOracle is IPtUsdOracle {
    function getPtPrice() external view override returns (uint256) {
        return 0.97 ether;
    }
}