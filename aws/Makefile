MKFILE_DIR			:=  $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT_DIR			:=  $(shell dirname $(MKFILE_DIR))
.DEFAULT_GOAL		:=  help
SHELL				:=  /bin/bash
MAKEFLAGS			+= --no-print-directory

# vars
DB_INSTANCE_TYPE	?=	db.t3.small
EC2_INSTANCE_TYPE	?=	t3.micro
REGION				?=	us-east-2

ACCOUNT_ID			=`aws sts get-caller-identity  | jq -r .Account`
TAG					="$(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com/psql_data_generation:latest"

# conditional output vars
ECHO_CMD 			= $(shell [[ "1" == "$$DRY_RUN" ]] && echo 'echo' || echo '')
DB_INFRA_DIR		= $(MKFILE_DIR)/infra/db_infra
SSH_PRIVATE_KEY_PATH= $(DB_INFRA_DIR)/pqsql-benchmarks-key.pem
DB_ADDR				?= $(shell jq -r '.db_address.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_NAME				?= $(shell jq -r '.db_name.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_USER				?= $(shell jq -r '.db_username.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_PASS				?= $(shell jq -r '.db_pass.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
EC2_ADDR			?= $(shell jq -r '.ec2_address.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
SSH_PRIVATE_KEY		?= $(shell jq -r '.ssh_private_key.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)

# default data vars
STREAMS				?= 12
SCALE				?= 1

.PHONY: docker/build
docker/build: ## Build the docker image
	docker build --target final -t $(TAG) $(ROOT_DIR)

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
	docker run -v $(ROOT_DIR):/tpch-pgsql --rm -ti $(TAG) bash

.PHONY: preflight
preflight:
	@command -v terraform &> /dev/null || { echo "[ERROR] Please install terraform with 'make local-terraform'."; exit 1; }

.PHONY: tfcmd
tfcmd: guard-TF_CMD
	cd $(DB_INFRA_DIR) && \
	terraform $(TF_CMD) \
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)" \
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)" \
		-var="region=$(REGION)"

.PHONY: tf/init
tf/init: TF_CMD=init ## Init terraform resources
tf/init: preflight tfcmd

.PHONY: tf/plan
tf/plan: TF_CMD=plan ## Plan all AWS resources
tf/plan: preflight tfcmd

.PHONY: tf/apply
tf/apply: TF_CMD=apply ## Apply all AWS resources
tf/apply: preflight tfcmd

.PHONY: tf/apply-refresh-only
tf/apply-refresh-only: TF_CMD=apply -refresh-only ## Apply all AWS resources
tf/apply-refresh-only: preflight tfcmd

.PHONY: tf/refresh
tf/refresh: TF_CMD=refresh ## Refresh all AWS resources
tf/refresh: preflight tfcmd
	rm -f $(DB_INFRA_DIR)/tfoutput.json

.PHONY: tf/destroy
tf/destroy: TF_CMD=destroy ## Destroy all AWS resources
tf/destroy: preflight tfcmd

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

.PHONY: app/copy-tpch-dbgen
app/copy-tpch-dbgen: ## Copy tpch-dbgen directory if necessary
	@\
	[ -d "$(ROOT_DIR)/tpch-dbgen" ] || \
	[ -d "/opt/tpch-dbgen" ] && cp -r /opt/tpch-dbgen $(ROOT_DIR) || \
	{ \
		cd /opt && \
        wget -q https://github.com/electrum/tpch-dbgen/archive/32f1c1b92d1664dba542e927d23d86ffa57aa253.zip -O tpch-dbgen.zip && \
        unzip -q tpch-dbgen.zip && mv tpch-dbgen-32f1c1b92d1664dba542e927d23d86ffa57aa253 tpch-dbgen && rm tpch-dbgen.zip && \
		cp -r /opt/tpch-dbgen $(ROOT_DIR); \
	}

.PHONY: app/prepare
app/prepare: ## Prepare/generate the data (optional DRY_RUN=1, SCALE=?, STREAMS=?)
app/prepare: guard-STREAMS guard-SCALE app/copy-tpch-dbgen
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -s $(SCALE) -n $(STREAMS) prepare

.PHONY: app/load
app/load: ## Load the data (optional DRY_RUN=1)
app/load: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) load

.PHONY: app/delta/%
app/delta/%: ## Add delta e.g. app/delta/1, app/delta/2, etc (optional DRY_RUN=1)
app/delta/%:
app/delta/%: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -x $* deltas

.PHONY: app/sample-commands
app/sample-commands: ## Generate sample commands
app/sample-commands: guard-SCALE guard-STREAMS guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@echo "Generate data w/ default scale (1.5M orders) but $$STREAMS update streams"
	@echo "./tpch_pgsql.py -s $(SCALE) -n $(STREAMS) prepare"
	@echo
	@echo "Load data:"
	@echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) load"
	@echo
	@echo "Apply deltas:"
	@for i in $$(seq 0 $$STREAMS); do echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -x $$i deltas"; done

# TODO - integrate calling tpch commands (prepare, load, apply, etc)

# TODO - allow for some useful psql commands such as
.PHONY: app/table-count-sql
app/table-count-sql: ## DB util - list table counts
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
connect: guard-SSH_PRIVATE_KEY
	ssh -i $(SSH_PRIVATE_KEY_PATH) \
		ec2-user@`jq -r '.ec2_address.value' $(DB_INFRA_DIR)/tfoutput.json`

.PHONY: sync
sync: ## Copy source files the to the terraformed EC2 instance
sync: guard-EC2_ADDR guard-SSH_PRIVATE_KEY
	cd $(ROOT_DIR) && rsync \
		-e 'ssh -i $(SSH_PRIVATE_KEY_PATH)' \
		-au \
		--exclude '.terraform' \
		--exclude '__pycache__' \
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