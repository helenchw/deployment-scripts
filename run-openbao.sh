#!/bin/bash

START_OVER=1

# predefined parameters / commands
TAG="2.0.2"
MEM_SIZE="4g"
CONTAINER_NAME="mybao"
DATA_DIR=./openbao-data
TOKEN_FILE_NAME=./openbao-keys-and-tokens.txt
RUN_IN_OPENBAO="docker exec ${CONTAINER_NAME} bao"
ENDPOINT=https://127.0.0.1:8200
TEST_USERNAME=user1
TEST_PASSWORD=password

# configurations
CA_CERT_PATH=ssl/ca.pem
SSL_CERT_PATH=ssl/openbao.pem
SSL_CERT_KEY_PATH=ssl/openbao-key.pem
GEN_SSL_SCRIPT_PATH=gen_cert.sh

# global variables
root_token=

check_for_ssl() {
  echo "> Checking for the SSL certificates ..."
  if [ ! -f ${CA_CERT_PATH} ] || [ ! -f ${SSL_CERT_PATH} ] || [ ! -f ${SSL_CERT_KEY_PATH} ]; then
    echo "Please initialize the SSL and CA certificates using ${GEN_SSL_SCRIPT_PATH}."
    exit 1
  fi
}

reset() {
  echo "> Removing any existing Openbao docker container ..."
  # remove any existing openbao instance
  docker rm -f ${CONTAINER_NAME}

  # remove the data directory for Docker
  if [ ${START_OVER} -eq 1 ]; then
    echo "> Starting over by removing the data directory ..."
    sudo rm -rf ${DATA_DIR}
  fi

  # create the data directory for Docker if not exists
  echo "> Creating the data directory ..."
  mkdir -p ${DATA_DIR}
  chmod 777 ${DATA_DIR}
}

run_openbao() {
  echo "> Starting the OpenBao docker container ..."
  # run an openbao instance
  docker run \
    -id \
    -p 8200:8200 \
    --memory ${MEM_SIZE} \
    --memory-swap ${MEM_SIZE} \
    --memory-swappiness 0 \
    --name ${CONTAINER_NAME} \
    -v ./openbao-config.hcl:/openbao-config.hcl \
    -v ./openbao-data:/mnt/openbao/data \
    -v ./ssl:/ssl:ro \
    -e VAULT_CAPATH="/ssl/ca.pem" \
    openbao/openbao:${TAG} server -config /openbao-config.hcl
}

init_vault() {
  # init the openbao instance's vault and save the root token and unseal keys to a file
  if [ ${START_OVER} -eq 1 ]; then
    echo "> Initializing the OpenBao vault ..."
    ${RUN_IN_OPENBAO} operator init > ${TOKEN_FILE_NAME}
    sleep 2
  fi
}

unseal_vault() {
  echo "> Unsealing the OpenBao vault ..."
  # unseal the vault (using 3 of the 5 keys)
  for key_id in 1 2 3; do
    # grep the unseal keys from the saved vault initialization output
    local unseal_key=$(grep "Unseal Key ${key_id}" ${TOKEN_FILE_NAME} | awk '{print $4}')
    if [ -z ${unseal_key} ]; then
      echo "Failed to extract the key ${key_id} for vault unsealing..."
      exit 1
    fi
    ${RUN_IN_OPENBAO} operator unseal ${unseal_key}

    # echo the unseal key used
    echo "Unseal using the key ${key_id} [${unseal_key}]."
  done
}

get_root_token() {
  root_token=$(grep 'Root Token' ${TOKEN_FILE_NAME} | awk '{print $4}')

  if [ -z ${root_token} ]; then
    echo "Failed to extract the root token..."
    exit 1
  fi

}

echo_root_token() {
  # grep the root token from the saved vault initialization output
  get_root_token
  # echo the root token
  echo "Root token is [${root_token}]."
}

enable_services() {
  # obtain the root token
  get_root_token 

  echo "> Enabling the OpenBao services (authentication using username-password) ..."
  # enable the secret storage service
  docker exec -e VAULT_TOKEN=${root_token} ${CONTAINER_NAME} bao auth enable userpass
}

send_openbao_request() {
  local token=$1
  local path=$2
  local req_type=$3
  local data=$4

  if [ -z "${data}" ]; then
    curl -k \
      --header "X-Vault-Token: ${token}" \
      --request ${req_type} \
      ${ENDPOINT}/${path}
  else
    echo "${data}"
    curl -k \
      --header "X-Vault-Token: ${token}" \
      --header "Content-Type: application/json" \
      --request ${req_type} \
      --data "${data}" \
      ${ENDPOINT}/${path}
  fi
  
}

create_user() {
  get_root_token 

  # add a test user
  echo "> Creating a test user (${TEST_USERNAME}/${TEST_PASSWORD}) ..."
  local configs="{ \"password\": \"${TEST_PASSWORD}\", \"token_polices\": [\"default\"], \"token_type\": \"service\", \"token_period\": 0, \"token_ttl\": \"720d\" }"
  send_openbao_request "${root_token}" "v1/auth/userpass/users/${TEST_USERNAME}" "POST" "${configs}"
}

list_users() {
  get_root_token 

  # list all users
  echo "> Listing all user in OpenBao ..."
  local response=$(send_openbao_request "${root_token}" "v1/auth/userpass/users" "LIST")
  echo ${response} | jq -r ".data.keys"
}

create_a_user_token() {
  echo "> Generating a token for user ${TEST_USERNAME} in OpenBao ..."
  local user_token=$(docker exec ${CONTAINER_NAME} bao login -token-only -method "userpass" username=${TEST_USERNAME} password=${TEST_PASSWORD})
  echo "User token: ${user_token}"

  echo "> Querying a token for user ${TEST_USERNAME} in OpenBao ..."
  local response=$(send_openbao_request "${user_token}" "v1/auth/token/lookup-self" "GET")

  local username=$(echo ${response} | jq -r ".data.meta.username")
  local token_expiration=$(echo ${response} | jq -r ".data.expire_time")

  echo "Username in the response: ${username}"
  echo "Token expiration time: ${token_expiration}"
}


# main

check_for_ssl
reset
run_openbao
init_vault
unseal_vault
echo_root_token
enable_services

create_user
list_users
create_a_user_token
