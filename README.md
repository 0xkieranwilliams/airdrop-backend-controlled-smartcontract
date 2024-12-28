# airdrop-backend-controlled-smartcontract

- Epoch based
- Backend owner account controls:
    - updateEpoch() - payable: to add funds for the new epoch
    - updateMaxUserPoolPercentage()
    - addUserToEpochRewards()

- User that has rewards to claim can claim the rewards via:
    - claimReward()
