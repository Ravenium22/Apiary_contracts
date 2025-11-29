Here is how I envision it:
-Staking mints new token each epoch at the rebase rate we decide and we can change it in the future so we can lower it and eventually get it to zero
-Bonds have fixed discounts on the BRR market price, we decide these discounts and we can change them whenever we want
-When the bonds are sold out (all the 20% allocated to treasury) we can decide to do a second round of bonds, minting new tokens for the treasury


🔒 Staking Invariants
	1.	New tokens are only minted during rebase epochs.
	2.	Rebase rate used for staking must be the currently set value (can be updated).
	3.	Total supply increases only by the rebase amount during staking epochs.
	4.	If the rebase rate is set to zero, staking should no longer mint tokens.

⸻

💸 Bonding Invariants
	5.	Bond discount is applied relative to the current BRR market price.
	6.	Discount rates for bonds can be updated at any time (by authorized roles only).
	7.	The total amount of BRR sold via bonds must not exceed the 20% cap unless explicitly increased.
	8.	Each bond purchase results in minting of BRR equal to the bond terms.

⸻

🔁 Bond Round Invariants
	9.	A second bond round can only start after the first 20% allocation is sold out.
	10.	Second bond round must also explicitly mint new BRR for the treasury.
	11.	Bond rounds cannot overlap (i.e., second round can’t start before the first is fully sold).