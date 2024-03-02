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
// forge script --rpc-url https://rpc.buildbear.io/persistent-siryn-0132e20a scripts/01_deployment.s.sol --legacy
// forge test --fork-url https://rpc.buildbear.io/persistent-siryn-0132e20a -vv   
contract RepoVaultTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public lp;
    MockUSDC public usdc;
    RepoVault public pool;
    MockPrincipalToken public aUSDCPT;
    MockPtUsdOracle public oracle;
    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
    uint256 CENTS = 10**4;

    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        usdc = new MockUSDC(); 

        vm.warp(JUNE242024 - 90 days);
        aUSDCPT = new MockPrincipalToken(address(0), "aUSDC", "aUSDC", 18, JUNE242024);
        aUSDCPT.mintByYT(UserWallet, 100 * DECIMALS);

        //setup oracle
        oracle = new MockPtUsdOracle();
        // Functional Oracle
        // new MockPtUsdOracle(1 days, address(0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5), address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));
        // console.log(oracle.getPtPrice());
        pool = new RepoVault(address(usdc), address(aUSDCPT), _SY, _market, address(oracle));
        usdc.mint(lp, 100 * DECIMALS);
    } 

    function test_deposits() public {
        vm.startPrank(lp);
        usdc.approve(address(pool), 100 * DECIMALS);
        pool.deposit(100 * DECIMALS, lp);
        assertEq(pool.balanceOf(lp), 100 * DECIMALS);
        assertEq(usdc.balanceOf(lp), 0);
        assertEq(usdc.balanceOf(address(pool)), 100 * DECIMALS);
        vm.stopPrank();
    }
    function test_withdraw() public {
        test_deposits();
        vm.startPrank(lp);
        pool.approve(address(pool), 100 * DECIMALS);
        pool.redeem(100 * DECIMALS, lp, lp);
        assertEq(pool.balanceOf(lp), 0);
        assertEq(usdc.balanceOf(lp), 100 * DECIMALS);
        assertEq(usdc.balanceOf(address(pool)), 0);
    }
    function test_borrow() public {
        test_deposits();
        vm.startPrank(UserWallet);

        aUSDCPT.approve(address(pool), 10 * DECIMALS);
        uint256 loanAmount = (97 * CENTS * 990_000) / 1_000_000; //(9.7 * DECIMALS * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        uint256 borrowAmount = loanAmount * (1_000_000 - (300*1)) / 1_000_000;
        pool.borrow(10 * DECIMALS, 1 days, UserWallet);
        // user holds borrow amount
        assertEq(usdc.balanceOf(UserWallet), borrowAmount);
        assertEq(usdc.balanceOf(address(pool)), 100 * DECIMALS - borrowAmount);
        // pool holds 10 of collateral
        assertEq(aUSDCPT.balanceOf(UserWallet), 90 * DECIMALS);
        assertEq(aUSDCPT.balanceOf(address(pool)), 10 * DECIMALS);
    }
    function test_borrow_seven_days() public {
        test_deposits();
        vm.startPrank(UserWallet);
        aUSDCPT.approve(address(pool), 10 * DECIMALS);
        uint256 loanAmount = (97 * CENTS * 990_000) / 1_000_000; //(9.7 * DECIMALS * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        uint256 borrowAmount = loanAmount * (1_000_000 - (300*7)) / 1_000_000;
        pool.borrow(10 * DECIMALS, 7 days, UserWallet);
        // user holds borrow amount
        assertEq(usdc.balanceOf(UserWallet), borrowAmount);
        // assertEq(usdc.balanceOf(address(pool)), 100 * DECIMALS - borrowAmount);
        // pool holds 10 of collateral
        assertEq(aUSDCPT.balanceOf(UserWallet), 90 * DECIMALS);
        assertEq(aUSDCPT.balanceOf(address(pool)), 10 * DECIMALS); 
    }
    function test_deposit_while_value_outstanding() public {
        test_deposits();
        vm.startPrank(UserWallet);
        aUSDCPT.approve(address(pool), 10 * DECIMALS);
        uint256 loanAmount = (97 * CENTS * 990_000) / 1_000_000; //(9.7 * DECIMALS * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        uint256 borrowAmount = loanAmount * (1_000_000 - (300*1)) / 1_000_000;
        pool.borrow(10 * DECIMALS, 1 days, UserWallet);
        vm.stopPrank();

        usdc.mint(lp, 100 * DECIMALS);
        vm.startPrank(lp);
        usdc.approve(address(pool), 100 * DECIMALS);
        pool.deposit(100 * DECIMALS, lp);
        assertEq(usdc.balanceOf(address(pool)), (200 * DECIMALS)-borrowAmount);
        console.log("balance: ", pool.balanceOf(lp));
        uint256 newShares = 100 * DECIMALS * (100 * DECIMALS) / ((100 * DECIMALS) + (loanAmount - borrowAmount));
        assertEq(pool.balanceOf(lp), 100 * DECIMALS + newShares);
        // assertEq(usdc.balanceOf(lp), 0);
        vm.stopPrank();
    }
    function test_repurchase() public {
        uint256 loanAmount = (97 * CENTS * 990_000) / 1_000_000; //(9.7 * DECIMALS * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        uint256 borrowAmount = loanAmount * (1_000_000 - (300*1)) / 1_000_000;
        uint256 fee = loanAmount - borrowAmount;
        
        test_borrow();
        vm.startPrank(UserWallet);
        usdc.mint(UserWallet, fee);
        usdc.approve(address(pool), uint256(UINT256_MAX));
        pool.repurchase(1);
        assertEq(usdc.balanceOf(UserWallet), 0);
        assertEq(usdc.balanceOf(address(pool)), 100 * DECIMALS+fee);

        assertEq(aUSDCPT.balanceOf(UserWallet), 100 * DECIMALS);
        assertEq(aUSDCPT.balanceOf(address(pool)), 0);
        
    }
    // function test_go_long() public {
    //     test_deposits();
    //     usdc.mint(UserWallet, 100 * DECIMALS);
    //     vm.startPrank(UserWallet);
    //     usdc.approve(address(pool), 100 * DECIMALS);
    //     pool.goLong(1 * DECIMALS, 1 days);
    //     console.log("balance: ", usdc.balanceOf(UserWallet));
    // }
}

//$ forge create --rpc-url <your_rpc_url> --private-key <your_private_key> src/MyContract.sol:MyContract



