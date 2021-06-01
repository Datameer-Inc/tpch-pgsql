MKFILE_DIR			:=  $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
.DEFAULT_GOAL		:=  help
shell				:=  /bin/bash
MAKEFLAGS			+= --no-print-directory

# vars
DB_INSTANCE_TYPE	?=	db.t3.small
EC2_INSTANCE_TYPE	?=	t3.micro
REGION				?=	us-east-2
DB_PASS				?=	handl3bar

ACCOUNT_ID=`aws sts get-caller-identity  | jq -r .Account`
TAG="$(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com/psql_data_generation:latest"

DB_INFRA_DIR		= aws/infra/db_infra
.PHONY: docker/build
docker/build: ## Build the docker image
	docker build --target final -t $(TAG) .

.PHONY: docker/login
docker/login: ## Log into ECR
docker/login:
	aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com

.PHONY: docker/create-repo
docker/create-repo: ## Create the ECR repository (only if required)
	aws ecr create-repository \
	--repository-name psql_data_generation \
	--image-scanning-configuration scanOnPush=false --region us-east-2

.PHONY: docker/push
docker/push: ## Push to docker image (only if required)
docker/push:
	docker push $(TAG)

.PHONY: docker/run
docker/run: ## Run the docker image with PWD mounted as /tpch-pgsql
	docker run -v $(PWD):/tpch-pgsql --rm -ti $(TAG) bash

.PHONY: preflight
preflight:
	@command -v terraform &> /dev/null || { echo "[ERROR] Please install terraform with 'make local-terraform'."; exit 1; }

.PHONY: keygen
keygen:
	cd $(DB_INFRA_DIR) && \
	[ -f id_rsa ] || ssh-keygen \
		-f id_rsa \
		-t rsa \
		-N ""

.PHONY: keydel
keydel:
	cd $(DB_INFRA_DIR) && \
	rm id_rsa*

.PHONY: tfcmd
tfcmd:
	cd $(DB_INFRA_DIR) && \
	terraform $(TF_CMD) \
		-var="ssh_public_key=`cat id_rsa.pub`" \
		-var="ssh_private_key=`cat id_rsa`" \
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)" \
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)" \
		-var="region=$(REGION)" \
		-var="db_password=$(DB_PASS)"

.PHONY: tf/init
tf/init: TF_CMD=init ## Init terraform resources
tf/init: preflight tfcmd

.PHONY: tf/plan
tf/plan: TF_CMD=plan ## Plan all AWS resources
tf/plan: preflight keygen tfcmd

.PHONY: tf/apply
tf/apply: TF_CMD=apply ## Apply all AWS resources
tf/apply: preflight tfcmd

.PHONY: tf/refresh
tf/refresh: TF_CMD=refresh ## Refresh all AWS resources
tf/refresh: preflight tfcmd
	rm -f $(DB_INFRA_DIR)/tfoutput.json

.PHONY: tf/destroy
tf/destroy: TF_CMD=destroy ## Destroy all AWS resources
tf/destroy: preflight tfcmd keydel

.PHONY: tf/output-gen
tf/output-gen: ## Generate terraform output json
tf/output-gen: preflight
	cd $(DB_INFRA_DIR) && \
	[ -z "$$FORCE" ] || rm -f tfoutput.json; \
	[ -f tfoutput.json ] || terraform output -json > tfoutput.json

.PHONY: tf/output
tf/output: ## Show terraform output information
tf/output: preflight tf/output-gen
	cat $(DB_INFRA_DIR)/tfoutput.json

.PHONY: app/sample-print
app/sample-print: export STREAMS		?= 12
app/sample-print: export DB_ADDR		?= $(shell jq -r '.db_address.value' $(DB_INFRA_DIR)/tfoutput.json)
app/sample-print: export DB_NAME		?= $(shell jq -r '.db_name.value' $(DB_INFRA_DIR)/tfoutput.json)
app/sample-print: export DB_USER		?= $(shell jq -r '.db_username.value' $(DB_INFRA_DIR)/tfoutput.json)
app/sample-print: export DB_PASS		?= $(shell jq -r '.db_pass.value' $(DB_INFRA_DIR)/tfoutput.json)
app/sample-print: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS
	@echo "Generate data w/ default scale (1.5M orders) but $$STREAMS update streams"
	@echo "./tpch_pgsql.py -n $(STREAMS)  prepare"
	@echo
	@echo "Load data:"
	@echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) load"
	@echo
	@echo "Apply deltas:"
	@for i in $$(seq 0 $$STREAMS); do echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -x $$i deltas"; done

.PHONY: app/sample-commands
app/sample-commands: ## Generate sample commands
app/sample-commands: tf/output-gen app/sample-print

# TODO - integrate calling tpch commands (prepare, load, apply, etc)

# TODO - allow for some useful psql commands such as
.PHONY: app/table-count-sql
app/table-count-sql: export DB_ADDR		?= $(shell jq -r '.db_address.value' $(DB_INFRA_DIR)/tfoutput.json)
app/table-count-sql: export DB_NAME		?= $(shell jq -r '.db_name.value' $(DB_INFRA_DIR)/tfoutput.json)
app/table-count-sql: export DB_USER		?= $(shell jq -r '.db_username.value' $(DB_INFRA_DIR)/tfoutput.json)
app/table-count-sql: export DB_PASS		?= $(shell jq -r '.db_pass.value' $(DB_INFRA_DIR)/tfoutput.json)
app/table-count-sql: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS
	@PGPASSWORD=$(DB_PASS) psql -w -U $(DB_USER) -h $(DB_ADDR) $(DB_NAME) -c \
	"select \
		table_schema, \
		table_name, \
		(xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count \
	from (select \
			table_name, \
			table_schema, \
			query_to_xml(format('select count(*) as cnt from %I.%I', table_schema, table_name), false, true, '') as xml_count \
		from information_schema.tables where table_schema = 'public') t"

.PHONY: connect
connect: ## Connect to the terraformed ec2 instance
	ssh \
		-i $(DB_INFRA_DIR)/id_rsa \
		ec2-user@`jq -r '.ec2_address.value' $(DB_INFRA_DIR)/tfoutput.json`

.PHONY: sync
sync: ## Copy source files the to the terraformed EC2 instance
sync: export EC2_ADDR		?= $(shell jq -r '.ec2_address.value' $(DB_INFRA_DIR)/tfoutput.json)
sync: guard-EC2_ADDR
	rsync \
		-e 'ssh -i $(DB_INFRA_DIR)/id_rsa' \
		-au \
		--exclude '.terraform' \
		--delete-excluded \
		$$(pwd) ec2-user@$(EC2_ADDR):~/


.PHONY: local-terraform
local-terraform: ## Install a local copy of terraform (only if required)
local-terraform: TF_VERSION		?= 0.15.4
local-terraform: INSTALL_PATH	?= $(HOME)/.local/bin
local-terraform:
	@terraform -v | awk -Fv '/Terraform v/ { print $2 }' | grep $(TF_VERSION) || \
	if [ ! -d "$(INSTALL_PATH)/terraform_$(TF_VERSION)" ]; then \
		wget https://releases.hashicorp.com/terraform/0.15.4/terraform_$(TF_VERSION)_linux_amd64.zip && \
		unzip terraform_$(TF_VERSION)_linux_amd64.zip && \
		rm terraform_$(TF_VERSION)_linux_amd64.zip && \
		mkdir -p $(INSTALL_PATH) && \
		mv terraform $(INSTALL_PATH)/terraform_$(TF_VERSION); \
	fi
	@ln -sf $(INSTALL_PATH)/terraform_$(TF_VERSION) $(INSTALL_PATH)/terraform && \
	echo "Terraform installed locally under $(INSTALL_PATH)/terraform" && \
	command -v terraform | grep -qE "^$(INSTALL_PATH)/terraform" || \
	echo "Terraform not yet found - maybe try running 'export PATH=$(INSTALL_PATH):$$PATH'"

.PHONY: help
help: # Makefile Help Page
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[\/\%a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-21s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: guard-%
guard-%: # Util to check env var (e.g. guard-ENV_VAR)
	@if [[ "${${*}}" == "" ]]; then echo "Environment variable $* not set"; exit 1; fi