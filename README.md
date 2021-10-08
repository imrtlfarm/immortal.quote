# immortal.quote
Not fully tested version of immortal farm contracts for solidity.finance to get an idea of the scope of the project.  The only unique piece is the eqv.sol file, the rest are taken from elsewhere.

Deposit and Farm
User Deposits FTM
Fund TVL is calculated using tarot oracle for LP prices in units of FTM
Fair Sh	are price is calculated (TVL/# of outstanding shares), still in FTM units
User is minted Share Price*FTM deposited shares
Deposited FTM is traded into tokens which are used to create LP tokens, according to the stated distribution of the vault.
Note, this distribution is according to prices at the time of deposit
These LP tokens are deposited into the corresponding Dex masterchef contract(s).
Every XX minutes, the interest (in the form of a Dex token), is harvested and traded into the same LP tokens and redeposited, compounding the user’s position
Note, this distribution is according to prices at the time of each compound
We charge a 4.5% fee on every compound

Withdraw
The user calls the withdraw function, passing the amount of shares they wish to withdraw as an argument, if there is no argument passed, then all shares will be withdrawn
If there is enough accumulated interest to compound, the fund will compound.
Each share withdrawn entitles the user to (Shares Withdrawn/# of outstanding shares) proportion of each LP position, at the time of withdrawal.
These proportions of each LP position are withdrawn and sold to FTM, which is transferred back to the user.
We charge a 0.1% withdrawal fee

