# Concourse intergration with HashiCorp Vault

# Requirements
* docker-compose | https://docs.docker.com/compose/install/
* vault | https://www.vaultproject.io/downloads/
* jq | https://stedolan.github.io/jq/download/

# MacOS homebrew

```console
brew install docker-compose
brew install vault
brew install jq
```

# Behide proxy 

Add these in docker-compose.yml.org under concourse environment:

```console
      http_proxy:  "http://proxy:port"
      https_proxy: "https://proxy:port"
      no_proxy:    "no_proxy=localhost,127.0.0.0,127.0.1.1,127.0.1.1,local.home,vault"
```

# 

# demo.sh
```console
./demo.sh
```

This will run these command in follow order
```
docker-compose up --no-start vault
docker-compose start vault
vault login root
vault secrets enable -version=1 -path=concourse kv
vault write concourse/main/username value=admin
vault write concourse/main/password value=admin
vault write concourse/main/hello value=universe
vault write concourse/main/job/username value=dave
vault write concourse/main/job/password value=dave
vault write concourse/main/hello value=world
vault policy write concourse concourse-policy.hcl
vault policy write concourse-admins concourse-admins-policy.hcl
vault token create --policy concourse --period 1h
vault auth enable approle
vault write auth/approle/role/concourse policies=concourse period=1h
vault write -f -format=json auth/approle/role/concourse/secret-id | jq -r '.data.secret_id'
sed -i.bak "s/ROLE_ID_SECRET_ID/role_id:${ROLE_ID},secret_id:${SECRET_ID}/g" docker-compose.yml
docker-compose up --no-start concourse-db concourse
docker-compose start concourse-db
docker-compose start concourse
fly login -t local -u admin -p admin -c http://127.0.0.1:8080
fly -t local set-pipeline -p job -cpipeline.yml -n
fly -t local unpause-pipeline -p job
fly -t local trigger-job -j job/job
fly -t local watch -j job/job  
vault write concourse/main/job/password value=anthony
```

# Vault URL
http://127.0.0.1:8200

Token: *root*

# Counourse URL

http://127.0.0.1:8080

login: *admin*

password: *admin*


# Testing 1

Change password

```console
vault write concourse/main/job/password value=foobar
```

Then trigger the job

```console
./fly -t local trigger-job -j job/job
./fly -t local watch -j job/job 
```

You will see that the *PASSWORD=foobar*

# Testing 2

Delete job path, concourse will fail back to concourse/main for lookup

```console
vault delete concourse/main/job/username
vault delete concourse/main/job/password
```
Then trigger the job

```console
./fly -t local trigger-job -j job/job
./fly -t local watch -j job/job 
```

You will see that the *USERNAME=admin* and *PASSWORD=admin*


# Cleanup all containers
```console
make clean
```

# Expect output of
```console
make
```

```console
== copy docker-compose.yml.org ==
cp docker-compose.yml.org docker-compose.yml
== Vault ==
docker-compose up --no-start vault
Creating concourse-vault-intergration_vault_1 ... done
docker-compose start vault
Starting vault ... done
sleep 5
vault login root
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                root
token_accessor       TrjzXFnJKGiP8vXWsGrIOr0a
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
== Vault Config ==
vault secrets enable -version=1 -path=concourse kv || (echo "== KV exist ==";)
Success! Enabled the kv secrets engine at: concourse/
== Vault Seed Data ==
vault write concourse/main/username value=admin
Success! Data written to: concourse/main/username
vault write concourse/main/password value=admin
Success! Data written to: concourse/main/password
vault write concourse/main/hello value=universe
Success! Data written to: concourse/main/hello
vault write concourse/main/job/username value=dave
Success! Data written to: concourse/main/job/username
vault write concourse/main/job/password value=dave
Success! Data written to: concourse/main/job/password
vault write concourse/main/hello value=world
Success! Data written to: concourse/main/hello
== Vault Policy Setup ==
vault policy write concourse concourse-policy.hcl
Success! Uploaded policy: concourse
vault policy write concourse-admins concourse-admins-policy.hcl
Success! Uploaded policy: concourse-admins
== Vault AppRole Setup ==
vault auth enable approle || ( echo "== AppRole already enable ==" )
Success! Enabled approle auth method at: approle/
vault write auth/approle/role/concourse policies=concourse period=1h || ( echo "== AppRole exist ==" ; )
Success! Data written to: auth/approle/role/concourse
== Vault AppRole get Role_ID ==
== Role_ID: b81d3c34-ec4f-29f4-07a3-3630b3ca0578 ==
== Concourse setup ==
== Concourse start ==
docker-compose up --no-start concourse-db concourse
Creating concourse-vault-intergration_concourse-db_1 ... done
Creating concourse-vault-intergration_concourse_1    ... done
docker-compose start concourse-db
Starting concourse-db ... done
docker-compose start concourse
Starting concourse ... done
sleep 10
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 20.8M  100 20.8M    0     0  41.2M      0 --:--:-- --:--:-- --:--:-- 41.2M
== Download fly for darwin ==
== Concourse start ==
./fly login -t local -u admin -p admin -c http://127.0.0.1:8080
logging in to team 'main'


target saved
== Deploy pipeline ==
./fly -t local set-pipeline -p job -cpipeline.yml -n
jobs:
  job job has been added:
+ name: job
+ plan:
+ - config:
+     container_limits: {}
+     image_resource:
+       source:
+         repository: busybox
+       type: registry-image
+     params:
+       PASSWORD: ((password))
+       USERNAME: ((username))
+     platform: linux
+     run:
+       path: env
+   task: simple-task
+ public: true

pipeline created!
you can view your pipeline here: http://127.0.0.1:8080/teams/main/pipelines/job

the pipeline is currently paused. to unpause, either:
  - run the unpause-pipeline command:
    ./fly -t local unpause-pipeline -p job
  - click play next to the pipeline in the web ui
./fly -t local unpause-pipeline -p job
unpaused 'job'
./fly -t local trigger-job -j job/job
started job/job #1
./fly -t local watch -j job/job
initializing
fetching busybox@sha256:edafc0a0fb057813850d1ba44014914ca02d671ae247107ca70c94db686e7de6
bdbbaa22dec6 [======================================] 743.1KiB/743.1KiB
running env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PASSWORD=dave
USERNAME=dave
USER=root
HOME=/root
succeeded
== Update Vault value ==
vault write concourse/main/job/password value=anthony
Success! Data written to: concourse/main/job/password
== Retrigger Job ==
./fly -t local trigger-job -j job/job
started job/job #2
./fly -t local watch -j job/job
initializing
running env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PASSWORD=anthony
USERNAME=dave
USER=root
HOME=/root
succeeded
```
