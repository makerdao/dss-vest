[![Tests](https://github.com/makerdao/dss-vest/actions/workflows/tests.yml/badge.svg)](https://github.com/makerdao/dss-vest/actions/workflows/tests.yml)
[![Echidna](https://github.com/makerdao/dss-vest/actions/workflows/echidna.yml/badge.svg)](https://github.com/makerdao/dss-vest/actions/workflows/echidna.yml)
[![Certora](https://github.com/makerdao/dss-vest/actions/workflows/certora.yml/badge.svg)](https://github.com/makerdao/dss-vest/actions/workflows/certora.yml)

# dss-vest

A token vesting plan for contributors. Includes scheduling, cliff vesting, and third-party revocation.

### Requirements

- [Dapptools](https://github.com/dapphub/dapptools)

### Deployment

`dss-vest` allows DAOs to create a participant vesting plan via token mints or surplus withdrawals.

```
$ dapp update

$ make deploy-suckable
or
$ make deploy-mintable gem=0xbeef...
or
$ make deploy-transferrable owner=0xdead... gem=0xbeef...
```

#### DssVestMintable

Pass the address of the vesting token to the constructor on deploy. This contract must be given authority to `mint()` tokens in the vesting contract.

After deployment, governance must set the `cap` value using the `file` function.

#### DssVestSuckable

Pass the MCD [chainlog](https://github.com/makerdao/dss-chain-log) address to the constructor to set up the contract for scheduled Dai `suck`s. Note: this contract must be given authority to `suck()` Dai from the `vat`'s surplus buffer.

A `vat.live` check is introduced to disable `vest()` in the event of Emergency Shutdown (aka Global Settlement).

After deployment, governance must set the `cap` value using the `file` function.

#### DssVestTransferrable

Pass the authorized sender address and the address of the token contract to the constructor to set up the contract for streaming arbitrary ERC20 tokens. Note: this contract must be given ERC `approve()` authority to withdraw tokens from this contract.

After deployment, the owner must also set the `cap` value using the `file` function.

### Creating a vest

#### `create(_usr, _tot, _bgn, _tau, _eta, _mgr) returns (id)`

Create a new vesting plan.

- `_usr`: The plan beneficiary
- `_tot`: The total amount of the vesting plan, in token units
  - ex. 100 MKR = `100 * 10**18`
- `_bgn`: A unix-timestamp of the plan start date
- `_tau`: The duration of the vesting plan (in seconds)
- `_eta`: The cliff period, a duration in seconds from the `_bgn` time, in which tokens are accrued but not payable. (in seconds)
- `_mgr`: (Optional) The address of an authorized manager. This address has permission to remove the vesting plan when the contributor leaves the project.
  - Note: `auth` users on this contract _always_ have the ability to `yank` a vesting contract.

### Interacting with a vest

#### `vest(_id)`

The vesting plan participant calls `vest(id)` after the cliff period to pay out all accrued and unpaid tokens.

#### `vest(_id, _maxAmt)`

The vesting plan participant calls `vest(id, maxAmt)` after the cliff period to pay out accrued and unpaid tokens, up to maxAmt.

#### `move(_id, _dst)`

The vesting plan participant can transfer their contract `_id` control and ownership to another address `_dst`.

#### `unpaid(_id) returns (amt)`

Returns the amount of accrued, vested, unpaid tokens.

#### `accrued(_id) returns (amt)`

Returns the amount of tokens that have accrued from the beginning of the plan to the current block.

#### `valid(_id) returns (bool)`

Returns true if the plan id is valid and has not been claimed or yanked before the cliff.

#### `restrict(uint256)`

Allows governance or the owner to restrict vesting to the owner only.

#### `unrestrict(uint256)`

Allows governance or the owner to enable permissionless vesting.

### Revoking a vest

#### `yank(_id)`

An authorized user (ex. governance) of the vesting contract, or an optional plan manager, can `yank` a vesting contract. If the contract is yanked prior to the plan cliff, no funds will be paid out. If a plan is `yank`ed after the contract cliff period has ended, new accruals will cease and the participant will be able to call `vest` to claim any vested funds.

#### `yank(_id, _end)`

Allows governance to schedule a point in the future to end the vest. Used for planned offboarding of contributors.

## Echidna

### Install Echidna

- Install Echidna v2.0.0
  ```
  $ nix-env -i -f https://github.com/crytic/echidna/archive/v2.0.0.tar.gz
  ```
- Install Echidna v2.0.0 via [echidnup](https://github.com/naszam/echidnup#installing)
  ```
  $ echidnup v2.0.0
  ```

### Local Dependencies

- Install solc 0.6.12
  ```
  $ nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_6_12
  ```
- Install solc 0.6.12 via [duppsolc](https://github.com/naszam/duppsolc#installing)
  ```
  $ duppsolc 0.6.12
  ```

### Run Echidna Tests

- DssVestMintableEchidnaTest:
  ```
  $ make echidna-mintable
  ```
- DssVestSuckableEchidnaTest:
  ```
  $ make echidna-suckable
  ```
- DssVestTransferrableEchidnaTest:
  ```
  $ make echidna-transferrable
  ```

## Certora

### Install Certora

- Install Java
  ```
  sudo apt install openjdk-14-jdk
  ```
- Install Certora Prover
  ```
  pip3 install certora-cli
  ```
- Set Certora Key
  ```
  export CERTORAKEY=<key>
  ```

### Local Dependencies

- Install solc-select and install solc 0.6.12 artifacts:
  ```
  make solc-select
  ```

### Run Certora Specs

- Run DssVestMintable Specs:
  ```
  make certora-mintable
  ```
- Run DssVestSuckable Specs:
  ```
  make certora-suckable
  ```
- Run DssVestTransferrable Specs:
  ```
  make certora-transferrable
  ```
