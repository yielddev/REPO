// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.20;
import "forge-std/Script.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { RepoVaultBorrowable } from "../src/RepoVaultBorrowable.sol";
import { FixedYieldCollateralVault } from "../src/FixedYieldCollateralVault.sol";
import "evc/EthereumVaultConnector.sol";
import { RepoPlatformOperator } from "../src/RepoPlatformOperator.sol";
contract Deployment is Script {
    IPPrincipalToken public aUSDCPT;
    PtUsdOracle public oracle;
    // RepoVault public pool;
    FixedYieldCollateralVault public collateralVault;
    RepoVaultBorrowable public pool;
    RepoPlatformOperator public operator;
    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
    IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _PT = 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    address _USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    function run() public {
        //uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC"), 0);
        address deployerWallet = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        IUSDC usdc_spoof = IUSDC(address(usdc));

        aUSDCPT = IPPrincipalToken(_PT);
//   oracle deployed at:  0x56FA06B9Fd91845Ca48f49c6cB05a966a509CbBE
//   aUSDCPT deployed at:  0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c
//   collateralVault deployed at:  0xE07EfD64a9de62d4eEa5B372876EBfC3d2D78D2e
//   evc deployed oconsoat:  0xb18F31145F2865a943957D22b9Da1c93C80aDa47
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        // evc = new EthereumVaultConnector();
        // collateralVault = new FixedYieldCollateralVault(evc, IERC20(address(aUSDCPT)));
        // oracle = new PtUsdOracle(1 days, _market, address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));
        // pool = new RepoVaultBorrowable(
        //     evc,
        //     IERC20(usdc),
        //     address(0xE07EfD64a9de62d4eEa5B372876EBfC3d2D78D2e),
        //     _PT,
        //     address(0x56FA06B9Fd91845Ca48f49c6cB05a966a509CbBE),
        //     _market
        // );
        // pool.setCollateralFactor(address(collateralVault), 990_000);
        operator = new RepoPlatformOperator(evc, address(0xE07EfD64a9de62d4eEa5B372876EBfC3d2D78D2e), address(0x67878578463A985398059f32F73d98462f25aC23));
        vm.stopBroadcast();

        console.log("RepoVault deployed at: ", address(pool));
        // console.log("oracle deployed at: ", address(oracle));
        // console.log("aUSDCPT deployed at: ", address(aUSDCPT));
        // console.log("collateralVault deployed at: ", address(collateralVault));
        // console.log("evc deployed oconsoat: ", address(evc));
        console.log("operator deployed at: ", address(operator));
    }
}

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}