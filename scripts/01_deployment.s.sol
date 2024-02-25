// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deployment is Script {
    MockPrincipalToken public aUSDCPT;
    MockPtUsdOracle public oracle;
    RepoVault public pool;
    uint256 JUNE242024 = 1719248606;

    function run() public {
        //uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC"), 0);
        address deployerWallet = address(0x5A43FbDF36FF1C484488b7BfF1bbdeDc845E97a9);
        address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        vm.startBroadcast(0x754b28153d34d9d9f6158517f4a3755189fe55f33ca81b1722f573d6488a2847);

        aUSDCPT = new MockPrincipalToken(address(0), "aUSDC", "aUSDC", 18, JUNE242024);
        aUSDCPT.mintByYT(deployerWallet, 100 ether);

        oracle = new MockPtUsdOracle();

        pool = new RepoVault(address(usdc), address(aUSDCPT), address(oracle));

        console.log(ERC20(usdc).balanceOf(deployerWallet));

        ERC20(usdc).approve(address(pool), 100 * 10 ** 6);
        pool.deposit(100 * 10**6, deployerWallet);

        vm.stopBroadcast();

        console.log("RepoVault deployed at: ", address(pool));
        console.log("oracle deployed at: ", address(oracle));
        console.log("aUSDCPT deployed at: ", address(aUSDCPT));
    }
}