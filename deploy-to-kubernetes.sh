#!/bin/bash

function az_login {
  echo "Logging in the $1 environment"

  az login
  az aks get-credentials --resource-group hsl-jore4-$1 --name hsl-jore4-$1-cluster --overwrite-existing
}

function do_deploy {
  echo "Deploying to the $1 environment"

  # create namespace for jore4 resources
  envsubst < kubernetes/jore4-namespace.yml | kubectl apply --namespace hsl-jore4 -f -

  # change default namespace to hsl-jore4
  kubectl config set-context --current --namespace=hsl-jore4

  # create ingress
  envsubst < kubernetes/jore4-ingress.yml | kubectl apply --namespace hsl-jore4 -f -

  # create backend service
  envsubst < kubernetes/jore4-backend.yml | kubectl apply --namespace hsl-jore4 -f -
}

function show_dialog {
  PS3='Choose the environment to deploy to: '
  envs=("dev" "test" "prod" "quit")
  select env in "${envs[@]}"; do
    case $env in
      "dev")
        echo "Start deployment to DEV environment..."
        az_login $env
        export APPGW_CERTIFICATE_NAME="hsl-jore4-dev-cert"
        export APP_HOSTNAME="dev.jore.hsl.fi"
        do_deploy $env
        break
        ;;
      "test")
        echo "Start deployment to TEST environment..."
        az_login $env
        export APPGW_CERTIFICATE_NAME="hsl-jore4-test-cert"
        export APP_HOSTNAME="test.jore.hsl.fi"
        do_deploy $env
        break
        ;;
      "prod")
        echo "Start deployment to PROD environment..."
        az_login $env
        export APPGW_CERTIFICATE_NAME="hsl-jore4-prod-cert"
        export APP_HOSTNAME="jore.hsl.fi"
        do_deploy $env
        break
        ;;
      "quit")
        echo "User requested exit"
        exit
        ;;
      *) echo "invalid option $REPLY";;
    esac
  done
}

show_dialog
