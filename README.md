# SIP10 migration token concept

This is a SIP10 compatible token set that offers a migration mechanism that can
be triggered by a contract owner. The contract owner should be a trust-minimised
principal. Once migration is triggered, the first SIP10 becomes defunct and the
replacement SIP10 compatible token will only be usable once the migration is
complete. Token migration is triggered in batches of up to 2,000 principals or
the runtime limit, whichever is smaller. Anyone can trigger token migration in
a trustless manner.

The concept burns the old tokens and mints new tokens as the migration happens.
It should therefore be minimally invasive for most users as their wallets will
show the same amount of USDC. The only inconvenience they could experience is
that they cannot transfer interim tokens while the migration waiting period is
active, which is currently 6 blocks. The migration also replaces tokens for
contract principals in the same way. Protocols that employ allowlists will need
to update that list (but the tokens will already be owned) and CEX and other
indexers will also need to update the stored token principal.

There is one integration test to illustrate how the migration would work.

# Out of scope

- How interim and final tokens are minted. In the example, the contract owner
  can perform these actions.
- The design of the contract owner itself, which should be a trust-minimised
  principal.
- The exact design of the final token contract. A minimal implementation is
  provided.

# Test

1. `yarn install`
2. `yarn test`
