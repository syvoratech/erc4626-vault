// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/MyVault.sol";
import "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract MyVaultTest is Test {
    MyVault public vault;
    address public admin = address(1);
    address public user = address(2);
    address public feeManager = address(3);

    IERC20 public weth;
    ILido public lido;
    IWithdrawalQueueERC721 public withdrawalQueue;

    uint256 public sepoliaFork;
    uint256 public constant DEPOSIT_AMOUNT = 1e18;

    function setUp() public {
        // Create a fork and select it.
        string memory sepoliaUrl = vm.envString("SEPOLIA_RPC_URL");
        uint256 blockNumber = vm.envUint("BLOCK_NUMBER");
        sepoliaFork = vm.createFork(sepoliaUrl, blockNumber);
        vm.selectFork(sepoliaFork);

        // Get environment addresses.
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address lidoAddress = vm.envAddress("LIDO_STETH_ADDRESS");
        address withdrawalQueueAddress = vm.envAddress(
            "WITHDRAWAL_QUEUE_ADDRESS"
        );

        weth = IERC20(wethAddress);
        lido = ILido(lidoAddress);
        withdrawalQueue = IWithdrawalQueueERC721(withdrawalQueueAddress);

        MyVault myVaultImpl = new MyVault(wethAddress);

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(myVaultImpl),
            abi.encodeWithSelector(
                MyVault.initialize.selector,
                admin,
                lidoAddress,
                withdrawalQueueAddress,
                100
            )
        );
        vault = MyVault(payable(address(proxy)));

        vm.startPrank(admin);
        vault.grantRole(vault.FEE_MANAGER(), feeManager);
        vm.stopPrank();

        deal(address(vault), 1 ether);
        deal(address(weth), user, DEPOSIT_AMOUNT * 100);
    }

    function test_Deposit() public {
        vm.startPrank(user);
        weth.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 expectedShares = vault.previewDeposit(DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        assertEq(
            vault.balanceOf(user),
            expectedShares,
            "Shares should be minted 1:1"
        );
        assertEq(
            weth.balanceOf(address(vault)),
            0,
            "WETH should be converted to ETH"
        );

        uint256 stETHBalance = IERC20(address(lido)).balanceOf(address(vault));
        assertApproxEqAbs(
            stETHBalance,
            expectedShares,
            expectedShares / 100,
            "stETH should be received"
        );
    }

    // function test_Redeem() public {
    //     test_Deposit();
    //     uint256 shares = vault.balanceOf(user);

    //     vm.startPrank(user);
    //     vm.expectRevert("ERC20: transfer amount exceeds balance");
    //     vault.redeem(shares, user, user);
    //     vm.stopPrank();
    // }

    function test_SetFee() public {
        vm.prank(feeManager);
        vault.setFeeBasisPoints(200);
        assertEq(vault.getFeeBasisPoints(), 200, "Fee should update");

        vm.prank(feeManager);
        vm.expectRevert(MyVault.InvalidFee.selector);
        vault.setFeeBasisPoints(10001);
    }

    function test_Upgrade() public {
        address newVault = address(new MyVault(address(weth)));
        vm.prank(admin);
        vault.upgradeToAndCall(address(newVault), "");

        vm.prank(user);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newVault), "");
    }

    function test_ReceiveETH() public {
        uint256 initialEthBalance = address(vault).balance;
        (bool success, ) = address(vault).call{value: 1e18}("");
        assertTrue(success, "ETH should be received");
        assertEq(
            address(vault).balance,
            1e18 + initialEthBalance,
            "ETH balance should update"
        );
    }

    function test_RevertInitialization() public {
        MyVault newVault = new MyVault(address(weth));
        bytes memory initData = abi.encodeWithSelector(
            MyVault.initialize.selector,
            address(user),
            address(lido),
            address(withdrawalQueue),
            100
        );
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.startPrank(admin);
        vault.upgradeToAndCall(address(newVault), initData);
    }

    function test_RoleGrants() public {
        address newAdmin = address(4);
        bytes32 adminRole = vault.VAULT_ADMIN();
        // Admin should be able to grant roles
        vm.prank(admin);
        vault.grantRole(adminRole, newAdmin);
        assertTrue(vault.hasRole(vault.VAULT_ADMIN(), newAdmin));

        // Non-admin should fail to grant roles
        vm.prank(user);
        vm.expectRevert();
        vault.grantRole(adminRole, newAdmin);
    }

    // function test_FeeDeduction() public {
    //     // Setup initial deposit
    //     test_Deposit();
    //     uint256 shares = vault.balanceOf(user);

    //     // Set 10% fee
    //     vm.prank(feeManager);
    //     vault.setFeeBasisPoints(1000);

    //     vm.prank(user);
    //     uint256 received = vault.redeem(shares, user, user);

    //     uint256 expectedFee = (DEPOSIT_AMOUNT * 1000) / 10000;
    //     assertEq(
    //         received,
    //         DEPOSIT_AMOUNT - expectedFee,
    //         "Fee not deducted correctly"
    //     );
    //     assertEq(
    //         weth.balanceOf(address(vault)),
    //         expectedFee,
    //         "Fee not retained in vault"
    //     );
    // }

    function test_RevertMaxUintDeposit() public {
        uint256 maxAmount = type(uint256).max;
        deal(address(weth), user, maxAmount);
        deal(address(weth), maxAmount);

        vm.startPrank(user);
        weth.approve(address(vault), maxAmount);
        vm.expectRevert();
        vault.deposit(maxAmount, user);
        vm.stopPrank();
    }

    // function test_FullWithdrawalFlow() public {
    //     test_Deposit();
    //     uint256 shares = vault.balanceOf(user);

    //     // Simulate Lido withdrawal finalization
    //     uint256 requestId = 123;
    //     vm.mockCall(
    //         address(withdrawalQueue),
    //         abi.encodeWithSelector(
    //             IWithdrawalQueueERC721.claimWithdrawal.selector
    //         ),
    //         abi.encode()
    //     );

    //     vm.prank(user);
    //     vault.redeem(shares, user, user);

    //     // Verify ETH conversion back to WETH
    //     assertGt(weth.balanceOf(user), 0, "Withdrawal conversion failed");
    // }

    function test_AssetConversionRates() public {
        test_Deposit();
        uint256 expectedShares = DEPOSIT_AMOUNT - 0.02 ether; // 0.02 eth is the gas buffer amount
        // Test conversion functions
        assertEq(
            vault.previewDeposit(DEPOSIT_AMOUNT),
            expectedShares,
            "Deposit preview mismatch"
        );

        uint256 grossStETH = (DEPOSIT_AMOUNT * lido.balanceOf(address(vault))) /
            vault.totalSupply();
        uint256 expectedETHBeforeFee = lido.getPooledEthByShares(grossStETH);
        uint256 expectedETHAfterFee = (expectedETHBeforeFee * (10000 - 100)) /
            10000;
        assertEq(
            vault.previewMint(DEPOSIT_AMOUNT),
            expectedETHAfterFee,
            "Mint preview mismatch"
        );

        uint256 netETHForDeposit = DEPOSIT_AMOUNT - 0.02 ether; // 0.02 eth is the gas buffer amount
        expectedShares =
            (netETHForDeposit * vault.totalSupply()) /
            lido.balanceOf(address(vault));
        assertEq(
            vault.previewWithdraw(DEPOSIT_AMOUNT),
            expectedShares,
            "Withdraw preview mismatch"
        );
    }

    function test_StatePreservationAfterUpgrade() public {
        test_Deposit();
        uint256 expectedShares = DEPOSIT_AMOUNT - 0.02 ether; // 0.02 eth is the gas buffer amount
        address newImplementation = address(new MyVault(address(weth)));

        vm.prank(admin);
        vault.upgradeToAndCall(newImplementation, "");

        // Verify state preservation
        assertEq(
            vault.totalSupply(),
            expectedShares,
            "Total supply mismatch after upgrade"
        );
        assertEq(
            vault.balanceOf(user),
            expectedShares,
            "User balance mismatch after upgrade"
        );
    }

    function test_ETHConversionMechanism() public {
        uint256 ethAmount = 1 ether;
        deal(address(this), ethAmount);

        (bool success, ) = address(vault).call{value: ethAmount}("");
        assertTrue(success, "ETH transfer did not failed");

        // Verify any ETH received does not automatically gets converted to WETH
        assertEq(weth.balanceOf(address(vault)), 0, "WETH balance mismatch");
    }
}
