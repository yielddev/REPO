// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import { ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { IStandardizedYield } from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { FixedYieldCollateralVault } from "../src/FixedYieldCollateralVault.sol";
import { RepoVaultBorrowable } from "../src/RepoVaultBorrowable.sol";
import "evc/EthereumVaultConnector.sol";
import "forge-std/console.sol";
// forge script --rpc-url https://rpc.buildbear.io/persistent-siryn-0132e20a scripts/01_deployment.s.sol --legacy
// forge test --fork-url https://rpc.buildbear.io/persistent-siryn-0132e20a -vv   
contract RepoVaultTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public lp;
    ERC20 public usdc;
    IUSDC public usdc_spoof;
    RepoVaultBorrowable public pool;
    IPPrincipalToken public aUSDCPT;
    PtUsdOracle public oracle;
    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
    FixedYieldCollateralVault public collateralVault;
    IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _PT = 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    address _USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        usdc = ERC20(_USDC); 
        IUSDC usdc_spoof = IUSDC(address(usdc));
        evc = new EthereumVaultConnector();
        vm.prank(usdc_spoof.masterMinter());
        // allow this test contract to mint USDC
        usdc_spoof.configureMinter(address(this), type(uint256).max);
        
        // mint $1000 USDC to the test contract (or an external user)
//        usdc_spoof.mint(address(this), 1000);

        //vm.warp(JUNE242024 - 90 days);
        aUSDCPT = IPPrincipalToken(_PT);
        //setup oracle
        oracle = new PtUsdOracle(0.1 hours, _market, address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));

        // Functional Oracle
        // new MockPtUsdOracle(1 days, address(0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5), address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3), address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1));
        
        // console.log(oracle.getPtPrice());
        collateralVault = new FixedYieldCollateralVault(evc, ERC20(address(aUSDCPT)));
        pool = new RepoVaultBorrowable(
            evc, usdc, address(collateralVault), address(aUSDCPT), address(oracle), _market);
        // pool = new RepoVault(address(usdc), address(aUSDCPT), _SY, _market, address(oracle));
        usdc_spoof.mint(lp, 1000 * DECIMALS);
        usdc_spoof.mint(UserWallet, 100 * DECIMALS);


    } 
    function test_deposits() public {
        vm.startPrank(lp);
        usdc.approve(address(pool), 100 * DECIMALS);
        pool.deposit(100 * DECIMALS, lp);
        // assertEq(pool.balanceOf(lp), 100 ether);
        // assertEq(usdc.balanceOf(lp), 0);
        // assertEq(usdc.balanceOf(address(pool)), 100 ether);
        vm.stopPrank();
    }
    function test_go_long() public {
        test_deposits();

        vm.startPrank(UserWallet);
        evc.enableController(UserWallet, address(pool));
        evc.enableCollateral(UserWallet, address(collateralVault));
        evc.enableCollateral(UserWallet, address(pool));
        usdc.approve(address(pool), 10000 * DECIMALS);
        pool.openTradeBaseForPT(
            100 * 10**6, // pt amount
            1 days, // term 
            99 * 10 ** 6, // min pt out
            UserWallet
        );
        vm.stopPrank();
        console.log("balance: ", usdc.balanceOf(UserWallet));
        assertGe(aUSDCPT.balanceOf(address(collateralVault)), 8 * 10 ** 5);
        console.log("PT Balance: ", aUSDCPT.balanceOf(address(collateralVault)));
        console.log("SY Balance: ", IStandardizedYield(_SY).balanceOf(address(pool)));
    }
    function test_liquidate_long() public {
        test_go_long();
        vm.warp(block.timestamp + 2 days);
        vm.startPrank(lp);
        evc.enableController(lp, address(pool));
        evc.enableCollateral(lp, address(collateralVault));
        usdc.approve(address(pool), 100 * DECIMALS);
        pool.liquidate(UserWallet, 1);
        console.log("balance: ", usdc.balanceOf(address(pool)));
    }
    function test_extend_a_long_financing_term() public {
        test_go_long();
        vm.startPrank(UserWallet);
        //pool.rolloverLoan(1, 5000000, 1 days);

        // Already Approved usdc 
        pool.renewRepoLoan(
            UserWallet,
            1,
            300000,
            2 days
        );
        vm.stopPrank();
    }
    function test_close_long() public {
        uint256 usd_balance = usdc.balanceOf(address(pool));
        test_go_long();
        vm.startPrank(UserWallet);
        pool.repurchaseAndSellPt(UserWallet, UserWallet, 1);
        uint256 usd_balance_after = usdc.balanceOf(address(pool));
        console.log("net balance change: ", usd_balance_after - usd_balance);
        // vm.stopPrank();
        // assertEq(aUSDCPT.balanceOf(UserWallet), 0);
    }
}
interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}
//$ forge create --rpc-url <your_rpc_url> --private-key <your_private_key> src/MyContract.sol:MyContract

//https://rpc.buildbear.io/persistent-siryn-0132e20a

// 

// Swap exact token for PT 0x851fA6b758d5b70551089b466FbAf69381b0d06e