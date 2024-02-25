// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import { ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { PPrincipalToken } from "@pendle/core/contracts/interfaces/PPrincipalToken.sol";
import "forge-std/console.sol";

contract ForkRepoVaultTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public lp;
    MockUSDC public usdc;
    RepoVault public pool;
    MockPrincipalToken public aUSDCPT;
    MockPtUsdOracle public oracle;
    uint256 JUNE242024 = 1719248606;
    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        usdc = new MockUSDC(); 

//        vm.warp(JUNE242024 - 90 days);
        aUSDCPT = PPrincipalToken(0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c);
//        aUSDCPT.mintByYT(UserWallet, 100 ether);
        //setup oracle
        oracle = new PtUsdOracle(1 days, address(0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5), address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));
        // Functional Oracle
        // new MockPtUsdOracle();
        // console.log(oracle.getPtPrice());
        pool = new RepoVault(address(usdc), address(aUSDCPT), address(oracle));
        usdc.mint(lp, 100 ether);
    }   
}