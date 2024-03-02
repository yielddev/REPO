// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.20;
import "forge-std/Script.sol";
contract faucet is Script {
    // IPPrincipalToken public aUSDCPT;
    // PtUsdOracle public oracle;
    // // RepoVault public pool;
    // FixedYieldCollateralVault public collateralVault;
    // RepoVaultBorrowable public pool;
    // RepoPlatformOperator public operator;
    uint256 JUNE242024 = 1719248606;
    uint256 DECIMALS = 10**6;
   //  IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _PT = 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    address _USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    function run() public {
        //uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC"), 0);
        address deployerWallet = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        IUSDC usdc_spoof = IUSDC(address(usdc));
        console.log(usdc_spoof.masterMinter());
        // vm.startBroadcast(usdc_spoof.masterMinter());
        usdc_spoof.configureMinter(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), type(uint256).max);

        // usdc_spoof.configureMinter(address(this), type(uint256).max);
        // vm.stopBroadcast();
        // vm.startBroadcast(address(this));
        //usdc_spoof.mint(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 100 * DECIMALS);
        // vm.stopBroadcast();

        // usdc_spoof.mint(address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8), 1000 * DECIMALS);
        // // usdc_spoof.mint(UserWallet, 100 * DECIMALS);

    }
}
interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}