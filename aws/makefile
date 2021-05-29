DB_INSTANCE_TYPE?=db.t3.small
EC2_INSTANCE_TYPE?=t3.micro
REGION?=us-east-2
DB_PASS?=handl3bar

create:
	cd infra/db_infra &&\
	ssh-keygen \
		-f id_rsa \
		-t rsa \
		-N "" &&\
	terraform apply \
		-var="ssh_public_key=`cat id_rsa.pub`"\
		-var="ssh_private_key=`cat id_rsa`"\
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)"\
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)"\
		-var="region=$(REGION)"\
		-var="db_password=$(DB_PASS)"

update:
	cd infra/db_infra &&\
	terraform apply \
		-var="ssh_public_key=`cat id_rsa.pub`"\
		-var="ssh_private_key=`cat id_rsa`"\
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)"\
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)"\
		-var="region=$(REGION)"\
		-var="db_password=$(DB_PASS)"


destroy:
	cd infra/db_infra &&\
	terraform destroy\
		-var="ssh_public_key=`cat id_rsa.pub`"\
		-var="ssh_private_key=`cat id_rsa`"\
		-var="ec2_instance_type=$(EC2_INSTANCE_TYPE)"\
		-var="rds_instance_type=$(DB_INSTANCE_TYPE)"\
		-var="region=$(REGION)"\
		-var="db_password=$(DB_PASS)" &&\
	rm id_rsa*

connect:
	ssh \
		-i infra/db_infra/id_rsa\
		ec2-user@`cd infra/db_infra && terraform output -json | jq -r .ec2_address.value`

info:
	cd infra/db_infra && terraform output
