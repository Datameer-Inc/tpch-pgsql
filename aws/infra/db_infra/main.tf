provider "aws" {
  default_tags {
    tags = {
      Purpose = "pgsql-dbgen benchmarks"
      Owner   = "DevOps"
    }
  }
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = "benchmarks"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_db_subnet_group" "benchmarks" {
  name       = "benchmarks"
  subnet_ids = module.vpc.public_subnets

  tags = {
    environment = "psql-benchmarks"
  }
}

resource "aws_subnet" "ec2-subnet" {
  vpc_id     = module.vpc.vpc_id
  cidr_block = "10.0.7.0/24"
}


resource "aws_default_route_table" "route_table" {
  default_route_table_id = module.vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc.igw_id
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "Postgres-benchmarks-ec2-sq"
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH traffic from everywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    environment = "psql-benchmarks"
  }
}

resource "aws_security_group" "db_sg" {
  name   = "Postgres-security-group"
  vpc_id = module.vpc.vpc_id
  ingress {
    cidr_blocks     = [var.halle_office, var.sf_office]
    description     = "Allow Postgres traffic from Halle and SF"
    security_groups = [aws_security_group.ec2_sg.id]
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    environment = "psql-benchmarks"
  }
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# generate a private key
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# create aws key
resource "aws_key_pair" "public_key" {
  key_name   = "pqsql-benchmarks-key"
  public_key = tls_private_key.pk.public_key_openssh

  provisioner "local-exec" { # Create a "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.pk.private_key_pem}' > ./pqsql-benchmarks-key.pem && chmod 0400 ./pqsql-benchmarks-key.pem"
  }

  provisioner "local-exec" { # Create a "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.pk.public_key_pem}' > ./pqsql-benchmarks-key.pub && chmod 0644 ./pqsql-benchmarks-key.pub"
  }
}

# S3 bucket removed since it should not be accidentally deleted.
# resource "aws_s3_bucket" "psql_benchmark_data" {
#   bucket = "psql-benchmark-data"
# }

resource "aws_iam_role" "ec2_iam_role" {
  name               = "ec2iamrole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}

resource "aws_iam_instance_profile" "profile" {
  name = "ecr-read"
  role = aws_iam_role.ec2_iam_role.name

}

resource "aws_instance" "ec2-instance" {
  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = var.ec2_instance_type
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.ec2-subnet.id
  key_name                    = aws_key_pair.public_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.profile.name

  root_block_device {
    volume_size = "200"
    tags = {
      "Purpose" = "db_benchmarks"
    }
  }

	user_data = <<EOF
    #! /bin/bash
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo yum install jq git java-11-amazon-corretto-headless postgresql bash-completion -y
    sudo service docker enable
    sudo service docker start
    sudo usermod -a -G docker ec2-user
  EOF

  provisioner "file" {
    source      = "scripts/tpch.sh"
    destination = "/home/ec2-user/tpch.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ec2-user/tpch.sh",
    ]
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.pk.private_key_pem
    host        = self.public_ip
  }

  tags = {
    "name" = "db_benchmarks"
  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_-"
}

resource "aws_db_instance" "psql" {
  # # create new if no target_snapshot_id
  # count = var.target_snapshot_id ? 0 : 1
  allocated_storage      = 200
  engine                 = "postgres"
  engine_version         = "12.5"
  instance_class         = var.rds_instance_type
  name                   = "psqlbenchmarks"
  identifier             = "psqlbenchmarks"
  username               = var.db_username
  password               = random_password.password.result
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.benchmarks.name
}

# resource "aws_db_instance" "psql" {
#   # create from snapshot if target_snapshot_id
#   count = var.target_snapshot_id ? 1 : 0
#   allocated_storage      = 200
#   instance_class         = var.rds_instance_type
#   name                   = "psqlbenchmarks"
#   snapshot_identifier    = var.target_snapshot_id

#   lifecycle {
#     ignore_changes = [snapshot_identifier]
#   }
# }

# hacks to render sensitive values
data "template_file" "db_password" {
  template = aws_db_instance.psql.password
}

data "template_file" "ssh_private_key" {
  template = tls_private_key.pk.private_key_pem
}
