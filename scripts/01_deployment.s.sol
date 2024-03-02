// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
contract Deployment is Script {
    IPPrincipalToken public aUSDCPT;
    PtUsdOracle public oracle;
    RepoVault public pool;
    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;

    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _PT = 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    address _USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    function run() public {
        //uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC"), 0);
        address deployerWallet = address(0x5A43FbDF36FF1C484488b7BfF1bbdeDc845E97a9);
        address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        IUSDC usdc_spoof = IUSDC(address(usdc));
        // usdc_spoof.configureMinter(address(this), type(uint256).max);
        // usdc_spoof.mint(deployerWallet, 1000 * DECIMALS);
        // usdc_spoof.mint(address(0x8E11D12876633885629ffA329Eb7bdAb4AD0Cd3B), 1000 * DECIMALS);
        // aUSDCPT = new MockPrincipalToken(address(0), "aUSDC", "aUSDC", 18, JUNE242024);
        // aUSDCPT.mintByYT(deployerWallet, 100 ether);
        aUSDCPT = IPPrincipalToken(_PT);
        // oracle = new MockPtUsdOracle();
        oracle = new PtUsdOracle(1 days, _market, address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));

        pool = new RepoVault(address(usdc), address(aUSDCPT), _SY, _market, address(oracle));

        console.log(ERC20(usdc).balanceOf(deployerWallet));

        ERC20(usdc).approve(address(pool), 100 * 10 ** 6);
        //pool.deposit(100 * 10**6, deployerWallet);

        vm.stopBroadcast();

        console.log("RepoVault deployed at: ", address(pool));
        console.log("oracle deployed at: ", address(oracle));
        console.log("aUSDCPT deployed at: ", address(aUSDCPT));
    }
}

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}
// forge script --rpc-url https://rpc.buildbear.io/persistent-siryn-0132e20a scripts/01_deployment.s.sol --legacy --broadcast