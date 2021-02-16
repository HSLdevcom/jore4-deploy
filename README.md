<!-- npx doctoc README.md -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [jore4-deploy](#jore4-deploy)
  - [Preliminaries](#preliminaries)
  - [How to Run](#how-to-run)
  - [Scripts](#scripts)
    - [1. Provisioning resource groups and network](#1-provisioning-resource-groups-and-network)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# jore4-deploy

Deployment scripts for provisioning and configuring JORE4 infrastructure in Azure.

## Preliminaries

- An Azure subscription
- Azure CLI (at least version 2.19.1)
- Docker (with docker-compose)

## How to Run

The deployment scripts are in the form of Ansible playbooks. To run the playbooks, we are using the
[hsldevcom/azure-ansible](https://gitlab.hsl.fi/developer-resources/azure-ansible) docker image.

The scripts are based on HSL's [server-based](https://gitlab.hsl.fi/platforms/server-based) platform
base.

To start the Ansible interactive shell for executing the scripts:

```
start-interactive-shell.sh
```

This will handle the Azure login for you and start the interactive shell in a docker container. To
exit the shell, just type `exit`.

There are preconfigured aliases (`playdev`, `playtest`, `playprod`) in the interactive shell to
simplify running the scripts against a chosen environment.

## Scripts

The following scripts either provision (create) resources to the chosen environment (dev, test,
prod) or configure them. They don't necessarily need to be done in this order, however it's advised
to do so as they have dependencies between each other.

If the given resources with the same name already exist, they are overwritten with the resources
described by the scripts. Other resources are not modified or delete unless explicitly mentioned in
the script description.

_For simplicity, the scripts below are only showing what happens in the DEV environment. The exact
same outcome is expected when using the `playtest` and `playprod` aliases._

### 1. Provisioning resource groups and network

Run in Ansible shell:

```
playdev play-provision-rg-and-nets.yml
```

Creates the `hsl-jore4-common` and `hsl-jore4-dev` resource groups.

- `hsl-jore4-common` is meant to store common resources (e.g. TLS certificate, automations, common
  secrets)
- `hsl-jore4-dev` is meant to store resources that are only for the DEV environment (e.g. DEV
  secrets, DEV Kubernetes cluster, DEV database)

Creates basic network setup:

- `hsl-jore4-dev-vnet`
  - `hsl-jore4-dev-subnet-private` (private subnet to deploy internal resources to (e.g. Kubernetes
    cluster))
  - `hsl-jore4-dev-subnet-public` (public subnet to allow access from outside (e.g. from bastion
    host))
  - `hsl-jore4-dev-subnet-gateway` (public subnet to allow access from Internet (e.g. from HTTPS))

The subnets can freely access resources between each other.
