// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {EpochRewardsVault} from "../src/EpochRewardsVault.sol";

contract EpochRewardsVaultTest is Test {
    EpochRewardsVault public vault;
    address public owner;
    address public alice;
    address public bob;
    address public carol;
    
    // Events for testing
    event RewardClaimed(uint256 indexed epoch, address indexed user, uint256 amount);
    event MaxUserPoolPercentageUpdate(uint256 updatedValue);
    event UserAddedToEpochRewards(uint256 indexed epoch, address indexed user, uint256 poolPercentage);

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        
        vm.startPrank(owner);
        vault = new EpochRewardsVault();
        vm.stopPrank();
    }

    /// @dev Test initial state after deployment
    function test_InitialState() public view {
        assertEq(vault.s_currentEpoch(), 0);
        assertEq(vault.s_maxUserPoolPercentage(), 50000);
        assertEq(vault.owner(), owner);
        assertEq(vault.getRewardVaultCurrentBalance(), 0);
    }

    /// @dev Test updating epoch with funds
    function test_UpdateEpoch() public {
        uint256 totalPoints = 1000;
        uint256 fundAmount = 10 ether;
        
        vm.deal(owner, fundAmount);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: fundAmount}(totalPoints);
        vm.stopPrank();

        (uint256 points, uint256 balance) = vault.getEpochInfo(1);
        assertEq(points, totalPoints);
        assertEq(balance, fundAmount);
        assertEq(vault.s_currentEpoch(), 1);
    }

    /// @dev Test adding user to epoch rewards
    function test_AddUserToEpochRewards() public {
        uint256 epoch = 1;
        uint256 poolPercentage = 2500; // 2.5%
        
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit UserAddedToEpochRewards(epoch, alice, poolPercentage);
        vault.addUserToEpochRewards(epoch, alice, poolPercentage);
        vm.stopPrank();

        (uint256 userPoolPercentage, bool claimed, bool isEligible,) = vault.getUserEpochReward(epoch, alice);
        assertEq(userPoolPercentage, poolPercentage);
        assertFalse(claimed);
        assertTrue(isEligible);
    }

    /// @dev Test updating max user pool percentage
    function test_UpdateMaxUserPoolPercentage() public {
        uint256 newMaxPercentage = 3000; // 3%
        
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit MaxUserPoolPercentageUpdate(newMaxPercentage);
        vault.updateMaxUserPoolPercentage(newMaxPercentage);
        vm.stopPrank();

        assertEq(vault.s_maxUserPoolPercentage(), newMaxPercentage);
    }

    /// @dev Test successful reward claim
    function test_ClaimReward() public {
        // Setup
        uint256 fundAmount = 10 ether;
        uint256 poolPercentage = 2500; // 2.5%
        vm.deal(owner, fundAmount);
        
        // Update epoch with funds
        vm.prank(owner);
        vault.updateEpoch{value: fundAmount}(1000);
        
        // Add user to rewards
        vm.prank(owner);
        vault.addUserToEpochRewards(1, alice, poolPercentage);
        
        // Calculate expected reward
        uint256 expectedReward = (fundAmount * poolPercentage) / 1000000; // Adjusted for 6 decimal places
        
        // Claim reward
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(1, alice, expectedReward);
        vault.claimReward();
        
        // Verify
        assertEq(alice.balance, expectedReward);
    }

    /// @dev Test claim reward with percentage exceeding max
    function test_ClaimRewardExceedingMax() public {
        uint256 fundAmount = 10 ether;
        uint256 poolPercentage = 75000; // 7.5% (exceeds max 5%)
        vm.deal(owner, fundAmount);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: fundAmount}(1000);
        vault.addUserToEpochRewards(1, alice, poolPercentage);
        vm.stopPrank();
        
        uint256 maxPercentage = vault.s_maxUserPoolPercentage();
        uint256 expectedReward = (fundAmount * maxPercentage) / 1000000;
        
        vm.prank(alice);
        vault.claimReward();
        
        assertEq(alice.balance, expectedReward);
    }

    /// @dev Test claiming with no rewards available
    function test_ClaimRewardNoRewards() public {
        vm.startPrank(bob);
        vm.expectRevert("No rewards available for this user in this epoch");
        vault.claimReward();
        vm.stopPrank();
    }

    /// @dev Test double claiming prevention
    function test_PreventDoubleClaim() public {
        uint256 fundAmount = 10 ether;
        uint256 poolPercentage = 2500;
        vm.deal(owner, fundAmount);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: fundAmount}(1000);
        vault.addUserToEpochRewards(1, alice, poolPercentage);
        vm.stopPrank();
        
        vm.startPrank(alice);
        vault.claimReward();
        vm.expectRevert("Reward already claimed");
        vault.claimReward();
        vm.stopPrank();
    }

    /// @dev Test getUserEpochReward view function
    function test_GetUserEpochReward() public {
        uint256 fundAmount = 10 ether;
        uint256 poolPercentage = 2500;
        vm.deal(owner, fundAmount);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: fundAmount}(1000);
        vault.addUserToEpochRewards(1, alice, poolPercentage);
        vm.stopPrank();
        
        (
            uint256 userPoolPercentage,
            bool claimed,
            bool isEligible,
            uint256 calculatedReward
        ) = vault.getUserEpochReward(1, alice);
        
        assertEq(userPoolPercentage, poolPercentage);
        assertFalse(claimed);
        assertTrue(isEligible);
        assertEq(calculatedReward, (fundAmount * poolPercentage) / 1000000);
    }

    /// @dev Test getEpochInfo view function
    function test_GetEpochInfo() public {
        uint256 fundAmount = 10 ether;
        uint256 totalPoints = 1000;
        vm.deal(owner, fundAmount);
        
        vm.prank(owner);
        vault.updateEpoch{value: fundAmount}(totalPoints);
        
        (uint256 points, uint256 balance) = vault.getEpochInfo(1);
        assertEq(points, totalPoints);
        assertEq(balance, fundAmount);
    }

    /// @dev Test canUserClaim view function
    function test_CanUserClaim() public {
        uint256 fundAmount = 10 ether;
        uint256 poolPercentage = 2500;
        vm.deal(owner, fundAmount);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: fundAmount}(1000);
        vault.addUserToEpochRewards(1, alice, poolPercentage);
        vm.stopPrank();
        
        (bool canClaim, string memory reason) = vault.canUserClaim(alice);
        assertTrue(canClaim);
        assertEq(reason, "");
        
        // Test after claiming
        vm.prank(alice);
        vault.claimReward();
        
        (bool canClaimAfter, string memory reasonAfter) = vault.canUserClaim(alice);
        assertFalse(canClaimAfter);
        assertEq(reasonAfter, "Already claimed");
    }

    /// @dev Test access control
    function test_OnlyOwnerFunctions() public {
        vm.startPrank(alice);
        
        vm.expectRevert();
        vault.updateEpoch(1000);
        
        vm.expectRevert();
        vault.addUserToEpochRewards(1, alice, 2500);
        
        vm.expectRevert();
        vault.updateMaxUserPoolPercentage(3000);
        
        vm.stopPrank();
    }

    /// @dev Fuzz test for addUserToEpochRewards
    function testFuzz_AddUserToEpochRewards(
        uint256 epoch,
        address user,
        uint256 percentage
    ) public {
        vm.assume(user != address(0));
        vm.assume(percentage > 0 && percentage <= 100000);
        
        vm.prank(owner);
        vault.addUserToEpochRewards(epoch, user, percentage);
        
        (uint256 userPoolPercentage,,bool isEligible,) = vault.getUserEpochReward(epoch, user);
        assertEq(userPoolPercentage, percentage);
        assertTrue(isEligible);
    }
    
    function test_ContractBalance() public {
        uint256 amount = 1 ether;
        address payable vaultAddress = payable(address(vault));
        vm.deal(vaultAddress, amount);
        assertEq(vault.getRewardVaultCurrentBalance(), amount);
    }

    function test_MultipleUserRewardsAndClaims() public {
        // Setup initial contract balance - 100 ETH for easy percentage calculations
        uint256 initialBalance = 100 ether;
        vm.deal(owner, initialBalance);

        // Setup test users with their allocated percentages
        address[] memory users = new address[](4);
        uint256[] memory percentages = new uint256[](4);
        uint256[] memory expectedRewards = new uint256[](4);
        uint256[] memory initialBalances = new uint256[](4);

        // Create test users
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");
        users[3] = makeAddr("user4");

        // Set up percentages (using 6 decimal places)
        percentages[0] = 5000;  // 5%
        percentages[1] = 3000;  // 3%
        percentages[2] = 2500;  // 2.5%
        percentages[3] = 1500;  // 1.5%

        // Calculate expected rewards with correct precision
        for(uint i = 0; i < users.length; i++) {
            expectedRewards[i] = (initialBalance * percentages[i]) / 1000000;
            vm.deal(users[i], 0); // Ensure they can receive ETH
            initialBalances[i] = users[i].balance;
        }

        // Initialize epoch with funds
        vm.startPrank(owner);
        vault.updateEpoch{value: initialBalance}(1000); // Total points don't affect reward calculation
        
        // Add all users to the epoch
        for(uint i = 0; i < users.length; i++) {
            vault.addUserToEpochRewards(1, users[i], percentages[i]);
            
            // Verify user was added correctly
            (uint256 poolPercentage, bool claimed, bool isEligible, uint256 calculatedReward) = 
                vault.getUserEpochReward(1, users[i]);
            
            assertEq(poolPercentage, percentages[i], "Pool percentage not set correctly");
            assertFalse(claimed, "Reward should not be claimed yet");
            assertTrue(isEligible, "User should be eligible");
            assertEq(calculatedReward, expectedRewards[i], "Calculated reward incorrect");
        }
        vm.stopPrank();

        // Verify total allocated percentage is 12%
        uint256 totalPercentage = 0;
        for(uint i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }
        assertEq(totalPercentage, 12000, "Total percentage should be 12%");

        // Have each user claim their reward
        for(uint i = 0; i < users.length; i++) {
            // Check claim eligibility
            (bool canClaim, string memory reason) = vault.canUserClaim(users[i]);
            assertTrue(canClaim, reason);

            // Perform claim
            vm.prank(users[i]);
            vm.expectEmit(true, true, false, true);
            emit RewardClaimed(1, users[i], expectedRewards[i]);
            vault.claimReward();

            // Verify user received correct amount
            assertEq(
                users[i].balance - initialBalances[i],
                expectedRewards[i],
                "User did not receive correct reward amount"
            );

            // Verify claim status
            (,bool claimed,,) = vault.getUserEpochReward(1, users[i]);
            assertTrue(claimed, "Claim status not updated");

            // Verify user cannot claim again
            vm.prank(users[i]);
            vm.expectRevert("Reward already claimed");
            vault.claimReward();
        }

        // Verify final contract balance
        uint256 expectedRemainingBalance = initialBalance;
        for(uint i = 0; i < expectedRewards.length; i++) {
            expectedRemainingBalance -= expectedRewards[i];
        }
        assertEq(
            vault.getRewardVaultCurrentBalance(),
            expectedRemainingBalance,
            "Contract balance incorrect after all claims"
        );
    }

    function test_InsufficientFunds_DrainedPool() public {
        uint256 initialBalance = 1 ether;
        uint256 percentage = 50000; // 5%
        uint256 expectedReward = (initialBalance * percentage) / 1000000; // 0.05 ether per person
        
        vm.deal(owner, initialBalance);
        
        // Setup epoch with initial balance
        vm.startPrank(owner);
        vault.updateEpoch{value: initialBalance}(1000);

        // We need exactly 20 users to claim exactly 1 ether total (100%)
        // Plus 1 more user who will fail to claim
        uint256 numUsers = 21;
        address[] memory users = new address[](numUsers);
        
        // Create and register all users
        for(uint i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string.concat("user", vm.toString(i)));
            vault.addUserToEpochRewards(1, users[i], percentage);
        }
        vm.stopPrank();

        // First 19 users claim (95% of pool)
        for(uint i = 0; i < 19; i++) {
            vm.prank(users[i]);
            vault.claimReward();
            console2.log(i, ". Balance: ", address(vault).balance);
        }

        // Verify balance after 19 claims
        uint256 balanceAfter19 = address(vault).balance;
        console2.log("Balance after 19 claims:", balanceAfter19);
        
        // 20th user claims (this should leave us with exactly 0)
        vm.prank(users[19]);
        vault.claimReward();

        // Verify balance after 20 claims
        uint256 remainingBalance = address(vault).balance;
        console2.log("Final balance:", remainingBalance);
        console2.log("Required for next claim:", expectedReward);
        
        // Now balance should be 0
        assertEq(remainingBalance, 0, "Balance should be zero after 20 claims");

        // 21st user tries to claim but fails
        vm.prank(users[20]);
        vm.expectRevert("Insufficient contract balance to claim reward");
        vault.claimReward();
    }

    // Test different percentage scenarios
    struct TestCase {
        address user;
        uint256 percentage;   // Input to contract (e.g., 5000 = 0.5%)
        uint256 expectedWei;  // Expected reward in wei
    }
    function test_PercentageCalculationAccuracy() public {
        // Setup epoch with 100 ether for easy percentage calculations
        uint256 initialBalance = 100 ether;
        vm.deal(owner, initialBalance);
        
        vm.startPrank(owner);
        vault.updateEpoch{value: initialBalance}(1000);


        TestCase[] memory testCases = new TestCase[](5);
        
        // Case 1: Maximum percentage (0.5%)
        testCases[0] = TestCase({
            user: makeAddr("user1"),
            percentage: 5000,
            expectedWei: initialBalance * 5000 / 1000000 // 0.5% of 100 ether
        });

        // Case 2: Half of maximum (0.25%)
        testCases[1] = TestCase({
            user: makeAddr("user2"),
            percentage: 2500,
            expectedWei: initialBalance * 2500 / 1000000 // 0.25% of 100 ether
        });

        // Case 3: Minimum percentage (0.001%)
        testCases[2] = TestCase({
            user: makeAddr("user3"),
            percentage: 10,
            expectedWei: initialBalance * 10 / 1000000 // 0.001% of 100 ether
        });

        // Case 4: Random percentage (0.123%)
        testCases[3] = TestCase({
            user: makeAddr("user4"),
            percentage: 1230,
            expectedWei: initialBalance * 1230 / 1000000 // 0.123% of 100 ether
        });

        // Case 5: Another random percentage (0.333%)
        testCases[4] = TestCase({
            user: makeAddr("user5"),
            percentage: 3330,
            expectedWei: initialBalance * 3330 / 1000000 // 0.333% of 100 ether
        });

        // Register all users
        for(uint i = 0; i < testCases.length; i++) {
            TestCase memory tc = testCases[i];
            vault.addUserToEpochRewards(1, tc.user, tc.percentage);
        }
        vm.stopPrank();

        // Verify and claim for each user
        for(uint i = 0; i < testCases.length; i++) {
            TestCase memory tc = testCases[i];
            
            // Get user reward info
            (uint256 poolPercentage, bool claimed, bool isEligible, uint256 calculatedReward) = 
                vault.getUserEpochReward(1, tc.user);
            
            // Verify registration
            assertEq(poolPercentage, tc.percentage, "Wrong pool percentage stored");
            assertFalse(claimed, "Should not be claimed");
            assertTrue(isEligible, "Should be eligible");
            
            // Verify calculated reward matches expected
            assertEq(
                calculatedReward, 
                tc.expectedWei, 
                string.concat(
                    "Incorrect reward calculation for user", 
                    vm.toString(i),
                    ": expected ",
                    vm.toString(tc.expectedWei),
                    " but got ",
                    vm.toString(calculatedReward)
                )
            );

            // Now claim and verify actual received amount
            vm.prank(tc.user);
            uint256 balanceBefore = tc.user.balance;
            vault.claimReward();
            uint256 actualReward = tc.user.balance - balanceBefore;
            
            // Verify received amount matches expected
            assertEq(
                actualReward, 
                tc.expectedWei, 
                string.concat(
                    "Incorrect reward received for user", 
                    vm.toString(i),
                    ": expected ",
                    vm.toString(tc.expectedWei),
                    " but got ",
                    vm.toString(actualReward)
                )
            );

            // Log results in separate lines
            console2.log("User", i);
            console2.log("- Percentage:");
            console2.log((tc.percentage * 100) / 1_000_000, ".", (tc.percentage * 100_000) / 1_000_000 % 1000, "%");
            console2.log("- Expected Wei:", tc.expectedWei);
            console2.log("- Actual Wei:", actualReward);
            console2.log("--------------------");}

        // Verify final contract balance
        uint256 expectedRemainingBalance = initialBalance;
        for(uint i = 0; i < testCases.length; i++) {
            expectedRemainingBalance -= testCases[i].expectedWei;
        }
        assertEq(
            vault.getRewardVaultCurrentBalance(),
            expectedRemainingBalance,
            "Contract final balance incorrect"
        );
    }
}
