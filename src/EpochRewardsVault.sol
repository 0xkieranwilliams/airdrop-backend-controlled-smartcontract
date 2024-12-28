// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title EpochRewardsVault
/// @author Kieran Williams
/// @notice Manages epoch-based rewards distribution with percentage-based allocation
/// @dev Inherits OpenZeppelin's Ownable for access control
contract EpochRewardsVault is Ownable{

  /// @notice Structure to track user rewards for each epoch
  /// @param poolPercentage User's percentage of the reward pool (0-100.0000)
  /// @param claimed Whether the user has claimed their reward for this epoch
  struct UserEpochPoolReward {
    uint256 poolPercentage; // 0 - 100.0000 (7 digit number, last 4 numbers are for decimal values)
    bool claimed;
  }

  /// @notice Initializes the contract with the deployer as owner
  /// @dev Uses OpenZeppelin's Ownable constructor
  constructor() Ownable(msg.sender){ }
  
  /// @notice Current epoch number
  uint256 public s_currentEpoch = 0;

  /// @notice Maximum allowed pool percentage per user (5.0000%)
  uint256 public s_maxUserPoolPercentage = 50000;

  /// @notice Maps epoch and user address to their reward information
  mapping(uint256 epoch => mapping(address user => UserEpochPoolReward)) s_userEpochRewards;

  /// @notice Total points allocated in each epoch
  mapping(uint256 epoch => uint256 totalPoints) s_totalPointsInEpoch;

  /// @notice Total balance available for distribution in each epoch
  mapping(uint256 epoch => uint256 epochDistributingBalance) s_epochDistributingBalance;

  /// @notice Emitted when a user claims their reward
  /// @param epoch The epoch number for which reward was claimed
  /// @param user Address of the user who claimed
  /// @param amount Amount of reward claimed
  event RewardClaimed(uint256 indexed epoch, address indexed user, uint256 amount);

  /// @notice Emitted when maximum user pool percentage is updated
  /// @param updatedValue New maximum percentage value
  event MaxUserPoolPercentageUpdate(uint256 updatedValue);

  /// @notice Emitted when a user is added to epoch rewards
  /// @param epoch The epoch number
  /// @param user Address of the user added
  /// @param poolPercentage Allocated pool percentage for the user
  event UserAddedToEpochRewards(uint256 indexed epoch, address indexed user, uint256 poolPercentage);

  /// @notice Updates the epoch number and sets new distribution parameters
  /// @param totalPointsInEpoch Total points to be considered for the new epoch
  /// @dev Increments current epoch and stores the total points and current balance
  function updateEpoch(uint256 totalPointsInEpoch) public payable onlyOwner {
    s_currentEpoch = s_currentEpoch + 1;
    s_totalPointsInEpoch[s_currentEpoch] = totalPointsInEpoch;
    s_epochDistributingBalance[s_currentEpoch] = getRewardVaultCurrentBalance();
  }

  /// @notice Adds or updates a user's reward allocation for a specific epoch
  /// @param user Address of the user to receive rewards
  /// @param poolPercentage Percentage of the pool allocated to the user
  function addUserToEpochRewards(address user, uint256 poolPercentage) public onlyOwner{
    require(!s_userEpochRewards[s_currentEpoch][user].claimed, "Can't add user after they have already been added and already claimed");
    s_userEpochRewards[s_currentEpoch][user] = UserEpochPoolReward({poolPercentage: poolPercentage, claimed: false});
    emit UserAddedToEpochRewards(s_currentEpoch, user, poolPercentage);
  }

  /// @notice Updates the maximum allowed pool percentage per user
  /// @param percentageValue New maximum percentage value (with 3 decimal places)
  function updateMaxUserPoolPercentage(uint256 percentageValue) public onlyOwner {
    s_maxUserPoolPercentage = percentageValue;
    emit MaxUserPoolPercentageUpdate(percentageValue);
  }

  /// @notice Allows users to claim their rewards for the current epoch
  /// @dev Validates eligibility, adjusts percentage if needed, and transfers rewards
  function claimReward() public {
      uint256 epoch = s_currentEpoch;
      UserEpochPoolReward storage userEpochPoolReward = s_userEpochRewards[epoch][msg.sender];
      
      // Check if the user has an entry for the given epoch
      require(userEpochPoolReward.poolPercentage > 0, "No rewards available for this user in this epoch");

      // Check if the reward has already been claimed
      require(!userEpochPoolReward.claimed, "Reward already claimed");

      // Adjust pool percentage if it exceeds the maximum allowed
      if (userEpochPoolReward.poolPercentage > s_maxUserPoolPercentage) {
          userEpochPoolReward.poolPercentage = s_maxUserPoolPercentage;
      }

      // Calculate the reward amount based on the user's pool percentage
      uint256 totalBalance = s_epochDistributingBalance[epoch];
      uint256 rewardAmount = (totalBalance * userEpochPoolReward.poolPercentage) / 1000000; // Pool percentage is stored as a 6-digit number with decimals

      // Ensure that there is enough balance to cover the reward
      require(getRewardVaultCurrentBalance() >= rewardAmount, "Insufficient contract balance to claim reward");

      // Update the claimed status
      userEpochPoolReward.claimed = true;

      // Transfer the reward to the user
      payable(msg.sender).transfer(rewardAmount);

      // Emit an event for the transfer
      emit RewardClaimed(epoch, msg.sender, rewardAmount);
  }

  /// @notice Returns the current balance of the contract
  /// @return Current balance in wei
  function getRewardVaultCurrentBalance() public view returns (uint256) {
    return address(this).balance;
  }

  /// @notice Returns all reward information for a user in a specific epoch
  /// @param epoch The epoch number to query
  /// @param user Address of the user
  /// @return poolPercentage User's pool percentage
  /// @return claimed Whether the reward has been claimed
  /// @return isEligible Whether user has any rewards allocated
  /// @return calculatedReward The reward amount user can claim (0 if already claimed)
  function getUserEpochReward(uint256 epoch, address user) public view returns (
      uint256 poolPercentage,
      bool claimed,
      bool isEligible,
      uint256 calculatedReward
  ) {
      UserEpochPoolReward memory reward = s_userEpochRewards[epoch][user];
      poolPercentage = reward.poolPercentage;
      claimed = reward.claimed;
      isEligible = reward.poolPercentage > 0;
      
      if (isEligible && !claimed) {
          uint256 adjustedPercentage = reward.poolPercentage > s_maxUserPoolPercentage ? 
              s_maxUserPoolPercentage : reward.poolPercentage;
          calculatedReward = (s_epochDistributingBalance[epoch] * adjustedPercentage) / 1000000;
      } else {
          calculatedReward = 0;
      }
  }

  /// @notice Returns total points and distributable balance for an epoch
  /// @param epoch The epoch number to query
  /// @return totalPoints Total points in the epoch
  /// @return distributingBalance Balance available for distribution
  function getEpochInfo(uint256 epoch) public view returns (
      uint256 totalPoints,
      uint256 distributingBalance
  ) {
      return (s_totalPointsInEpoch[epoch], s_epochDistributingBalance[epoch]);
  }

  /// @notice Checks if a user can claim rewards for the current epoch
  /// @param user Address of the user to check
  /// @return canClaim Whether the user can claim rewards
  /// @return reason Reason why user cannot claim (empty string if can claim)
  function canUserClaim(address user) public view returns (bool canClaim, string memory reason) {
      UserEpochPoolReward memory reward = s_userEpochRewards[s_currentEpoch][user];
      
      if (reward.poolPercentage == 0) {
          return (false, "No rewards allocated");
      }
      if (reward.claimed) {
          return (false, "Already claimed");
      }
      
      uint256 adjustedPercentage = reward.poolPercentage > s_maxUserPoolPercentage ? 
          s_maxUserPoolPercentage : reward.poolPercentage;
      uint256 rewardAmount = (s_epochDistributingBalance[s_currentEpoch] * adjustedPercentage) / 1000000;
      
      if (getRewardVaultCurrentBalance() < rewardAmount) {
          return (false, "Insufficient contract balance");
      }
      
      return (true, "");
  }
}
