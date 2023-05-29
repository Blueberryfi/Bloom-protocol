# The Billy Pool Protocol

> The name "Billy" comes from T-Bills because idk, "billy" sounds funny? Name is WIP, change at your
> discretion.


## The [`BillyPool`](src/BillyPool.sol) Contract

The BillyPool smart contract enables lenders and borrowers to deposit stablecoins and swap them for
tokenized treasuries. Borrowers need to be whitelisted and earn a spread compared to lenders.
Borrowers are also the first in line to carry losses or gains from swapping to and from treasuries.

Lender claims are fungible and tradeable as ERC20 tokens.

### Deposit

Lenders and borrowers are matched on a first-come-first-serve basis. Once the commit phase ends, the
contract processes the commitments and matches the lenders and borrowers based on the leverage.

- `depositBorrower(uint256 amount, bytes calldata whitelistProof)`: Borrowers deposit a specified
  amount of stablecoins along with a whitelist proof. The deposited amount must be greater than the
  `MIN_BORROW_DEPOSIT`.

- `depositLender(uint256 amount)`: Lenders deposit a specified amount of stablecoins. The deposited
  amount must be greater than 0.

### Process

The `process` functions not only mints shares for lenders / confirm borrower commitments but also takes care
of refunds for unmatched parties.

- `processBorrowerCommit(uint256 id)`: Processes a borrower's commit after the commit phase has
  ended. Calculates the included and excluded amounts based on the total assets committed by lenders
  and the leverage. Refunds any unmatched amounts to the borrower.

- `processLenderCommit(uint256 id)`: Processes a lender's commit after the commit phase has ended.
  Calculates the included and excluded amounts based on the total assets committed by borrowers and
  the leverage. Mints shares for the lender based on the included amount and refunds any unmatched
  amounts to the lender.

### Withdraw

- `withdrawBorrower(uint256 id)`: Allows borrowers to withdraw their share of the returned stablecoins
  after the pool phase has ended and swaps have been completed.

- `withdrawLender(uint256 shares)`: Allows lenders to withdraw their share of the returned
  stablecoins, including their earned spread, after the pool phase has ended and swaps have been
  completed.


### State and Transitions

The contract has several states and transitions between them based on the current block timestamp and the completion of specific actions:

1. `State.Commit`: Users can deposit stablecoins as lenders or borrowers during the commit phase.
2. `State.ReadyPreHoldSwap`: The contract is ready to initiate the pre-hold swap after the commit phase ends.
3. `State.PendingPreHoldSwap`: The pre-hold swap is initiated and pending completion.
4. `State.Holding`: The pre-hold swap is completed, and the contract is holding the swapped tokens.
5. `State.ReadyPostHoldSwap`: The contract is ready to initiate the post-hold swap after the pool phase ends.
6. `State.PendingPostHoldSwap`: The post-hold swap is initiated and pending completion.
7. `State.FinalWithdraw`: The post-hold swap is completed, and users can withdraw their share of the returned stablecoins.

## Integrations: Swap Facility & Whitelist

### Swap Facility

The swap facility is required to swap the `UNDERLYING_TOKEN` to and from the `BILL_TOKEN`. The swap
facility is completely trusted by the associated pool contract, the pool does not check or enforce
any slippage on the swap result. Swaps do not have to occur atomically in one transaction, but can
be settled at a later point in a separate call. Meaning any critical such as the aforementioned
slippage checks must be performed by the swap facility.

The swap facility must implement the `swap` method from the [`ISwapFacility`](src/interfaces/ISwapFacility.sol)
interface and call the pool's `completeSwap` method from the [`ISwapRecipient`](src/interfaces/ISwapRecipient.sol)
interface, upon completion.

**NOTE:** The `outAmount` reported by the swap facility contract to the pool upon completion is very
critcial, it **must** equal the amount of tokens actually transferred to the pool. If `outAmount`
is less than the actual amount the difference will be permanently stuck, conversely if `outAmount`
is larger than the actual amount the pool will be insolvent, introducing a race condition whereby
it will not allow all parties to be fully paid out.

### Whitelist

Whitelists uses Merkle proofs for validation logic and conforms to the [`IWhitelist`](src/interfaces/IWhitelist.sol)
interface. The aribtrary length `proof` bytes argument can be used to relay any added context
outside of the members address to the whitelist contract merkle proofs. 


## The [`BillyPoolFactory`](src/BillyPoolFactory.sol) Contract
The factory contract allows for easy deployment of new Billy pools. Specific defaults can be set
prior to deployment via the `storeUint` and `storeAddr` methods. The keys for the configurable
default values are:

- `store.defaultUnderyling`
- `store.defaultWhitelist`
- `store.defaultSwapFacility`
- `store.defaultLeverage`
- `store.defaultMinimumBorrow`

The configured default values can be retrieved at any time via the factory's `getUint` and `getAddr`
methods.

To deploy a pool with the configured defaults use the `createWithDefaults` function, which also
sanity checks the lender return to ensure it's not negative. To deploy a pool without checks or
defaults use the `rawCreate` method. All deployment and configuration methods are only accessible by
the contract's owner.

### Parameters
**Non-defaults (must always be supplied at creation):**
- `address billToken`: Address of the treasury token
- `uint256 commitPhaseDuration`: How much time users should have to commit as borrowers/lenders from contract deployment.
- `uint256 poolPhaseDuration`: How long the pool should hold the treasuries before swapping back and
  allowing people to withdraw, **highly recommended** to set this to the maturity length of the
  underlying treasuries as the pool has no liquidation mechanism.
- `uint256 lenderReturnBps`: The fixed return lenders are to receive in basis points e.g. `10000`
  means lenders will receive 100% of their capital back (0% return), `10030` would
  represent 103% or a 3% yield.
- `string memory name`: The ERC20-name the lender share token should have
- `string memory symbol`: The ERC20-symbol the lender share token should have

**Default parameters (configurable in advance):**

- `store.defaultUnderyling (address)`: The underlying stablecoin for pools (the ERC20
  lender token will copy its decimals)
- `store.defaultWhitelist (address)`: The whitelist contract for pools
- `store.defaultSwapFacility (address)`: The swap facility contract for pools to swap between
  underlying and tokenized T-Bills
- `store.defaultLeverage (uint)`: The pool leverage in basis points e.g. `350000` means that for
  every $1 a borrower commits it'll match $35 of lender commitments
- `store.defaultMinimumBorrow (uint)`: The minimum token amount borrowers will be able to commit to
  in one deposit