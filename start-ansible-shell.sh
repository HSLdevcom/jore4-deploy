#!/bin/bash
AZURE_LOCATION=${AZURE_LOCATION:=~/.azure}

# prefixes containers and networks created by docker-compose with "jore4_infra"
export COMPOSE_PROJECT_NAME=jore4_infra

# allow running from any working directory
WD=$(dirname "$0")
cd "${WD}"

echo "Log in to azure with own user..."
az login
echo "Set active subscription to 'jore4'..."
az account set --subscription "jore4"

docker-compose -f docker-compose.ansible.yml run --rm ansible ./interactive-entrypoint.sh