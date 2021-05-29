# Requirements
* terraform
* jq
* aws
* docker

# Usage
* `make create` - creates all of the necessary resources for db benchmarking. 
* `make connect` - connects to the ec2 instance 
* `make destroy` - destroys all of the created components
* `make info` - lists the addresses and credentials from tf state

# Example
First, create AWS resources:
```
make create DB_INSTANCE_TYPE=db.t3.micro  EC2_INSTANCE_TYPE=t2.micro REGION=us-east-2 DB_PASS=handl3bar
```
After all of the resources are created, run:
```
make connect
```
This will get you to the ec2 instance. Then run:
```
./tpch.sh
```
which will create a tpch container, if it doesn't exist, and attach to it. 
Once you're in the tpch container you will have all the tools needed to load data into a database.
# Populating DB with data
1. Generate data w/ default scale (1.5M orders) but 12 update streams
```
# cd tpch-pgsql/
# ./tpch_pgsql.py -n 12  prepare
```
2. Load the data. If you're not sure what is your address/user/password run `make info` from the db_infra directory. 
```
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar load
```
3. Apply deltas

```
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 0 deltas
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 1 deltas
./tpch_pgsql.py -H psqlbenchmarks.<XYZ>>.us-east-2.rds.amazonaws.com -U postgres -d psqlbenchmarks -W handl3bar -x 2 deltas
```
`-x | --delta-stream ` is a 0-based stream number that inserts the batch until max of whatever value we set in step 1 w/ -n - 1 

# Todo 
 * Current terraform definitions create a dedicated VPC. After it is decided in which account/environment this will run, the definitions should use an existing subnet/VPC.
 * Stop/start functionality both for EC2 instance and DB
 * Get AMI ID that works in different AWS regions/accounts.
 * All tests were done only in 157586671174 account, us-east-2 region. To have this working in other accounts the docker image creation and upload process need also to be automated.


 # Future work
 * Replace EC2 instance with K8S or ECS
 * Automate data generation process
 * Store credentials in SSM or other centralized solution
 * Integrate with Jenkins

