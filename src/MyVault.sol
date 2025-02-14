// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import { IWETH } from "src/interface/IWETH.sol";

contract MyVault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    // Immutable WETH address
    address public immutable weth;

    // Roles
    bytes32 public constant VAULT_ADMIN = keccak256("VAULT_ADMIN");
    bytes32 public constant FEE_MANAGER = keccak256("FEE_MANAGER");

    // LIDO staking contract address
    address public lidoStakingContract;

    // Fee in basis points (e.g., 100 = 1%)
    uint256 public feeBasisPoints;

    // Custom errors
    error InvalidAddress();
    error InvalidFee();
    error InsufficientBalance();

    // Disable initializers in the constructor
    constructor(address _weth) {
        if (_weth == address(0)) revert InvalidAddress();
        weth = _weth;
        _disableInitializers();
    }

    /// @notice Initializes the contract after deployment
    /// @param _admin The admin address for AccessControl
    /// @param _lidoStakingContract The address of the LIDO staking contract
    /// @param _feeBasisPoints The fee in basis points (e.g., 100 = 1%)
    function initialize(
        address _admin,
        address _lidoStakingContract,
        uint256 _feeBasisPoints
    ) external initializer {
        if (_admin == address(0)) revert InvalidAddress();
        if (_lidoStakingContract == address(0)) revert InvalidAddress();
        if (_feeBasisPoints > 10000) revert InvalidFee(); // Fee cannot exceed 100%

        __ERC4626_init(IERC20Upgradeable(weth)); // Initialize ERC4626 with WETH as the underlying asset
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(VAULT_ADMIN, _admin);
        _grantRole(FEE_MANAGER, _admin);

        lidoStakingContract = _lidoStakingContract;
        feeBasisPoints = _feeBasisPoints;
    }

    /// @notice Converts WETH to ETH and stakes it on LIDO (internal)
    function _stakeWETH(uint256 amount) internal nonReentrant {
        // Convert WETH to ETH
        IWETH(weth).withdraw(amount);

        // Stake ETH on LIDO (replace with actual LIDO staking logic)
        (bool success, ) = lidoStakingContract.call{value: amount}("");
        require(success, "Staking failed");
    }

    /// @notice Withdraws ETH from LIDO and converts it back to WETH (internal)
    function _unstakeETH(uint256 amount) internal nonReentrant {
        // Withdraw ETH from LIDO (replace with actual LIDO unstaking logic)
        (bool success, ) = lidoStakingContract.call(abi.encodeWithSignature("withdraw(uint256)", amount));
        require(success, "Unstaking failed");

        // Convert ETH to WETH
        IWETH(weth).deposit{value: amount}();
    }

    /// @notice Override ERC4626 previewRedeem to account for staking rewards
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        // Calculate total assets including staking rewards
        uint256 totalAssets = IERC20Upgradeable(weth).balanceOf(address(this)) + address(this).balance;
        return (shares * totalAssets) / totalSupply();
    }

    /// @notice Set the fee basis points (only callable by FEE_MANAGER)
    function setFeeBasisPoints(uint256 _feeBasisPoints) external onlyRole(FEE_MANAGER) {
        if (_feeBasisPoints > 10000) revert InvalidFee();
        feeBasisPoints = _feeBasisPoints;
    }

    /// @notice Get the current fee basis points
    function getFeeBasisPoints() external view returns (uint256) {
        return feeBasisPoints;
    }

    /// @notice Required by UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(VAULT_ADMIN) {}

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}