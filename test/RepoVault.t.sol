// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import { ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import "forge-std/console.sol";
contract RepoVaultTest is Test {
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

        vm.warp(JUNE242024 - 90 days);
        aUSDCPT = new MockPrincipalToken(address(0), "aUSDC", "aUSDC", 18, JUNE242024);
        aUSDCPT.mintByYT(UserWallet, 100 ether);

        //setup oracle
        oracle = new MockPtUsdOracle();
        // Functional Oracle
        // new MockPtUsdOracle(1 days, address(0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5), address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));
        
        // console.log(oracle.getPtPrice());


        pool = new RepoVault(address(usdc), address(aUSDCPT), address(oracle));
        usdc.mint(lp, 100 ether);


    } 
    function test_deposits() public {
        vm.startPrank(lp);
        usdc.approve(address(pool), 100 ether);
        pool.deposit(100 ether, lp);
        assertEq(pool.balanceOf(lp), 100 ether);
        assertEq(usdc.balanceOf(lp), 0);
        assertEq(usdc.balanceOf(address(pool)), 100 ether);
        vm.stopPrank();
    }
    function test_withdraw() public {
        test_deposits();
        vm.startPrank(lp);
        pool.approve(address(pool), 100 ether);
        pool.redeem(100 ether, lp, lp);
        assertEq(pool.balanceOf(lp), 0);
        assertEq(usdc.balanceOf(lp), 100 ether);
        assertEq(usdc.balanceOf(address(pool)), 0);
    }
    function test_borrow() public {
        test_deposits();
        vm.startPrank(UserWallet);
        aUSDCPT.approve(address(pool), 10 ether);
        uint256 borrowAmount = (9.7 ether * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        pool.borrow(10 ether, borrowAmount, 1 days, UserWallet);
        // user holds borrow amount
        assertEq(usdc.balanceOf(UserWallet), borrowAmount);
        assertEq(usdc.balanceOf(address(pool)), 100 ether - borrowAmount);
        // pool holds 10 of collateral
        assertEq(aUSDCPT.balanceOf(UserWallet), 90 ether);
        assertEq(aUSDCPT.balanceOf(address(pool)), 10 ether);
    }
    function test_repurchase() public {
        uint256 fee = (9.7 ether * 300) / 1_000_000;
        uint256 borrowAmount = 9.7 ether - fee;
        
        test_borrow();
        vm.startPrank(UserWallet);
        usdc.mint(UserWallet, fee);
        usdc.approve(address(pool), uint256(UINT256_MAX));
        pool.repurchase();
        assertEq(usdc.balanceOf(UserWallet), 0);
        assertEq(usdc.balanceOf(address(pool)), 100 ether+fee);

        assertEq(aUSDCPT.balanceOf(UserWallet), 100 ether);
        assertEq(aUSDCPT.balanceOf(address(pool)), 0);
        
    }
}



