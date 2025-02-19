// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts/interfaces/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";

import {IWETH} from "src/interfaces/IWETH.sol";
import {ILido} from "src/interfaces/ILido.sol";
import {IWithdrawalQueueERC721} from "src/interfaces/IWithdrawalQueueERC721.sol";

contract MyVault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Immutable WETH address
    IERC20 public immutable weth;

    // Roles
    bytes32 public constant VAULT_ADMIN = keccak256("VAULT_ADMIN");
    bytes32 public constant FEE_MANAGER = keccak256("FEE_MANAGER");

    // LIDO staking & withdrawal contracts
    ILido public lido;
    IWithdrawalQueueERC721 public withdrawalQueue;

    // Fee in basis points (e.g., 100 = 1%)
    uint256 public feeBasisPoints;

    // Events
    event WithdrawalRequested(address indexed user, uint256[] requestIds);
    event ETHClaimed(address indexed user, uint256 amount, uint256 requestId);

    // Custom errors
    error InvalidAddress();
    error InvalidFee();
    error InsufficientBalance();

    // Disable initializers in the constructor
    constructor(address _weth) {
        if (_weth == address(0)) revert InvalidAddress();
        weth = IERC20(_weth);
        _disableInitializers();
    }

    /// @notice Initializes the contract after deployment
    /// @param _admin The admin address for AccessControl
    /// @param _lido The address of the LIDO staking contract
    /// @param _feeBasisPoints The fee in basis points (e.g., 100 = 1%)
    function initialize(
        address _admin,
        address _lido,
        address _withdrawalQueue,
        uint256 _feeBasisPoints
    ) external initializer {
        if (_admin == address(0)) revert InvalidAddress();
        if (_lido == address(0)) revert InvalidAddress();
        if (_withdrawalQueue == address(0)) revert InvalidAddress();
        if (_feeBasisPoints > 10000) revert InvalidFee(); // Fee cannot exceed 100%

        __ERC4626_init(IERC20(weth)); // Initialize ERC4626 with WETH as the underlying asset
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(VAULT_ADMIN, _admin);
        _grantRole(FEE_MANAGER, _admin);

        lido = ILido(_lido);
        withdrawalQueue = IWithdrawalQueueERC721(_withdrawalQueue);
        feeBasisPoints = _feeBasisPoints;
    }

    /// @notice Converts WETH to ETH and stakes it on LIDO (internal)
    function _stakeWETH(uint256 amount) internal returns (uint256) {
        weth.transferFrom(msg.sender, address(this), amount);
        IWETH(address(weth)).withdraw(amount);

        // Reserve a buffer for the Lido submit call, 200,000 gas * 100 gwei = 200,000 * 100e-9 ETH = 0.02 ETH.
        uint256 gasBuffer = 200000 * 100 gwei;
        require(amount > gasBuffer, "Amount too low to cover gas buffer");

        uint256 balanceBefore = address(this).balance;
        uint256 netAmount = amount - gasBuffer;
        uint256 stETHReceived = lido.submit{value: netAmount}(address(0));

        uint256 balanceAfter = address(this).balance;
        uint256 remaining = balanceAfter + amount - balanceBefore;
        if (remaining > 0) {
            (bool success, ) = payable(msg.sender).call{value: remaining}("");
            require(success, "Refund failed");
        }

        return stETHReceived;
    }

    /// @notice Withdraws ETH from LIDO and converts it back to WETH (internal)
    function _unstakeETH(uint256 amount) internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        lido.approve(address(withdrawalQueue), amount);
        uint256[] memory requestIds = withdrawalQueue.requestWithdrawals(
            amounts,
            address(this)
        );
        emit WithdrawalRequested(msg.sender, requestIds);

        withdrawalQueue.claimWithdrawal(requestIds[0]);
        emit ETHClaimed(msg.sender, amount, requestIds[0]);
    }

    /// @notice Override ERC4626 deposit to stake WETH automatically
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256) {
        require(assets > 0, "Invalid amount");

        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        _stakeWETH(assets);

        uint256 shares = previewDeposit(assets);
        _mint(receiver, shares);
        emit Deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /// @notice Override ERC4626 redeem to unstake ETH and deduct fees
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256) {
        require(shares > 0, "Invalid shares");

        // Calculate the amount of WETH to withdraw based on shares
        uint256 assets = previewRedeem(shares);

        // Burn shares from the owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        // Unstake ETH from LIDO
        _unstakeETH(assets);

        // Deduct fees from the profit
        uint256 fee = (assets * feeBasisPoints) / 10000;
        uint256 amountAfterFee = assets - fee;

        // Transfer WETH to the receiver
        IERC20(weth).safeTransfer(receiver, amountAfterFee);

        return amountAfterFee;
    }

    /// @notice Mint: Users specify a desired number of shares to receive.
    /// The required assets are computed (including the fixed gas buffer).
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override returns (uint256) {
        require(shares > 0, "Invalid shares");

        uint256 supply = totalSupply();
        uint256 gasBuffer = 200000 * 100 gwei;
        uint256 requiredAssets;
        if (supply == 0) {
            // For the first deposit, shares equal net assets so:
            requiredAssets = shares + gasBuffer;
        } else {
            // In deposit we do:
            //   shares = (assets - gasBuffer) * supply / _totalAssets()
            // Solve for assets: assets = (shares * _totalAssets()) / supply + gasBuffer
            requiredAssets = (shares * _totalAssets()) / supply + gasBuffer;
        }

        uint256 maxAssets = maxDeposit(receiver);
        if (requiredAssets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(
                receiver,
                requiredAssets,
                maxAssets
            );
        }

        _stakeWETH(requiredAssets);

        _mint(receiver, shares);
        emit Deposit(_msgSender(), receiver, requiredAssets, shares);
        return requiredAssets;
    }

    /// @notice Withdraw: Users specify the desired net asset amount (WETH) they want to receive.
    /// The vault computes the required shares, burns them, unstakes the ETH from Lido, deducts fees,
    /// and transfers the net assets.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(assets > 0, "Invalid assets");

        uint256 shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        // Unstake the requested gross asset amount from Lido.
        _unstakeETH(assets);

        // Deduct fees from the gross amount.
        uint256 fee = (assets * feeBasisPoints) / 10000;
        uint256 amountAfterFee = assets - fee;

        // Transfer the resulting asset (WETH) to the receiver.
        IERC20(weth).safeTransfer(receiver, amountAfterFee);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function _totalAssets() internal view returns (uint256) {
        return lido.balanceOf(address(this));
    }

    /// @notice Converts a given amount of underlying assets (WETH) to vault shares,
    ///         taking into account the gas buffer that will be deducted at deposit.
    ///         Note that the deposit function will require assets > gasBuffer.
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 gasBuffer = 200000 * 100 gwei;
        require(assets > gasBuffer, "Assets must exceed gas buffer");

        uint256 netAssets = assets - gasBuffer;

        uint256 supply = totalSupply();
        if (supply == 0) {
            return netAssets;
        } else {
            return (netAssets * supply) / _totalAssets();
        }
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 stETHBalance = IERC20(address(lido)).balanceOf(address(this));
        uint256 grossStETH = (shares * stETHBalance) / supply;

        uint256 expectedETH = lido.getPooledEthByShares(grossStETH);
        uint256 fee = (expectedETH * feeBasisPoints) / 10000;

        return expectedETH - fee;
    }

    /// @notice Set the fee basis points (only callable by FEE_MANAGER)
    function setFeeBasisPoints(
        uint256 _feeBasisPoints
    ) external onlyRole(FEE_MANAGER) {
        if (_feeBasisPoints > 10000) revert InvalidFee();
        feeBasisPoints = _feeBasisPoints;
    }

    /// @notice Get the current fee basis points
    function getFeeBasisPoints() external view returns (uint256) {
        return feeBasisPoints;
    }

    /// @notice Required by UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(VAULT_ADMIN) {}

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
