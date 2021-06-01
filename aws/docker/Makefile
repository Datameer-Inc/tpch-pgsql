MKFILE_DIR			:= $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
.DEFAULT_GOAL		:= help
shell				:= /bin/bash
MAKEFLAGS			+= --no-print-directory

ACCOUNT_ID=`aws sts get-caller-identity  | jq -r .Account`
TAG="$(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com/psql_data_generation:latest"

.PHONY: build
build: ## Build the docker image
	docker build \
		--target final \
		-t $(TAG) \
		../../

.PHONY: run
run: ## Run the docker image
run: build
	docker run --rm -ti $(TAG) bash

.PHONY: login
login: ## Log into ECR
login:
	aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com

.PHONY: create-repo
create-repo: ## Create the ECR repository
	aws ecr create-repository \
	--repository-name psql_data_generation \
	--image-scanning-configuration scanOnPush=false --region us-east-2

.PHONY: push
push: ## Push to docker image
push: build login
	docker push $(TAG)


.PHONY: help
help: # Makefile Help Page
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[\/\%a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-21s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: guard-%
guard-%: # Util to check env var (e.g. guard-ENV_VAR)
	@if [[ "${${*}}" == "" ]]; then echo "Environment variable $* not set"; exit 1; fi