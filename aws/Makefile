MKFILE_DIR			:=  $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
.DEFAULT_GOAL		:=  help
shell				:=  /bin/bash
MAKEFLAGS			+= --no-print-directory

# vars
DB_INSTANCE_TYPE	?=	db.t3.small
EC2_INSTANCE_TYPE	?=	t3.micro
REGION				?=	us-east-2
DB_PASS				?=	handl3bar


.PHONY: preflight
preflight:
	@command -v terraform &> /dev/null || { echo "[ERROR] Please install terraform."; exit 1; }

.PHONY: keygen
keygen:
	cd infra/db_infra && \
	[ -f id_rsa ] || ssh-keygen \
		-f id_rsa \
		-t rsa \
		-N ""

.PHONY: keydel
keydel:
	cd infra/db_infra && \
	rm id_rsa*

.PHONY: tfcmd
tfcmd:
	cd infra/db_infra && \
	terraform $(TF_CMD) \
		-var="ssh_public_key=`cat id_rsa.pub`" \
		-var="ssh_private_key=`cat id_rsa`" \
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)" \
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)" \
		-var="region=$(REGION)" \
		-var="db_password=$(DB_PASS)"

.PHONY: init
init: TF_CMD=init ## Init terraform resources
init: preflight tfcmd

.PHONY: plan
plan: TF_CMD=plan ## Plan all AWS resources
plan: preflight keygen tfcmd

.PHONY: apply
apply: TF_CMD=apply ## Apply all AWS resources
apply: preflight tfcmd

.PHONY: refresh
refresh: TF_CMD=refresh ## Refresh all AWS resources
refresh: preflight tfcmd
	rm -f infra/db_infra/tfoutput.json

.PHONY: destroy
destroy: TF_CMD=destroy ## Destroy all AWS resources
destroy: preflight tfcmd keydel


.PHONY: output/gen
output/gen: ## Generate terraform output json
output/gen: preflight
	cd infra/db_infra && \
	[ -z "$$FORCE" ] || rm -f tfoutput.json; \
	[ -f tfoutput.json ] || terraform output -json > tfoutput.json

.PHONY: output
output: ## Show terraform output information
output: preflight output/gen
	cat infra/db_infra/tfoutput.json

.PHONY: sample-print
sample-print: export STREAMS		?= 12
sample-print: export DB_ADDR		?= $(shell jq -r '.db_address.value' infra/db_infra/tfoutput.json)
sample-print: export DB_NAME		?= $(shell jq -r '.db_name.value' infra/db_infra/tfoutput.json)
sample-print: export DB_USER		?= $(shell jq -r '.db_username.value' infra/db_infra/tfoutput.json)
sample-print: export DB_PASS		?= $(shell jq -r '.db_pass.value' infra/db_infra/tfoutput.json)
sample-print:
	@echo "Generate data w/ default scale (1.5M orders) but $$STREAMS update streams"
	@echo "./tpch_pgsql.py -n $(STREAMS)  prepare"
	@echo
	@echo "Load data:"
	@echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) load"
	@echo
	@echo "Apply deltas:"
	@for i in $$(seq 0 $$STREAMS); do echo "./tpch_pgsql.py -H $(DB_ADDR) -U $(DB_USER) -d $(DB_NAME) -W $(DB_PASS) -x $$i deltas"; done

.PHONY: sample-commands
sample-commands: ## Generate sample commands
sample-commands: preflight output/gen sample-print

.PHONY: sync
sync: ## Copy the to the terraformed ec2 instance
sync: export EC2_ADDR		?= $(shell jq -r '.ec2_address.value' infra/db_infra/tfoutput.json)
sync:
	cd .. && \
		rsync \
		-e 'ssh -i aws/infra/db_infra/id_rsa' \
		-au \
		--exclude '.terraform' \
		--delete-excluded \
		$$(pwd) ec2-user@$(EC2_ADDR):~/


.PHONY: connect
connect: ## Connect to the terraformed ec2 instance
	ssh \
		-i infra/db_infra/id_rsa \
		ec2-user@`jq -r '.ec2_address.value' infra/db_infra/tfoutput.json`

.PHONY: help
help: # Makefile Help Page
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[\/\%a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-21s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: guard-%
guard-%: # Util to check env var (e.g. guard-ENV_VAR)
	@if [[ "${${*}}" == "" ]]; then echo "Environment variable $* not set"; exit 1; fi