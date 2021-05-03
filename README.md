# dss-vest

## Fuzz

### Install Echidna

- Building using Nix
  `$ nix-env -i -f https://github.com/crytic/echidna/tarball/master`

- Building using Docker
  `$ docker build -t echidna .`

Then, run via:
`docker run -it -v`pwd`:/src echidna echidna-test /src/fuzz/DssVestEchidnaTest.sol`

- Precompiled Binaries

Before starting, make sure Slither is installed:
`$ pip3 install slither-analyzer`

To quickly test Echidna in Linux or MacOS:
[release page](https://github.com/crytic/echidna/releases)

### Local Dependencies

- Slither
  `$ pip3 install slither-analyzer`

- solc-select
  `$ pip3 install solc-select`

### Run Echidna Tests

- Install solc version:
  `$ solc-select install 0.6.12`

- Select solc version:
  `$ solc-select use 0.6.12`

- Run Echidna Tests:
  `$ echidna-test src/fuzz/DssVestEchidnaTest.sol --contract DssVestEchidnaTest --config src/fuzz/echidna.config.yml`
