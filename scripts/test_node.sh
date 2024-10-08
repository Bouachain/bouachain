#!/bin/bash
# Run this script to quickly install, setup, and run the current version of the network without docker.
#
# Examples:
# CHAIN_ID="bouachain" HOME_DIR="~/.bouachain" BLOCK_TIME="1000ms" CLEAN=true sh scripts/test_node.sh
# CHAIN_ID="localchain-2" HOME_DIR="~/.bouachain" CLEAN=true RPC=36657 REST=2317 PROFF=6061 P2P=36656 GRPC=8090 GRPC_WEB=8091 ROSETTA=8081 BLOCK_TIME="500ms" sh scripts/test_node.sh

export KEY="bouaverse"
export KEY2="bouablock"

export CHAIN_ID=${CHAIN_ID:-"bouachain"}
export MONIKER="BouaValidator"
export KEYALGO="secp256k1"
export KEYRING=${KEYRING:-"test"}
export HOME_DIR=$(eval echo "${HOME_DIR:-"~/.bouachain"}")
export BINARY=${BINARY:-bouachain}
export DENOM=${DENOM:-ubouacoin}

export CLEAN=${CLEAN:-"false"}
export RPC=${RPC:-"26657"}
export REST=${REST:-"1317"}
export PROFF=${PROFF:-"6060"}
export P2P=${P2P:-"26656"}
export GRPC=${GRPC:-"9090"}
export GRPC_WEB=${GRPC_WEB:-"9091"}
export PROFF_LADDER=${PROFF_LADDER:-"6060"}
export ROSETTA=${ROSETTA:-"8080"}
export BLOCK_TIME=${BLOCK_TIME:-"5s"}

# if which binary does not exist, install it
if [ -z `which $BINARY` ]; then
  make install

  if [ -z `which $BINARY` ]; then
    echo "Ensure $BINARY is installed and in your PATH"
    exit 1
  fi
fi

alias BINARY="$BINARY --home=$HOME_DIR"

command -v $BINARY > /dev/null 2>&1 || { echo >&2 "$BINARY command not found. Ensure this is setup / properly installed in your GOPATH (make install)."; exit 1; }
command -v jq > /dev/null 2>&1 || { echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"; exit 1; }

set_config() {
  $BINARY config set client chain-id $CHAIN_ID
  $BINARY config set client keyring-backend $KEYRING
}
set_config


from_scratch () {
  # Fresh install on current branch
  make install

  # remove existing daemon files.
  if [ ${#HOME_DIR} -le 2 ]; then
      echo "HOME_DIR must be more than 2 characters long"
      return
  fi
  rm -rf $HOME_DIR && echo "Removed $HOME_DIR"

  # reset values if not set already after whipe
  set_config

  add_key() {
    key=$1
    mnemonic=$2
    echo $mnemonic | BINARY keys add $key --keyring-backend $KEYRING --algo $KEYALGO --recover
  }

  # boua1r7fm6cl5j4qu0l683e9hxpunczg3q4npjgr27l
  add_key $KEY "flash ozone elevator cash ability invest hip flower museum patch exercise swift olive endless another sleep chair machine leopard agree roast analyst border thunder"
  # boua1x62lhv0m0qt38759299fg04qgueqt8uaay3wg9
  add_key $KEY2 "dinner fossil column choice mobile similar owner garment olive furnace lawn carry what solar girl often drip render choose glove inquiry turtle fruit broccoli"

  # chain initial setup
  BINARY init $MONIKER --chain-id $CHAIN_ID --default-denom $DENOM

  update_test_genesis () {
    cat $HOME_DIR/config/genesis.json | jq "$1" > $HOME_DIR/config/tmp_genesis.json && mv $HOME_DIR/config/tmp_genesis.json $HOME_DIR/config/genesis.json
  }
  
  # Adding denom metadata
  update_test_genesis '
  .app_state["bank"]["denom_metadata"]=[{
    "description": "The native token of Bouachain, used for transaction fees, staking, and governance.",
    "denom_units": [
      {"denom": "ubouacoin", "exponent": 0, "aliases": []},
      {"denom": "bouacoin", "exponent": 8, "aliases": ["BOUA"]}
    ],
    "base": "ubouacoin",
    "display": "bouacoin",
    "name": "Bouacoin",
    "symbol": "BOUA"
  }]'
  
  # === CORE MODULES ===

  # Block
  update_test_genesis '.consensus_params["block"]["max_gas"]="100000000"'

  # Gov
  update_test_genesis `printf '.app_state["gov"]["params"]["min_deposit"]=[{"denom":"%s","amount":"10000000"}]' $DENOM`
  update_test_genesis '.app_state["gov"]["params"]["voting_period"]="30s"'
  update_test_genesis '.app_state["gov"]["params"]["expedited_voting_period"]="15s"'

  # staking
  update_test_genesis `printf '.app_state["staking"]["params"]["bond_denom"]="%s"' $DENOM`
  update_test_genesis '.app_state["staking"]["params"]["min_commission_rate"]="0.10000000000000000"'

  # mint
  update_test_genesis `printf '.app_state["mint"]["params"]["mint_denom"]="%s"' $DENOM`
  update_test_genesis '.app_state["mint"]["minter"]["inflation"]="0.100000000000000000"'
  update_test_genesis '.app_state["mint"]["minter"]["annual_provisions"]="0.100000000000000000"'
  update_test_genesis '.app_state["mint"]["params"]["inflation_rate_change"]="0.000000000000000000"'
  update_test_genesis '.app_state["mint"]["params"]["inflation_max"]="0.100000000000000000"'
  update_test_genesis '.app_state["mint"]["params"]["inflation_min"]="0.050000000000000000"'
  update_test_genesis '.app_state["mint"]["params"]["goal_bonded"]="0.670000000000000000"'
  update_test_genesis '.app_state["mint"]["params"]["blocks_per_year"]="6311520"'

  # crisis
  update_test_genesis `printf '.app_state["crisis"]["constant_fee"]={"denom":"%s","amount":"1000"}' $DENOM`
  
  # Distribution (Add Community Tax, Base Proposer Reward, and Bonus Proposer Reward)
  update_test_genesis '.app_state["distribution"]["params"]["community_tax"]="0.020000000000000000"'
  update_test_genesis '.app_state["distribution"]["params"]["base_proposer_reward"]="0.010000000000000000"'
  update_test_genesis '.app_state["distribution"]["params"]["bonus_proposer_reward"]="0.040000000000000000"'

  # === CUSTOM MODULES ===
  
  # tokenfactory
  update_test_genesis '.app_state["tokenfactory"]["params"]["denom_creation_fee"]=[]'
  update_test_genesis '.app_state["tokenfactory"]["params"]["denom_creation_gas_consume"]=2000000'

  # Allocate genesis accounts
  BINARY genesis add-genesis-account $KEY 90000000000000000$DENOM --keyring-backend $KEYRING --append
  BINARY genesis add-genesis-account $KEY2 10000000000000000$DENOM --keyring-backend $KEYRING --append

  # Sign genesis transaction
  BINARY genesis gentx $KEY2 10000000000000000$DENOM --keyring-backend $KEYRING --chain-id $CHAIN_ID \
--moniker "BouaValidator" \
--identity "" \
--website "https://bouachain.com" \
--security-contact "dev@bouachain.com" \
--details "Bouachain Validator" \
--commission-rate "0.10" \
--commission-max-rate "0.20" \
--commission-max-change-rate "0.01" \
--min-self-delegation "1"

  BINARY genesis collect-gentxs

  BINARY genesis validate-genesis
  err=$?
  if [ $err -ne 0 ]; then
    echo "Failed to validate genesis"
    return
  fi
}

# check if CLEAN is not set to false
if [ "$CLEAN" != "false" ]; then
  echo "Starting from a clean state"
  from_scratch
fi

echo "Starting node..."

# Opens the RPC endpoint to outside connections
sed -i -e 's/laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:'$RPC'"/g' $HOME_DIR/config/config.toml
sed -i -e 's/cors_allowed_origins = \[\]/cors_allowed_origins = \["\*"\]/g' $HOME_DIR/config/config.toml

# REST endpoint
sed -i -e 's/address = "tcp:\/\/localhost:1317"/address = "tcp:\/\/0.0.0.0:'$REST'"/g' $HOME_DIR/config/app.toml
sed -i -e 's/enable = false/enable = true/g' $HOME_DIR/config/app.toml
sed -i -e 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g' $HOME_DIR/config/app.toml

# peer exchange
sed -i -e 's/pprof_laddr = "localhost:6060"/pprof_laddr = "localhost:'$PROFF'"/g' $HOME_DIR/config/config.toml
sed -i -e 's/laddr = "tcp:\/\/0.0.0.0:26656"/laddr = "tcp:\/\/0.0.0.0:'$P2P'"/g' $HOME_DIR/config/config.toml

# GRPC
sed -i -e 's/address = "localhost:9090"/address = "0.0.0.0:'$GRPC'"/g' $HOME_DIR/config/app.toml
sed -i -e 's/address = "localhost:9091"/address = "0.0.0.0:'$GRPC_WEB'"/g' $HOME_DIR/config/app.toml

# Rosetta Api
sed -i -e 's/address = ":8080"/address = "0.0.0.0:'$ROSETTA'"/g' $HOME_DIR/config/app.toml

# Faster blocks
sed -i -e 's/timeout_commit = "5s"/timeout_commit = "'$BLOCK_TIME'"/g' $HOME_DIR/config/config.toml

# Start the node with 0 gas fees
BINARY start --pruning=nothing  --minimum-gas-prices=0.0006$DENOM --rpc.laddr="tcp://0.0.0.0:$RPC"