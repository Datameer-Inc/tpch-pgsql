MKFILE_DIR			:=  $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT_DIR			:=  $(shell dirname $(MKFILE_DIR))
.DEFAULT_GOAL		:=  help
SHELL				:=  /bin/bash
MAKEFLAGS			+= --no-print-directory

# vars
DB_INSTANCE_TYPE	?=	db.t3.small
EC2_INSTANCE_TYPE	?=	t3.micro
# this is where the redeshift cluster is located
REGION				?=	eu-west-2

ACCOUNT_ID			=`aws sts get-caller-identity  | jq -r .Account`
TAG					="$(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com/psql_data_generation:latest"

# default vars
ECHO_CMD 			= $(shell [ -n "$$DRY_RUN" ] && echo 'echo' || echo '')
export DB_INFRA_DIR		= $(MKFILE_DIR)/infra/db_infra
export SSH_PRIVATE_KEY_PATH= $(DB_INFRA_DIR)/pqsql-benchmarks-key.pem

# scale based params
export STREAMS			?= 12
export SCALE			?= 1
export S_FORMATTED		?= $(shell printf "%07.3f\n" $(SCALE))
export S_DATADIR		?= $(shell sf=$(S_FORMATTED) && echo scale$${sf//\./_}/data)
export S_DB_IDENTIFIER	?= $(shell sf=$(S_FORMATTED) && echo dbbenchmarks-scale$${sf//\./-})
export S_SN_IDENTIFIER	?= $(shell sf=$(S_FORMATTED) && echo dbbenchmarks-scale$${sf//\./-})

# conditional output vars
DB_IDENTIFIER		?= $(shell jq -r '.db_identifier.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_ADDR				?= $(shell jq -r '.db_address.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_NAME				?= $(shell jq -r '.db_name.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_USER				?= $(shell jq -r '.db_username.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
DB_PASS				?= $(shell jq -r '.db_pass.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
EC2_ADDR			?= $(shell jq -r '.ec2_address.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)
SSH_PRIVATE_KEY		?= $(shell jq -r '.ssh_private_key.value' $(DB_INFRA_DIR)/tfoutput.json 2>/dev/null || true)

.PHONY: params
params: ## Build the docker image
	@for p in STREAMS SCALE S_FORMATTED S_DATADIR S_DB_IDENTIFIER S_SN_IDENTIFIER; do echo "$$p = $${!p}"; done

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

.PHONY: docker/start
docker/start: ## Start the docker container with PWD mounted as /tpch-pgsql
	@[ "$$(docker ps --format "{{.Names}}" --filter "name=data_generation")" ] || \
		docker run --rm -v $(ROOT_DIR):/tpch-pgsql -d --name="data_generation" $(TAG) sleep infinity

.PHONY: docker/stop
docker/stop: ## Start the docker container with PWD mounted as /tpch-pgsql
	@[ "$$(docker ps --format "{{.Names}}" --filter "name=data_generation")" ] && \
		docker stop data_generation

.PHONY: docker/connect
docker/connect: ## Connect to the docker container (starting if necessary)
docker/connect: docker/start
	@docker exec -ti data_generation bash

.PHONY: preflight
preflight:
	@command -v terraform &> /dev/null || { echo "[ERROR] Please install terraform with 'make local-terraform'."; exit 1; }
	@command -v jq &> /dev/null || { echo "[ERROR] Please install jq before continuing"; exit 1; }

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

# Strange output w/ changes vs no-changes due to: https://github.com/hashicorp/terraform/issues/28844
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
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -s $(SCALE) -i $(S_DATADIR) prepare

.PHONY: app/load
app/load: ## Load the data (optional DRY_RUN=1)
app/load: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -i $(S_DATADIR) load

.PHONY: app/delta/%
app/delta/%: ## Add delta e.g. app/delta/1, app/delta/2, etc (optional DRY_RUN=1)
app/delta/%: guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@cd $(ROOT_DIR) && $(ECHO_CMD) ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -i $(S_DATADIR) -x $* deltas

.PHONY: app/sample-commands
app/sample-commands: ## Generate sample commands
app/sample-commands: guard-SCALE guard-STREAMS guard-DB_ADDR guard-DB_NAME guard-DB_USER guard-DB_PASS app/copy-tpch-dbgen
	@echo "Generate data"
	@echo "( cd .. && ./tpch_pgsql.py -s $(SCALE) prepare )"
	@echo
	@echo "Load data:"
	@echo "( cd .. && ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -i $(S_DATADIR) load )"
	@echo
	@echo "Applying deltas:"
	@for i in $$(seq 0 2); do echo "( cd .. && ./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -x $$i deltas )"; done
	@echo "..."
	@echo "..."
	@echo

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

.PHONY: cli/sample-commands
cli/sample-commands: ## Sample commands for running the aws targets
cli/sample-commands: export DRY_RUN=1
cli/sample-commands:
	@echo "# Push raw CSV files to S3"
	@$(MAKE) cli/push-to-s3
	@echo
	@echo "# Launch an EC2 instance for testing (TODO - replace values in the yaml input file)"
	@$(MAKE) cli/ec2-launch
	@echo
	@echo "# Launch an RDS instance for testing (TODO - replace values in the yaml input file)"
	@$(MAKE) cli/rds-launch
	@echo
	@echo "# Update the password of the RDS instance"
	@$(MAKE) cli/rds-update-password
	@echo
	@echo "# Create a snapshot using SCALE based naming conventions"
	@$(MAKE) cli/rds-create-snapshot
	@echo

.PHONY: cli/push-to-s3
cli/push-to-s3: ## Push CSV raw data to S3
cli/push-to-s3:
	@$(ECHO_CMD) aws s3 sync $(S_DATADIR) s3://psql-benchmark-data/tpch-pgsql-data-dumps/$(S_DATADIR)

.PHONY: cli/ec2-launch
cli/ec2-launch: ## Launch instance using the templates under cli-input-templates
cli/ec2-launch:
	@$(ECHO_CMD) aws ec2 run-instances --cli-input-yaml file://cli-input-templates/ec2-run-instances.yaml

.PHONY: cli/rds-launch
cli/rds-launch: ## Launch RDS using the templates under cli-input-templates
cli/rds-launch:
	@$(ECHO_CMD) aws rds restore-db-instance-from-db-snapshot --cli-input-yaml file://cli-input-templates/restore-db-instance-from-db-snapshot.yaml
	@$(ECHO_CMD) aws rds wait db-instance-available --db-instance-identifier $(DB_IDENTIFIER)

.PHONY: cli/rds-update-password
cli/rds-update-password: ## Update RDS password
cli/rds-update-password:
	@$(ECHO_CMD) aws rds modify-db-instance --db-instance-identifier $(DB_IDENTIFIER) --master-user-password $(DB_PASS)

.PHONY: cli/rds-create-snapshot
cli/rds-create-snapshot: ## Create snapshot of DB_IDENTIFIER
cli/rds-create-snapshot:
	@$(ECHO_CMD) aws rds create-db-snapshot --db-instance-identifier $(S_DB_IDENTIFIER) --db-snapshot-identifier $(S_SN_IDENTIFIER)
	@$(ECHO_CMD) aws rds wait db-snapshot-completed --db-snapshot-identifier $(S_SN_IDENTIFIER)

.PHONY: connect
connect: ## Connect to the terraformed ec2 instance
connect: guard-SSH_PRIVATE_KEY
	ssh -i $(SSH_PRIVATE_KEY_PATH) ec2-user@$(EC2_ADDR)

.PHONY: sync
sync: ## Copy source files the to the terraformed EC2 instance
sync: guard-EC2_ADDR guard-SSH_PRIVATE_KEY
	cd $(ROOT_DIR) && rsync \
		-e 'ssh -i $(SSH_PRIVATE_KEY_PATH)' \
		-au \
		--exclude '.terraform' \
		--exclude '__pycache__' \
		$(ROOT_DIR) ec2-user@$(EC2_ADDR):~/

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