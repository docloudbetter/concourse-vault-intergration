SHELL := /bin/bash

export VAULT_ADDR := http://127.0.0.1:8200

ROLE_ID=$(shell VAULT_ADDR=$(VAULT_ADDR) vault read auth/approle/role/concourse/role-id --format=json | jq -r ".data.role_id")
SECRET_ID=$(shell VAULT_ADDR=$(VAULT_ADDR) vault write -f -format=json auth/approle/role/concourse/secret-id | jq -r '.data.secret_id')

# Only Linux, MacOS are support
OS_NAME := $(shell uname -s | tr A-Z a-z)
ifeq ($(OS_NAME),linux)
  cmd=$(shell curl -s http://127.0.0.1:8080/api/v1/cli\?arch\=amd64\&platform\=linux --output ./fly ; chmod +x ./fly)
endif

ifeq ($(OS_NAME),darwin)
  cmd=$(shell curl http://127.0.0.1:8080/api/v1/cli\?arch\=amd64\&platform\=darwin --output ./fly; chmod +x ./fly)
endif


.PHONY: all
all:    copy_file \
	vault_start \
       	vault_config \
       	vault_seed_data \
	vault_policy \
	vault_approle \
	vault_approle_getid \
	concourse_setup \
	concourse_start \
	download_fly \
	concourse_login \
	deploy \
	trigger

.PHONY: copy_file
copy_file:
	@ echo "== copy docker-compose.yml.org =="
	cp docker-compose.yml.org docker-compose.yml

.PHONY: vault_start
vault_start:
	@ echo "== Vault =="
	docker-compose up --no-start vault
	docker-compose start vault
	sleep 5
	vault login root

.PHONY: vault_config
vault_config:
	@ echo "== Vault Config =="
	vault secrets enable -version=1 -path=concourse kv || (echo "== KV exist ==";)

.PHONY: vault_seed_data
vault_seed_data:
	@ echo "== Vault Seed Data =="
	vault write concourse/main/username value=admin
	vault write concourse/main/password value=admin
	vault write concourse/main/hello value=universe
	vault write concourse/main/job/username value=dave
	vault write concourse/main/job/password value=dave
	vault write concourse/main/hello value=world


.PHONY: vault_policy
vault_policy: 
	@ echo "== Vault Policy Setup =="
	vault policy write concourse concourse-policy.hcl
	vault policy write concourse-admins concourse-admins-policy.hcl
	
.PHONY: vault_approle
vault_approle: 
	@ echo "== Vault AppRole Setup =="
	vault auth enable approle || ( echo "== AppRole already enable ==" )
	vault write auth/approle/role/concourse policies=concourse period=1h || ( echo "== AppRole exist ==" ; )

.PHONY: vault_approle_getid
vault_approle_getid:
	@ echo "== Vault AppRole get Role_ID =="
	@ echo "== Role_ID: $(ROLE_ID) =="

.PHONY: concourse_setup
concourse_setup: 
	@ echo "== Concourse setup =="
	$(shell sed -i.bak "s/ROLE_ID_SECRET_ID/role_id:$(ROLE_ID),secret_id:$(SECRET_ID)/g" docker-compose.yml)

.PHONY: concourse_start
concourse_start:
	@ echo "== Concourse start =="
	docker-compose up --no-start concourse-db concourse
	docker-compose start concourse-db
	docker-compose start concourse
	sleep 10

.PHONY: concourse_login
concourse_login: download_fly
	@ echo "== Concourse start =="
	./fly login -t local -u admin -p admin -c http://127.0.0.1:8080

loop = 10
.PHONY: download_fly
download_fly: concourse_start
	@ echo "== Download fly for $(OS_NAME) =="
	$(cmd) 

.PHONY: deploy
deploy: concourse_login
	@ echo "== Deploy pipeline =="
	./fly -t local set-pipeline -p job -cpipeline.yml -n
	./fly -t local unpause-pipeline -p job
	./fly -t local trigger-job -j job/job
	./fly -t local watch -j job/job

.PHONY: trigger
trigger: update_vault deploy
	@ echo "== Retrigger Job =="
	./fly -t local trigger-job -j job/job
	./fly -t local watch -j job/job

.PHONY: update_vault
update_vault: 
	@ echo "== Update Vault value =="
	vault write concourse/main/job/password value=anthony

.PHONY: clean
clean:
	@echo "Clean up"
	docker-compose stop
	docker-compose rm -f

