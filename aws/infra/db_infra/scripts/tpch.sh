#!/bin/bash
if [ ! "$(docker ps --format "{{.Names}}" --filter "name=data_generation")" ]; then
  $(aws ecr get-login --region us-east-2 --no-include-email)
  docker run -d --name="data_generation" 157586671174.dkr.ecr.us-east-2.amazonaws.com/psql_data_generation sleep infinity
  docker exec -ti data_generation bash
else
  docker exec -ti data_generation bash
fi
