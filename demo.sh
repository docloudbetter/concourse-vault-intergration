#!/bin/bash
#
# Concourse and HashiCorp Vault integration
#

export VAULT_ADDR="http://127.0.0.1:8200"

which docker-compose
if [ $? -ne 0 ]; then
 echo "please install docker-compose"
 exit 1
fi

which jq
if [ $? -ne 0 ]; then
  echo "please install jq"
  exit 1
fi

pause(){
  echo ""
  read -n 1 -s -r -p "Press any key to continue"
  echo ""
}

function vault_create(){
  echo "=== Create docker containers: vault / concourse-db / concourse ==="
  echo -e "\033[1;31m Execute: docker-compose create \033[0m"
  echo "=================================================================="
  docker-compose up --no-start vault
}

function vault_start(){
  echo ""
  echo "=== Start vault container ========================================"
  echo -e "\033[1;31m Execute: docker-compose start vault \033[0m"
  docker-compose start vault
}

function vault_login(){
  echo "=== Login into vault ============================================="
  echo -e "\033[1;31m Execute: vault login root \033[0m"
  vault login root
}

function vault_create_kv(){
  echo "=== Create Vault K/V with path /concourse ========================"
  echo -e "\033[1;31m Execute: vault secrets enable -version=1 -path=concourse kv \033[0m"
  vault secrets enable -version=1 -path=concourse kv
}

function vault_seed_data(){
  echo "=== Seed Vault K/V data ========================"
  echo -e "\033[1;31m Execute: 
  vault write concourse/main/username value=admin
  vault write concourse/pcf/om-password value=pa$$w0rd
  vault write concourse/pcf/om-password value=pa$$w0rd
  vault write concourse/main/hello value=world
  \033[0m"
  vault write concourse/main/username value=admin
  vault write concourse/main/password value=admin
  vault write concourse/main/hello value=universe
  vault write concourse/main/job/username value=dave
  vault write concourse/main/job/password value=dave
  vault write concourse/main/hello value=world
}

function vault_create_policy(){
  echo "=== Create vault policies: concourse ============================="
  echo -e "\033[1;31m Execute: vault policy write concourse concourse-policy.hcl \033[0m"
  vault policy write concourse concourse-policy.hcl
}

function vault_create_policy_admins(){
  echo "=== Create vault policies: concourse-admin ========================"
  echo -e "\033[1;31m Execute: vault policy write concourse-admins concourse-admins-policy.hcl \033[0m"
  vault policy write concourse-admins concourse-admins-policy.hcl
}

function vault_create_token(){
  echo "=== Create token in Vault --======================================"
  echo -e "\033[1;31m Execute: vault token create --policy concourse --period 1h \033[0m"
  vault token create --policy concourse --period 1h
}

function vault_enable_approle(){
  echo "=== Enable approle in Vault ======================================"
  echo -e "\033[1;31m Execute: vault auth enable approle \033[0m"
  vault auth enable approle
}

function vault_create_approle(){
  echo "=== Create approle in Vault ======================================"
  echo -e "\033[1;31m Execute: vault write auth/approle/role/concourse policies=concourse period=1h \033[0m"
  vault write auth/approle/role/concourse policies=concourse period=1h
}

function vault_create_secret_id(){
  echo "=== Fetch role-id from approle ==================================="
  echo -e "\033[1;31m Execute: vault read auth/approle/role/concourse/role-id \033[0m"
  ROLE_ID=$(vault read auth/approle/role/concourse/role-id --format=json | jq -r '.data.role_id')
  echo -e "\033[1;31m ROLE_ID = ${ROLE_ID} \033[0m"
  echo "=== Fetch role-id from approle ==================================="
  echo -e "\033[1;31m Execute: vault read auth/approle/role/concourse/role-id \033[0m"
  SECRET_ID=$(vault write -f -format=json auth/approle/role/concourse/secret-id | jq -r '.data.secret_id')
  echo -e "\033[1;31m SECRET_ID = ${SECRET_ID} \033[0m"
}

function update_config(){
  echo "=== Update ROLE_ID / SECRET_ID to concourse web server ==========="
  sed -i.bak "s/ROLE_ID_SECRET_ID/role_id:${ROLE_ID},secret_id:${SECRET_ID}/g" docker-compose.yml
}

function start_concourse(){
  echo "=== Apply new config to concourse container ======================"
  echo -e "\033[1;31m Execute: docker-compose start concourse \033[0m"
  docker-compose up --no-start concourse-db concourse
  docker-compose start concourse-db
  docker-compose start concourse
}

download_fly(){
  OS=`uname -s`
  case "$OS" in
    Darwin) 
	    curl http://127.0.0.1:8080/api/v1/cli\?arch\=amd64\&platform\=darwin --output ./fly
            chmod +x ./fly
	    ;;
    Linux)
	    curl http://127.0.0.1:8080/api/v1/cli\?arch\=amd64\&platform\=linux --output ./fly
           chmod +x ./fly
	    ;;
    *) echo "OS not Support"
       exit 1
          ;;
  esac
}

function concourse_login(){
  echo "=== Login to concourse ==========================================="
  echo -e "\033[1;31m Execute: ./fly login -t local -u admin -p admin -c http://127.0.0.1:8080 \033[0m"
  ./fly login -t local -u admin -p admin -c http://127.0.0.1:8080
}

function pipeline_deploy(){
  echo "=== Deploy pipeline ==============================================="
  echo -e "\033[1;31m Execute: ./fly -t local set-pipeline -p job -cpipeline.yml \033[0m"
  ./fly -t local set-pipeline -p job -cpipeline.yml -n
  ./fly -t local unpause-pipeline -p job
  ./fly -t local trigger-job -j job/job
  echo "=== watch job  ===================================================="
  echo -e "\033[1;31m Execute: ./fly -t local watch -p job/job  \033[0m"
  ./fly -t local watch -j job/job
  echo "==================================================================="
}

function update_vault_secret(){
  echo "=== Update vault variable ========================================"
  echo -e "\033[1;31m Execute: vault write concourse/main/job/password value=anthony \033[0m"
  vault write concourse/main/job/password value=anthony
}

### Main program ###
cp docker-compose.yml.org docker-compose.yml
vault_create
vault_start
## Wait for vault to be up ##
vault login root
while [ $? -ne 0 ] 
do
  echo "Waiting for Vault to be up ..."
  sleep 5
  vault_login root
done

vault_create_kv
vault_seed_data
vault_create_policy
vault_create_policy_admins
vault_create_token
vault_enable_approle
vault_create_approle
vault_create_secret_id
update_config
start_concourse

concourse_login
while [ $? -ne 0 ] 
do
  echo "Waiting for Concourse to be up ..."
  sleep 5
  download_fly
  concourse_login
done

pipeline_deploy
update_vault_secret
pipeline_deploy

