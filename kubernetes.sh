#!/bin/bash

set -eu

function az_login {
  echo "Logging in the $1 environment"

  az login
  az account set --subscription "jore4"
  az aks get-credentials --resource-group "hsl-jore4-$1" --name "hsl-jore4-$1-cluster" --overwrite-existing
  kubectl config set-context --current --namespace=hsl-jore4
}

function check_context {
  echo "Checking whether $1 context is active"

  CURRENT_CONTEXT=$(kubectl config current-context)

  [[ "$CURRENT_CONTEXT" == "hsl-jore4-$1-cluster" ]] || {
    echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
    echo >&2 "You should first log in to $1 context to continue."
    exit 1
  }

  echo "$1 context is active, no need to login"
}

function deploy_flux {
  check_context "$1"

  echo "Deploying flux to the $1 environment"

  # first make sure all the flux definitions are applied
  kubectl apply -f clusters/base/flux-system/gotk-components.yaml

  # bundle and configure all resources for flux and deploy
  kustomize build "clusters/$1/flux-system" | kubectl apply -f -
}

function deploy_jore4 {
  check_context "$1"

  echo "Deploying jore4 to the $1 environment"

  # bundle and configure all resources for jore4 and deploy
  kustomize build "clusters/$1/hsl-jore4" | kubectl apply -f -
}

function usage {
  echo "
  Usage $0 <command>

  login [<stage>]
    Logs in to Azure and to the selected Kubernetes environment context.

  check [<stage>]
    Checks whether you are currently logged in to the given context.

  deploy:flux [<stage>]
    Deploys fluxcd for the selected environment. Flux automatically redeploys itself and/or the apps
    configured (e.g. jore4) in when kubernetes yamls change or there are new versions of docker
    images.

  deploy:jore4 [<stage>]
    Manually deploys the jore4 app to the selected environment. Warning: if you are using also flux,
    it might overwrite it when it's reconciling if it sees a different version.

  help
    Show this usage information
  "
}

case $1 in
login)
  az_login "$2"
  ;;

check)
  check_context "$2"
  ;;

deploy:flux)
  deploy_flux "$2"
  ;;

deploy:jore4)
  deploy_flux "$2"
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
