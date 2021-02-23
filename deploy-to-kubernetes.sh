#!/bin/bash

function az_login {
    echo "Logging in the $1 environment"

    az login
    az aks get-credentials --resource-group hsl-jore4-$1 --name hsl-jore4-$1-cluster --overwrite-existing
}

function do_deploy {
    echo "Deploying to the $1 environment"

    # create namespace for jore4 resources
    kubectl apply -f kubernetes/jore4-namespace.yml --namespace hsl-jore4

    # change default namespace to hsl-jore4
    kubectl config set-context --current --namespace=hsl-jore4

    # create ingress
    kubectl apply -f kubernetes/jore4-ingress.yml

    # create backend service
    kubectl apply -f kubernetes/jore4-backend.yml
}

function show_dialog {
    PS3='Choose the environment to deploy to: '
    envs=("dev" "test" "prod" "quit")
    select env in "${envs[@]}"; do
        case $env in
            "dev")
                echo "Start deployment to $env environment..."
                az_login $env
                do_deploy $env
                break
                ;;
            "test")
                echo "Start deployment to $env environment..."
                az_login $env
                do_deploy $env
                break
                ;;
            "prod")
                echo "Start deployment to $env environment..."
                az_login $env
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