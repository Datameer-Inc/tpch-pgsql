ACCOUNT_ID=`aws sts get-caller-identity  | jq -r .Account`
TAG="$(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com/psql_data_generation:latest"
build: Dockerfile
	docker build --build-arg SSH_PRIVATE_KEY="`cat ${HOME}/.ssh/id_ed25519`" . --target final -t $(TAG)

run: build
	docker run --rm -ti $(TAG) bash 

login: 
	aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.us-east-2.amazonaws.com

create-repo:
	aws ecr create-repository \
	--repository-name psql_data_generation \
	--image-scanning-configuration scanOnPush=false --region us-east-2

push: build login
	docker push $(TAG)
