// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockUSDC } from "../src/mocks/MockUSDC.sol";
import { RepoVault } from "../src/RepoVault.sol";
import { RepoVaultBorrowable } from "../src/RepoVaultBorrowable.sol";
import { FixedYieldCollateralVault } from "../src/FixedYieldCollateralVault.sol";
import { PtCollateralVault } from "../src/PtCollateralVault.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import { MockPrincipalToken } from "../src/mocks/MockPrincipalToken.sol";
import { PtUsdOracle } from "../src/PtUsdOracle.sol";
import { IPtUsdOracle } from "../src/interfaces/IPtUsdOracle.sol";
import { MockPtUsdOracle } from "../src/mocks/MockPtUsdOracle.sol";
import { RepoPlatformOperator } from "../src/RepoPlatformOperator.sol";
import "evc/EthereumVaultConnector.sol";
import "forge-std/console.sol";

// PT-wstETH-28MAR24	0x5A4e68E1F82dD4eAFBda13e47E0EC3cc452ED521	
// SY-wstETH	0x80c12D5b6Cc494632Bf11b03F09436c8B61Cc5Df
// PT-wstETH-28MAR24/SY-wstETH Market	0x58F50De493B6bE3585558F95F208dE489C296E24
// wstETH 0x5979D7b546E38E414F7E9822514be443A4800529
contract RepoVaultTestWSTETH is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public Liquidator;
    address public lp;
    wstETH public wsteth;
    RepoVaultBorrowable public pool;
    IPPrincipalToken public wstethPT;
    MockPtUsdOracle public oracle;
    FixedYieldCollateralVault public collateralVault;
    RepoPlatformOperator public operator;

    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
    uint256 CENTS = 10**4;
    IEVC evc;
    address BASEASSET = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address BRIDGE = 0x07D4692291B9E30E326fd31706f686f83f331B82;
    address _SY = 0x80c12D5b6Cc494632Bf11b03F09436c8B61Cc5Df;
    address _PT = 0x5A4e68E1F82dD4eAFBda13e47E0EC3cc452ED521;
    address _market = 0x58F50De493B6bE3585558F95F208dE489C296E24;


    error REPO__MaxLoanExceeded();
    function mintWSTETH(address to, uint256 amount) public {
       vm.prank(BRIDGE);
       wsteth.bridgeMint(to, amount);
    }
    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        Liquidator = address(42100000000055005);
        wstethPT = IPPrincipalToken(_PT);
        oracle = new MockPtUsdOracle();

        wsteth = wstETH(BASEASSET);

       

        evc = new EthereumVaultConnector();
        collateralVault = new FixedYieldCollateralVault(evc, ERC20(address(wstethPT)));
        pool = new RepoVaultBorrowable(
            evc,
            IERC20(address(BASEASSET)),
            address(collateralVault),
            _PT,
            address(oracle),
            _market
        );
        pool.setEPS(10**18);
    }
    function test_deposit() public {
        mintWSTETH(lp, 100 ether);
        vm.startPrank(lp);
        wsteth.approve(address(pool), 100 ether);
        pool.deposit(100 ether, lp);
        vm.stopPrank();
        assertEq(pool.balanceOf(lp), 100 ether);
        assertEq(wsteth.balanceOf(address(pool)), 100 ether);
        assertEq(pool.totalAssets(), 100 ether);
    }
    function test_go_long() public {
        mintWSTETH(UserWallet, 100 ether);
        test_deposit();
        vm.startPrank(UserWallet);
        evc.enableController(UserWallet, address(pool));
        evc.enableCollateral(UserWallet, address(collateralVault));
        evc.enableCollateral(UserWallet, address(pool));
        wsteth.approve(address(pool), 1 ether);
        uint256 preBalance = wsteth.balanceOf(UserWallet);
        pool.openTradeBaseForPT(
            1 ether, // stethPt to long
            1 days,
            0.999999 ether, // min stethPt to long
            UserWallet
        );
        vm.stopPrank();
        (uint256 exposure, uint256 loan, ) = pool.getRepoLoan(UserWallet, 1);
        console.log("exposure: ", exposure);
        console.log("loan: ", loan);
        console.log("userInitial: ", preBalance - wsteth.balanceOf(UserWallet));    
        uint256 totalCost = (preBalance - wsteth.balanceOf(UserWallet)) + loan;
        console.log("totalCost: ", totalCost); // totalSteth cost of position 
        uint256 pricePaid = totalCost* 1 ether / exposure;
        console.log("pricePaid: ", pricePaid);


    }


}

interface wstETH is IERC20 {
    function bridgeMint(address account_, uint256 amount_) external;
}