[![Fuzz](https://github.com/brianmcmichael/dss-vest/actions/workflows/fuzz.yml/badge.svg)](https://github.com/brianmcmichael/dss-vest/actions/workflows/fuzz.yml)

# dss-vest

A token vesting plan for contributors. Includes scheduling, cliff vesting, and third-party revocation.

### Requirements

- [Dapptools](https://github.com/dapphub/dapptools)

### Deployment

`dss-vest` allows DAOs to create a participant vesting plan via token mints.

Pass the address of the vesting token to the constructor on deploy. This contract must be given authority to `mint()` tokens in the vesting contract.

### Creating a vest

#### `init(_usr, _tot, _bgn, _tau, _clf, _mgr) returns (id)`

Init a new vest to create a vesting plan.

- `_usr`: The plan beneficiary
- `_tot`: The total amount of the vesting plan, in token units
  - ex. 100 MKR = `100 * 10**18`
- `_bgn`: A unix-timestamp of the plan start date
- `_tau`: The duration of the vesting plan (in seconds)
- `_clf`: The cliff period, in which tokens are accrued but not payable. (in seconds)
- `_mgr`: (Optional) The address of an authorized manager. This address has permission to remove the vesting plan when the contributor leaves the project.
  - Note: `auth` users on this contract _always_ have the ability to `yank` a vesting contract.

### Interacting with a vest

#### `vest(_id)`

The vesting plan participant calls `vest(id)` after the cliff period to pay out accrued and unpaid tokens.

#### `move(_id, _dst)`

The vesting plan participant can transfer their contract `_id` control and ownership to another address `_dst`.

#### `unpaid(_id) returns (amt)`

Returns the amount of accrued, vested, unpaid tokens.

#### `accrued(_id) returns (amt)`

Returns the amount of tokens that have accrued from the beginning of the plan to the current block.

#### `valid(_id) returns (bool)`

Returns true if the plan id is valid and has not been claimed or yanked before the cliff.

### Revoking a vest

#### `yank(_id)`

An authorized user (ex. governance) of the vesting contract, or an optional plan manager, can `yank` a vesting contract. If the contract is yanked prior to the plan cliff, no funds will be paid out. If a plan is `yank`ed after the contract cliff period has ended, new accruals will cease and the participant will be able to call `vest` to claim any vested funds.

#### `yank(_id, _end)`

Allows governance to schedule a point in the future to end the vest. Used for planned offboarding of contributors.

## Fuzz

### Install Echidna

- Building using Nix
  `$ nix-env -i -f https://github.com/crytic/echidna/tarball/master`

### Run Echidna Tests

- Install solc 0.6.12:
  `$ nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-versions.solc_0_6_12`

- Run Echidna Tests:
  `$ echidna-test src/fuzz/DssVestEchidnaTest.sol --contract DssVestEchidnaTest --config echidna.config.yml`
