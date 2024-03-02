// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import { ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { RepoVaultBorrowable } from "../src/RepoVaultBorrowable.sol";
import { FixedYieldCollateralVault } from "../src/FixedYieldCollateralVault.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { RepoPlatformOperator } from "../src/RepoPlatformOperator.sol";
import "evc/EthereumVaultConnector.sol";
import "forge-std/console.sol";


contract RepoVaultBorrowableTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public Liquidator;
    address public lp;
    MockUSDC public usdc;
    RepoVaultBorrowable public pool;
    MockPrincipalToken public aUSDCPT;
    MockPtUsdOracle public oracle;
    FixedYieldCollateralVault public collateralVault;
    RepoPlatformOperator public operator;

    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
    uint256 CENTS = 10**4;
    IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    error REPO__MaxLoanExceeded();
    function setUp() public {

        lp = address(69);
        UserWallet = address(420);
        Liquidator = address(4210000000000005);
        usdc = new MockUSDC(); 
        evc = new EthereumVaultConnector();
        vm.warp(JUNE242024 - 90 days);
        aUSDCPT = new MockPrincipalToken(address(0), "PrincipalToken aUSDC", "PTaUSDC", 18, JUNE242024);
        aUSDCPT.mintByYT(UserWallet, 100 * DECIMALS);

        //setup oracle
        oracle = new MockPtUsdOracle();

        collateralVault = new FixedYieldCollateralVault(evc, ERC20(aUSDCPT));


        pool = new RepoVaultBorrowable(
            evc,
            usdc,
            address(collateralVault),
            address(aUSDCPT),
            // _market,
            address(oracle),
            _market
  
        );

        operator = new RepoPlatformOperator(evc, address(collateralVault), address(pool));

        console.log(pool.name());
        console.log(pool.symbol()); 
        usdc.mint(lp, 100 * DECIMALS);
    }
    function test_approve_operator() public {
        test_deposits();
        vm.startPrank(UserWallet);
        evc.setAccountOperator(UserWallet, address(operator), true);
        operator.approveAllVaultsOnBehalfOf(UserWallet);
        aUSDCPT.approve(address(collateralVault), 10 * DECIMALS);
        collateralVault.deposit(10 * DECIMALS, UserWallet);
        // user moves 10 PT to collateral Vault
        assertEq(collateralVault.balanceOf(UserWallet), 10 * DECIMALS);
        assertEq(aUSDCPT.balanceOf(UserWallet), 90 * DECIMALS); 

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
        evc.enableController(UserWallet, address(pool));
        evc.enableCollateral(UserWallet, address(collateralVault));
        evc.enableCollateral(UserWallet, address(pool));

        aUSDCPT.approve(address(collateralVault), 10 * DECIMALS);
        collateralVault.deposit(10 * DECIMALS, UserWallet);
        // user moves 10 PT to collateral Vault
        assertEq(collateralVault.balanceOf(UserWallet), 10 * DECIMALS);
        assertEq(aUSDCPT.balanceOf(UserWallet), 90 * DECIMALS);


        // uint256 loanAmount = (97 * CENTS * 990_000) / 1_000_000; //(9.7 * DECIMALS * (1_000_000 - 300) * 1 days) / (1_000_000 * 1 days);
        //uint256 borrowAmount = loanAmount * (1_000_000 - (300*1)) / 1_000_000;
        pool.borrow(950 * CENTS, 1 days, UserWallet);
        // user holds borrow amount 9.50 pool is less by 9.50
        assertEq(usdc.balanceOf(UserWallet), 950 * CENTS);
        assertEq(usdc.balanceOf(address(pool)), 100 * DECIMALS - (950 * CENTS));
        // pool holds 10 of collateral


        uint256 loanAmount = (950 *CENTS) + pool.getTermFeeForAmount(950 * CENTS, 1 days);
        uint256 collateralValueRequired = (loanAmount) * 1_000_000 / 990_000;
        // console.log(collateralValueRequired);
        uint256 collateralAmount = collateralValueRequired * 1 ether / (.97 ether);
        // console.log(collateralAmount);
        (uint256 collateralNominal, , ) = pool.getRepoLoan(address(UserWallet), 1);
        // console.log("collateralAmount", collateralNominal);

        // user tries to withdraw all PT from collateral Vault expect a MaxLoanExceeded Revert
        vm.expectRevert(abi.encodeWithSelector(REPO__MaxLoanExceeded.selector));
        collateralVault.withdraw(10 * DECIMALS, UserWallet, UserWallet);
    }
    function test_repurchase() public {
        // uint256 repurchasePrice = (950*CENTS) + pool.getTermFeeForAmount(950 * CENTS, 1 days);
        uint256 repurchasePrice = (950 * CENTS) + ((950*CENTS) * pool.getRate((950*CENTS), 10*DECIMALS, 0) / 1_000_000);
        console.log("repo price: ", repurchasePrice);
        test_borrow();
        console.log("rebalance: ", usdc.balanceOf(address(UserWallet)));
        usdc.mint(UserWallet, repurchasePrice - usdc.balanceOf(address(UserWallet)));
        vm.startPrank(UserWallet);
        usdc.approve(address(pool), repurchasePrice);
        (uint256 collateralNominal, uint256 loanAmount, ) = pool.getRepoLoan(address(UserWallet), 1);
        console.log("loanAmount: ", loanAmount);
        pool.repurchase(UserWallet, 1);
        assertEq(usdc.balanceOf(UserWallet), 0);
        console.log("rebalance: ", usdc.balanceOf(address(UserWallet)));
        assertGe(usdc.balanceOf(address(pool)), 100 * DECIMALS);
        (collateralNominal, loanAmount, ) = pool.getRepoLoan(address(UserWallet), 1);
        console.log("loanAmount2: ", loanAmount);

        assertEq(pool.pledgedCollateral(UserWallet), 0);
        assertEq(pool.loans(UserWallet), 0);
    }
    function test_liquidation() public {
        test_borrow();
        usdc.mint(Liquidator, 100 * DECIMALS);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(Liquidator);
        evc.enableController(Liquidator, address(pool));

        usdc.approve(address(pool), 100 * DECIMALS);
        (uint256 collateralNominal, uint256 repurchasePrice, ) = pool.getRepoLoan(address(UserWallet), 1);

        uint256 preAssets = pool.totalAssets();
        pool.liquidate(UserWallet, 1);

        assertEq(usdc.balanceOf(Liquidator), (100 * DECIMALS) - repurchasePrice);
        assertEq(collateralVault.balanceOf(Liquidator), collateralNominal);
        assertEq(usdc.balanceOf(address(pool)), preAssets + (repurchasePrice));


    }
}