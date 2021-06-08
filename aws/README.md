# AWS Data Generation

This page contains:

- The current status and location of data
- Running tests - how to set up a DB from a snapshot
- Dev Setup - creating the dev envrionment with terraform

## Current Status

Currently we have the raw CSV files in the S3  based on the SCALE factor mentioned in this repository with:

- `scale 0.10` - 150,000 orders (approx 4x the amount in the `linetitem` table)
- `scale 01.0` - 1,500,000 orders (approx 4x the amount in the `linetitem` table)
- `scale 10.0` - 15,000,000 orders (approx 4x the amount in the `linetitem` table)
- `scale 50.0` - 75,000,000 orders (approx 4x the amount in the `linetitem` table)

```shell
root@0bf0282d7053:/tpch-pgsql# wc -l scale0_1/data/*/orders.*
  150000 scale0_1/data/load/orders.tbl.csv
     150 scale0_1/data/update/orders.tbl.u1.csv
     150 scale0_1/data/update/orders.tbl.u2.csv
     150 scale0_1/data/update/orders.tbl.u3.csv
  150450 total

root@0bf0282d7053:/tpch-pgsql# wc -l scale1_0/data/*/orders.*
  1500000 scale1_0/data/load/orders.tbl.csv
     1500 scale1_0/data/update/orders.tbl.u1.csv
     1500 scale1_0/data/update/orders.tbl.u2.csv
     1500 scale1_0/data/update/orders.tbl.u3.csv
  1504500 total

root@0bf0282d7053:/tpch-pgsql# wc -l scale10_0/data/*/orders.*
  15000000 scale10_0/data/load/orders.tbl.csv
     15000 scale10_0/data/update/orders.tbl.u1.csv
     15000 scale10_0/data/update/orders.tbl.u2.csv
     15000 scale10_0/data/update/orders.tbl.u3.csv
     15000 scale10_0/data/update/orders.tbl.u4.csv
  15060000 total

root@0bf0282d7053:/tpch-pgsql# wc -l scale50_0/data/*/orders.*
  75000000 scale50_0/data/load/orders.tbl.csv
     75000 scale50_0/data/update/orders.tbl.u1.csv
     75000 scale50_0/data/update/orders.tbl.u2.csv
     75000 scale50_0/data/update/orders.tbl.u3.csv
     75000 scale50_0/data/update/orders.tbl.u4.csv
     75000 scale50_0/data/update/orders.tbl.u5.csv
     75000 scale50_0/data/update/orders.tbl.u6.csv
  75450000 total
```

## Dev Environment Setup

This describes how, in terraform, to setup a developer environment for creating the datasets.

### Requirements

- terraform
- jq
- aws
- docker

### Usage

- `make tf/plan [tf/apply]` - creates all of the necessary resources for db benchmarking.
- `make connect` - connects to the ec2 instance
- `make tf/destroy` - destroys all of the created components
- `make tf/output` - lists the addresses and credentials from tf state

### Example

First, create AWS resources:

```shell
make tf/plan tf/apply DB_INSTANCE_TYPE=db.t3.micro  EC2_INSTANCE_TYPE=t2.micro REGION=us-east-2
```

After all of the resources are created, run:

```shell
make connect
```

This will get you to the ec2 instance. Then run:

```shell
./tpch.sh
```

which will create a tpch container, if it doesn't exist, and attach to it.
Once you're in the tpch container you will have all the tools needed to load data into a database.

### Preparing the data with SCALE option

```shell
# Prepare
SCALE=0.1 && DATADIR=scale${SCALE//\./_}/data && echo ./tpch_pgsql.py -s $SCALE -i $DATADIR prepare

# Push to S3
SCALE=0.1 && DATADIR=scale${SCALE//\./_}/data && aws s3 sync $DATADIR s3://psql-benchmark-data/tpch-pgsql-data-dumps/$DATADIR
```

### Populating DB with data

1. Generate data w/ default scale (1.5M orders) but 12 update streams

```shell
cd tpch-pgsql/
./tpch_pgsql.py -n 12  prepare
```

2. Load the data. If you're not sure what is your address/user/password run `make info` from the db_infra directory.

```shell
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar load
```

3. Apply deltas

```shell
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 0 deltas
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 1 deltas
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 2 deltas
```

`-x | --delta-stream` is a 0-based stream number that inserts the batch until max of whatever value we set in step 1 w/ -n - 1

## Todo

- Current terraform definitions create a dedicated VPC. After it is decided in which account/environment this will run, the definitions should use an existing subnet/VPC.
- Stop/start functionality both for EC2 instance and DB
- Get AMI ID that works in different AWS regions/accounts.
- All tests were done only in 157586671174 account, us-east-2 region. To have this working in other accounts the docker image creation and upload process need also to be automated.

## Future work

- Replace EC2 instance with K8S or ECS
- Automate data generation process
- Store credentials in SSM or other centralized solution
- Integrate with Jenkins
