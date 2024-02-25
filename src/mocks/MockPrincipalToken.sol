// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPPrincipalToken } from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";

contract MockPrincipalToken is IPPrincipalToken, ERC20 {
    // Should inherit PendleERC20Permit token instead
    address public immutable SY;
    address public immutable factory;
    uint256 public immutable expiry;
    address public YT;
    constructor(
        address _SY,
        string memory _name,
        string memory _symbol,
        uint8 __decimals,
        uint256 _expiry
    ) ERC20(_name, _symbol) {
        SY = _SY;
        expiry = _expiry;
        factory = msg.sender;
    }

    function isExpired() external view override returns (bool) {
        return block.timestamp > expiry;
    }
    function burnByYT(address user, uint256 amount) external override {
        _burn(user, amount);
    }
    function initialize(address _YT) external override {
        YT = _YT;
    }
    function mintByYT(address user, uint256 amount) external override {
        _mint(user, amount);
    }

}