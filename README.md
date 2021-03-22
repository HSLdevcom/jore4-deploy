<!-- markdownlint-disable MD025 MD040 MD034 -->

# jore4-deploy

Deployment scripts for provisioning and configuring JORE4 infrastructure in Azure.

# Table of Contents

<!-- regenerate with: npx doctoc README.md -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Preliminaries](#preliminaries)
- [Development](#development)
- [How to Run](#how-to-run)
- [Roles](#roles)
- [Scripts](#scripts)
  - [Provisioning](#provisioning)
    - [1. Provisioning resource groups and network](#1-provisioning-resource-groups-and-network)
    - [2. Provisioning key vaults](#2-provisioning-key-vaults)
    - [3. Provisioning a log workspace](#3-provisioning-a-log-workspace)
    - [4. Provisioning a bastion host and configuring it](#4-provisioning-a-bastion-host-and-configuring-it)
    - [5. Provisioning an application gateway](#5-provisioning-an-application-gateway)
    - [6. Provisioning a Kubernetes cluster](#6-provisioning-a-kubernetes-cluster)
      - [Configuration](#configuration)
      - [Docker images](#docker-images)
      - [Networking](#networking)
      - [Nodes, ACI burst](#nodes-aci-burst)
      - [Application Gateway Ingress Controller](#application-gateway-ingress-controller)
      - [Accessing the Cluster](#accessing-the-cluster)
      - [Troubleshooting AKS](#troubleshooting-aks)
    - [7. Provisioning a Domain](#7-provisioning-a-domain)
    - [8. Provisioning a Certificate](#8-provisioning-a-certificate)
    - [9. Provisioning a Database](#9-provisioning-a-database)
      - [Database scaling](#database-scaling)
      - [DB users](#db-users)
      - [Connecting to the database](#connecting-to-the-database)
  - [Configurations](#configurations)
    - [Adding services to Kubernetes cluster](#adding-services-to-kubernetes-cluster)
    - [Setting up Flux](#setting-up-flux)
      - [Concept](#concept)
      - [Kustomize](#kustomize)
      - [Flux cluster directory structure](#flux-cluster-directory-structure)
      - [Installing Flux to the cluster](#installing-flux-to-the-cluster)
      - [Generate Flux configurations](#generate-flux-configurations)
      - [Deploying things manually to the Kubernetes cluster](#deploying-things-manually-to-the-kubernetes-cluster)
      - [Troubleshooting Flux](#troubleshooting-flux)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Preliminaries

- An Azure subscription
- Azure CLI (at least version 2.19.1)
- Docker (with docker-compose)
- Kubectl and Helm (for deployments to Kubernetes)
- Fluxcd, Kustomize (for setting up automatic deployments to Kubernetes)

# Development

When making changes to this codebase, CI automatically runs Github [Super-Linter](https://github.com/github/super-linter) to check the code
format. To run it manually, use `./development.sh lint`.

# How to Run

The deployment scripts are in the form of Ansible playbooks. To run the playbooks, we are using HSL's
[hsldevcom/azure-ansible](https://gitlab.hsl.fi/developer-resources/azure-ansible) docker image.

The scripts are based on HSL's [aks-based](https://gitlab.hsl.fi/platforms/aks-based) platform model.

To start the Ansible interactive shell for executing the scripts:

```
./start-ansible-shell.sh
```

This will handle the Azure login for you and start the interactive shell in a docker container. To
exit the shell, just type `exit`.

There are preconfigured aliases (`playdev`, `playtest`, `playprod`) in the interactive shell to
simplify running the scripts against a chosen environment.

# Roles

For some scripts, you need to temporarily elevate your role to e.g. create new role bindings for
managed identities. You may do so [here](https://portal.azure.com/#blade/Microsoft_Azure_PIMCommon/ActivationMenuBlade/azurerbac/provider/azurerbac).


# Scripts

The following scripts either provision (create) resources to the chosen environment (dev, test,
prod) or configure them. They don't necessarily need to be done in this order, however it's advised
to do so as they have dependencies between each other.

If the given resources with the same name already exist, they are overwritten with the resources
described by the scripts. Other resources are not modified or delete unless explicitly mentioned in
the script description.

_For simplicity, the scripts below are only showing what happens in the DEV environment. The exact
same outcome is expected when using the `playtest` and `playprod` aliases._

# Subscriptions

When first logging in to Azure with `az login` (e.g. for your Ansible scripts or for Kubernetes),
your subscription by default will be pointed to the HSL default subscription. To be able to create
and view resources in the JORE4 subscription, you have to point your Azure CLI to the proper
context by using: `az account set --subscription "jore4"`

Note that `start-ansible-shell.sh` and `kubernetes.sh` automatically does this for you.

## Provisioning

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
- resources in the `hsl-jore4-test` and `hsl-jore4-prod` resource groups (created using the
  `playtest` or `playprod` aliases) as well as resources in the `hsl-jore4-common` resource group
  will be deletion protected using a CanNotDelete-lock, the lock is created via the
  `lock: cannotdelete`-tag
- resources in the `hsl-jore4-dev` resource group are not protected by such a lock
- use the Owner-role in order to remove the lock and to be able to delete resources, for more
  information, see [Roles](#roles)
- for more information on the locking mechanism, see the
  [HSL Azure dashboard](https://portal.azure.com/#@hslfi.onmicrosoft.com/dashboard/arm/subscriptions/b13714ed-2c1b-416c-89a9-909524515193/resourcegroups/dashboards/providers/microsoft.portal/dashboards/bcea8162-492c-4428-ba8c-19321eceb0cd)

Creates basic network setup:

- `hsl-jore4-dev-vnet`
  - `hsl-jore4-dev-subnet-private` (private subnet to deploy internal resources to. E.g. Kubernetes
    pods)
  - `hsl-jore4-dev-subnet-private-aci` (private subnet to deploy Kubernetes ACI burst containers to.
    Delegated to Microsoft.ContainerInstance/containerGroups)
  - `hsl-jore4-dev-subnet-private-db` (private subnet to deploy database and its failovers to.
    Delegated to Microsoft.DBforPostgreSQL/flexibleServers)
  - `hsl-jore4-dev-subnet-public` (public subnet to allow access from outside. E.g. from bastion
    host)
  - `hsl-jore4-dev-subnet-gateway` (public subnet to allow access from Internet. E.g. HTTP requests)

The subnets can freely access resources between each other.

### 2. Provisioning key vaults

Run in Ansible shell:

```
playdev play-provision-key-vault.yml
```

Provisions a common and an environment-specific Azure Key Vault and users to access them with.

- In `hsl-jore4-common` resource group:
  - `hsl-jore4-common-vault` is meant to store common secrets (e.g. TLS certificate)
  - `hsl-jore4-common-vault-user` is a managed identity with READ permissions that can be used to
    access secrets from this vault. E.g. by the application gateway to fetch the certificate.
- In `hsl-jore4-dev` resource group:
  - `hsl-jore4-dev-vault` is environment-specific and is used for storing secrets the
    application needs
  - `hsl-jore4-dev-vault-user` is a managed identity with READ permissions that can be used to
    access secrets from this vault.

If the play complains about an existing soft-deleted Key Vault, re-run the play with
`-e key_vault_create_mode=recover`.

_Note that key vault's access policies are reset whenever you run this playbook. So if you manually
added access policies, they will disappear. This is a limitation of Azure (4.2.2020)._

### 3. Provisioning a log workspace

```
playdev play-provision-log-analytics.yml
```

Provisions an Azure Log Analytics workspace for the subscription. This is where all logs will be
collected (including the Kubernetes pods logs).

- In `hsl-jore4-common` resource group:
  - `hsl-jore4-log-analytics` is where all the log messages are stored

You should also manually set up Security Center auto-provisioning for the subscription ("jore4").
See https://docs.microsoft.com/en-us/azure/security-center/security-center-enable-data-collection

### 4. Provisioning a bastion host and configuring it

To provision the bastion host, run

```
playdev play-provision-bastion-host.yml
```

This will

- create a virtual machine that has network interfaces in both private and public subnets of the
  vnet created by `play-provision-rg-and-nets.yml`,
- assign a public IP to that VM's public subnet network interface,
- download the developer team CA public key from the common key vault and
- install the CA public key on the bastion host to enable project members to log in.

For initial deployment of the CA public key, the ansible environment's public SSH key is used. If
the project CA keypair is changed at a later stage, it has to be updated manually on the bastion
host in the files

- /etc/ssh/ca.pub and
- /home/hsladmin/.ssh/authorized_keys

For instructions on how to connect to the bastion host, see the
[Wiki](https://github.com/HSLdevcom/jore4/blob/main/wiki/onboarding.md).

The playbook `play-provision-bastion-host.yml` and its roles and templates have been adopted from
the playbooks `play-provision-bastion-host.yml` and `play-configure-server-ssh.yml` found in the
the [server-based](https://gitlab.hsl.fi/platforms/server-based) repository.

### 5. Provisioning an application gateway

```
playdev play-provision-appgateway.yml
```

Provisions an Azure Application Gateway for the DEV environment. This is what does the routing and
load balancing of the HTTP requests.

- In `hsl-jore4-dev` resource group:
  - `hsl-jore4-dev-appgw` is the application gateway to serve the services of the DEV environment.
  - `hsl-jore4-dev-appgw-pip` is the public IP address the application gateway will be available on.

Note that when first provisioning this, there are no certificates attached, neither are any listeners
created. Those will be automatically created by Kubernetes's Application Gateway Ingress Controller
(AGIC). AGIC also does all the necessary changes whenever you create/modify/delete services from the
Kubernetes cluster.
See [this](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview) for more info.

Warning: if you rerun this playbook, it will also remove all the existing listeners that AGIC
has created. If happens so, redo the Kubernetes deployment to recreate all the listeners.

### 6. Provisioning a Kubernetes cluster

```
playdev play-provision-aks.yml
```

Requires Owner role to run as playbook assigns role bindings as well. To temporarily acquire the
Owner role, see [Roles](#roles).

_Warning: you may need to rerun the playbook a few times, as some resources (e.g. managed
identities) are created dynamically while&after Kubernetes is spinning up and the later half of the
playbook wants to reference them. E.g. AGIC principal id might be missing._

The following resources and resource group are created:

- `hsl-jore4-dev` resource group:
  - `hsl-jore4-dev-cluster` is the management resource of the Kubernetes cluster.
- `hsl-jore4-dev-cluster-nodes` resource group that is automatically created and managed by the
  cluster for grouping the resources used by the cluster
  - VMs, load balancers, managed identities...

#### Configuration

Note that this script only provisions the cluster, it does not create services. To see how to add
services to the Kubernetes cluster, see
[Adding services to Kubernetes cluster](#1-adding-services-to-kubernetes-cluster)

#### Docker images

The current setup assumes that Docker Hub will be used as image storage. In case you need a private
registry, see how it's provisioned and configured with AKS at
[aks-based](https://gitlab.hsl.fi/platforms/aks-based) platform model.

#### Networking

This AKS setup uses Azure networking mode and the existing `hsl-jore4-dev-subnet-private` to assign
IP addresses for pods. This is necessary for using AGIC.

#### Nodes, ACI burst

The initial number of nodes is configurable through `az_aks_initial_node_count` variable. If having
a burst in load, the ACI plugin will spin up a temporary instance in seconds and kill it when not
required anymore:
https://docs.microsoft.com/en-us/azure/architecture/solution-ideas/articles/scale-using-aks-with-aci

ACI burst containers are spun up to `hsl-jore4-dev-subnet-private-aci` subnet.

#### Application Gateway Ingress Controller

As AGIC is still in Preview mode, the following steps have to be done once per subscription to
manually enable using this module:

- https://docs.microsoft.com/en-us/azure/application-gateway/tutorial-ingress-controller-add-on-new#prerequisites
- https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity#register-the-enablepodidentitypreview

In short:

- Enable pod identity: `az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService`
- Enable AGIC: `az feature register --name AKS-IngressApplicationGatewayAddon --namespace microsoft.containerservice`
- Wait until above features are registered: `az feature list -o table --query "[?properties.state == 'Registered'].{Name:name,State:properties.state}"`
- Confirm changes and reload provider: `az provider register --namespace Microsoft.ContainerService`

#### Accessing the Cluster

Can only access the created Kubernetes cluster from preconfigured IPs
(`az_bastion_host_trusted_ips` in `env-*.yml`). Access is limited only to the
`jore4-platform-developers` group users for now.

If still having issues with accessing the cluster, check if the `jore4-platform-developers` group
was actually added as an AAD admin group to the cluster:
`az aks show --name hsl-jore4-dev-cluster --resource-group hsl-jore4-dev --query "aadProfile"`
If not, fix it by rerunning the Kubernetes playbook

#### Troubleshooting AKS

For troubleshooting, see [this](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-troubleshoot) article:


If you see Authorization errors in the AGIC pod logs
(`kubectl logs ingress-appgw-deployment-xxxx --namespace kube-system`), they probably originate from
the fact that the controller was created before the permissions were assigned in the playbook. Try
restarting the AGIC controller by setting the number of replicas first to 0 and then 1.
`kubectl scale deployment ingress-appgw-deployment --replicas=0 --namespace kube-system`

### 7. Provisioning a Domain

```
playdev play-provision-dns-zone.yml
```

The following resources and resource group are created:

- `hsl-jore4-dns` resource group:
  - `jore.hsl.fi` is the DNS zone for the application

Will create a root dns record (`jore.hsl.fi`) and an A record ("subdomain") to point to the
Application Gateway's IP address (`dev.jore.hsl.fi -> XX.XX.XX.XX`). Note that to point the root
domain to an IP, the subdomain should be set to `"@"`

Note that these subdomains are not published until they are declared by HSL Administrator at the
domain root (hsl.fi and/or hsldev.com). Domain registrations time to get active, check with
`dig jore.hsl.fi` if it has Azure's DNS servers bound.

Note that this playbook does not delete other subdomains. If you e.g. change a subdomain name, you
have to manually delete the obsolete A record (e.g. from Azure Portal)

Note that you should to configure the Kubernetes ingress such that it only listens to requests from
the given hostname (in the ingress rules spec should specify a hostname):

```
kind: Ingress
[...]
spec:
  rules:
    - host: dev.jore.hsl.fi
      http:
        paths:
[...]
```

### 8. Provisioning a Certificate

You should provision an App Service Certificate manually. There has been attempts to create it
automatically with an ARM template, but it's quite buggy so don't do it! It's now created anyway, so
don't touch it! :)

The App Service Certificate should have the following parameters:

- name: `star-jore-hsl-fi-certificate`
- domain hostname: `*.jore.hsl.fi`
- certificate SKU: `wildcard`
- `hsl-jore4-common` resource group

App Service Certificates renew automatically once a year. This is a wildcard (`*.jore.hsl.fi`)
certificate that applies to all environments. After provisioning, you will need to manually visit
Azure Portal to bind the certificate to the `hsl-jore4-vault` in the `hsl-jore4-common` resource
group. (See
[docs](https://docs.microsoft.com/en-us/azure/app-service/configure-ssl-certificate#import-an-app-service-certificate)).
You also need to wait for domain verification for the certificate by HSL admins (can check its
progress on Azure Portal)

After this is done, verify that the certificate was in fact created and placed to the
`hsl-jore4-vault` as a secret.

To import the certificate to the DEV environment's Application gateway, run the following script:

```
playdev play-configure-certificate.yml
```

This will search for the certificate in the `hsl-jore4-vault` and import it to the Application
Gateway. Note that it is looking for the certificate by type and not by secret name (as the name is
generated dynamically). The imported certificate in the Application Gateway will have the
name: `hsl-jore4-dev-cert`. As it uses a reference to the key-vault, it will automatically renew as
well when the App Service Certificate is updated.

You have to instruct Kubernetes Ingress to use this appgw certificate:

```
[...]
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: hsl-jore4-dev-cert
[...]
```

For troubleshooting the App Service Certificate, it's a good idea to use the [Azure REST API](https://docs.microsoft.com/en-us/rest/api/appservice/appservicecertificateorders/get). Note that
when a certificate is broken (e.g. complains that keyVaultId is null or cannot load the certificate
information on the Azure Portal), then it's best to use the [PATCH endpoint](https://docs.microsoft.com/en-us/rest/api/appservice/appservicecertificateorders/updatecertificate)
for fixing the key-vault binding as the [PUT endpoint](https://docs.microsoft.com/en-us/rest/api/appservice/appservicecertificateorders/createorupdatecertificate)
does not work in every case.

### 9. Provisioning a Database

```
playdev play-provision-database.yml
```

- In `hsl-jore4-dev` resource group:

Provisions a managed PostgreSQL Flexible-server instance for the DEV environment. This offers a
primary database instance in one of the availability zones (AZ) and when the high availability (HA)
parameter is set to Enabled, other secondary hotswap instances are created in the other AZs.

Note that this setup is still in _preview_ in Azure. More information on the service here:
https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/overview

#### Database scaling

Currently, Flexible-server PostgreSQL services can only use fixed-size storage without the option
for auto-grow. As storage is cheap, so it's worth setting a high-enough storage for the database.

When basic parameters (e.g. storage, number of vCores, postgresql version) of the database are
changed, the playbook can be rerun to change these parameters in the running instance. Note that
this might result in a minute-long downtime while the db server is restarted.

More information on scaling here:
https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/postgresql/flexible-server/concepts-compute-storage.md#scale-resources

#### DB users

The playbook checks whether there are existing credentials found for the DB admin user from the
`hsl-jore4-dev-vault`. If not, they get generated and placed to the key-vault automatically.

TODO: currently we only have an admin user for the database, it's a follow-up task to create
application-specific users that are meant to actually run the database queries.

#### Connecting to the database

The database is located in the private subnet, meaning you need to be on VPN and tunnel through the
bastion host.

```
# create tunnel with:
ssh -L 6432:hsl-jore4-dev-db.postgres.database.azure.com:5432 -i ~/.ssh/jore4_key_ed25519 hsladmin@[bastion-host-IP]
# in another terminal, connect to database with (find sql username and password from hsl-jore4-dev-vault):
psql -h localhost -p 6432 -U <admin username> -W postgres
```

Another solution mentioned in this Article
(https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/connect-azure-cli) says it's
possible to connect to the database using `az postgresql flexible-server connect`, however it seems
to be broken (as of 15.3.2021)

## Configurations

### Adding services to Kubernetes cluster

Adding/updating Kubernetes services does not need Ansible. To deploy JORE4 to Kubernetes from your
local machine, run `./kubernetes.sh help`. Follow the instructions in the help. When running
deployments, remember to stay connected to VPN. It's recommended to use Flux (see below) instead of
manual deployments to enable automatic deployments to Kubernetes.

The JORE4 Kubernetes services are deployed to the `hsl-jore4` namespace. All other controllers (AGIC,
ACI, Flux pods) can be found from the `kube-system` namespace and `flux-system` namespace.

For troubleshooting, visit `hsl-jore4-dev-cluster` in Azure Portal and see if all Services and
Ingresses are up. Could also check the pods under Workloads menu.

For debugging with command line, first need to log in to Azure `az login` and then to the proper
Kubernetes cluster
`az aks get-credentials --resource-group hsl-jore4-dev --name hsl-jore4-dev-cluster --overwrite-existing`.
Or just use `./kubernetes.sh login dev`

To see JORE4 pods, use `kubectl get pods --namespace hsl-jore4`, for system pods:
`kubectl get pods --namespace kube-system`. To check logs, use:
`kubectl logs [pod id] --namespace [hsl-jore | kube-system]`

### Setting up Flux

#### Concept

Flux (https://fluxcd.io/) is a Kubernetes extension which keeps on polling sources (git/helm/docker
repositories) for changes. It has to be deployed to a cluster once (see instructions below), then
it will keep on working and updating itself.

Whenever there's a change in the git/helm/docker repositories, it automatically (re)deploys the
desired resources to the cluster. Note that Flux also stores its own components and configurations
as Kubernetes resources, so it also automatically updates its own configuration (sync settings) the
same way as it can redeploy applications.

Flux automatically accesses the cluster from inside, without having to allow an IP address
through the Network Security Group or creating a machine user (service principal) for CI.

Flux periodically (currently every minute) checks for differences in the Kubernetes cluster from the
desired state. When there's a change, it automatically reconciles. As a drawback, this also means
that we cannot (easily) manually deploy a specific random version to the cluster, as flux will
return the cluster to the latest version that matches the version pattern. E.g. if flux is set to
deploy `1.3.x` versions, you cannot manually deploy a 1.2.1 or 1.4.1 version as it will be
reconciled back to 1.3.1.

#### Kustomize

In our case, Kubernetes resources are bundled with Kustomize (https://kustomize.io/), meaning that
we have some base templates (found from `clusters/base`) and then each stage defines their own
patches that apply the necessary changes for the given environment (e.g. `clusters/dev`)

Note the confusing terminology that Kubernetes's `kustomize.config.k8s.io/v1beta1` `Kustomize`
resource is used to bundle resources while flux's `kustomize.toolkit.fluxcd.io/v1beta1` `Kustomize`
resource is used to define source monitoring rules.

#### Flux cluster directory structure

Flux's base components, Kubernetes definitions can be found from
`clusters/base/flux-system/gotk-components.yaml`. The configuration for the monitored repositories
can be found from `clusters/base/flux-system/gotk-sync.yaml`. These files have been generated with
the Flux CLI, see instructions [Generate Flux configurations](#generate-flux-configurations)
section. Naturally, every environment needs to slighty differ in sync configurations, these patches
are found from `clusters/XXX/flux-system/gotk-sync-patch.yaml`

The jore4 Kubernetes application base template is defined in the directory `clusters/base/hsl-jore4`.
This only contains the base template, every stage has to define its own differences. For example
what is the hostname or what docker image to use (e.g. hsldevcom/jore4-frontend:dev-v3.0-4f0127be).
These differences are defined in the directory `clusters/XXX/hsl-jore4`.

#### Installing Flux to the cluster

Preliminaries

- kubectl cli (https://kubernetes.io/docs/tasks/tools/)
- kustomize cli (https://kustomize.io/)
- flux cli (https://fluxcd.io/)

This git repository already has all the Kubernetes resources bootstrapped to set up Flux to DEV,
TEST and PROD environments, there's no need to generate anything.

The `./kubernetes.sh` script contains all the necessary commands and help instructions for you to
set up Flux. In a nutshell:

`./kubernetes.sh login dev`
`./kubernetes.sh deploy:flux dev`

This will:

1. log you in to the dev cluster
1. deploy Flux's Kubernetes definitions (`gotk-components.yaml`)
1. deploy Flux's sync configurations (`gotk-sync.yaml`)
1. Flux will automatically monitor the `main` branch or this git repository and deploy the app(s)
specific to the stage (only hsl-jore4 for now)

#### Generate Flux configurations

Sometimes you might want to generate Flux configurations with the CLI instead of manually editing
the existing `gotk-*.yaml` files. However, I advise that you should manually edit at least the
`gotk-sync.yaml` file instead of generating it, because the Flux CLI is just writing the .yaml file
for you that is already pretty simple to just edit in a text editor. To update Flux however I advise
on using the CLI to update the `gotk-components.yaml` file.

Here are some instructions for the manual bootstrapping process if you want to go through it again,
based on [official documentation](https://toolkit.fluxcd.io/guides/installation/#generic-git-server).

1. log in to kubernetes (az login, az aks get-credentials... or `./kubernetes.sh login dev`)

2. check that Flux prerequisites are ok in the cluster
`flux check --pre`

3. generate manifests for setting up Flux system in kubernetes (monitoring controllers)
`flux install --network-policy=false --export > clusters/base/flux-system/gotk-components.yaml`

4. generate a manifest for this git repository to be monitored as a "source":

```
flux create source git flux-repo \
--url=https://github.com/HSLdevcom/jore4-deploy \
--branch=main \
--interval=1m \
--export > clusters/base/flux-system/gotk-sync.yaml`
```

(this will poll the `main` branch of the `jore4-deploy` repository every minute for changes)

5. generate a manifest for Flux resources itself to be monitored. The monitored directory should
have a `kustomization.yaml` file in it

```
flux create kustomization flux-system-sync \
--source=flux-repo \
--path="./clusters/dev/flux-system" \
--prune=true \
--interval=1m \
--export >> clusters/base/flux-system/gotk-sync.yaml`
```

(this will examine if there are any changes in `clusters/dev/flux-system` from the `jore4-deploy`
git repository every minute.)

6. generate a manifest for kubernetes app resources to be monitored. The monitored directory should
have a `kustomization.yaml` file in it

```
flux create kustomization hsl-jore4-sync \
--source=flux-repo \
--path="./clusters/dev/hsl-jore4" \
--prune=true \
--interval=1m \
--export >> clusters/base/flux-system/gotk-sync.yaml
```

(similarly, this will monitor for changes in the `clusters/dev/hsl-jore4` directory from the
`jore4-deploy` git repository)

#### Deploying things manually to the Kubernetes cluster

As mentioned before, Fluxcd will always revert back to the configuration defined in the repository,
so if you manually deploy either `flux-system` or `hsl-jore4` resources that differ from this
configuration, your changes will be reverted.

_Option no 1_

The laziest solution is just to delete Flux from the cluster with
`flux uninstall --namespace=flux-system`. You can always just redeploy Flux with
`./kubernetes.sh deploy:flux dev`.

_Option no 2_

The nicer solution is to instruct Flux to start monitoring a new branch where you are placing your
currently tested Kubernetes resources. This will also make sure that your changes are constantly
also tested whether they are still compatible with Flux (so you didn't break the sync).

1. Create a new git branch, e.g. `feature-x`
1. Modify the `cluster/dev/flux-system/gotk-sync.yaml` script to start monitoring this `feature-x`
branch. Commit this change to the branch and push it to github.
1. As the deployed Flux at the moment is still monitoring the `main` branch, you have to manually
redeploy the new Flux configuration with `./kubernetes deploy:flux dev` to apply changes.
1. Now you can test your new Kubernetes resources by editing, commiting and pushing your changes.
These will automatically get applied to the DEV environment.
1. Don't forget to do the same steps to set the syncing back to the `main` branch after you are
done.

_Option no 3_

If you want to develop the Kubernetes scripts in a safe environment, you could also use Kind
(Kubernetes in Docker). See instructions [here](https://docs.fluxcd.io/projects/helm-operator/en/stable/contributing/get-started-developing/#prepare-your-environment).

#### Troubleshooting Flux

_Kustomize_

For bundling resources and templating, we use Kustomizations. Unfortunately `kubectl apply -k ...`
uses an old version of Kustomize, so we rather have to build the Kustomizations ourselves and apply
them as patches, like this: `kustomize build clusters/XXX/flux-system | kubectl apply -f -`

To test whether Kustomize builds and patches the templates correctly, just call `kustomize build ...`
pointing to a directory with a `kustomisation.yaml` in it.

_Pods_

Flux is deployed to Kubernetes, it's controllers are run in pods. For checking all pods' status, use
`kubectl get pods -A`. For checking Flux's pods, use `kubectl get pods --namespace flux-system`.
To viewing the logs of a single pod in the Flux namespace, use `kubectl logs XXX --namespace flux-system`.

If the flux pods don't start, you may need to increase the number of nodes that are assigned for
Kubernetes in `ansible/vars/env-dev.yaml` and rerun `play-provision-aks.yaml`. For other
startup-related issues, see the [docs](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-application/).

_Uninstall_

If you want to uninstall Flux from the cluster, simply call `flux uninstall --namespace=flux-system`.

On some rare occasions however the Kubernetes destroy finalizer does not get called and the
namespace does not get deleted. To clean up:

1. retrieve the current namespace manifest with
`kubectl get namespace flux-system -o json > tmp.json`
1. edit `tmp.json` and remove "kubernetes" from finalizers
1. open another terminal and run `kubectl proxy`
1. patch the cluster namespace manifest with
`curl -k -H "Content-Type: application/json" -X PUT --data-binary @tmp.json https://localhost:8001/api/v1/namespaces/flux-system/finalize`

_Flux monitoring_

To see what Kustomizations currently are deployed by Flux, use `watch flux get kustomizations`. If
there's a wrong version deployed:

1. wait for the reconciliation timeout (1 minutes) to pass
1. if still a wrong version, see the Flux controller pods' logs
`kubectl logs XXX-controller-YYY --namespace flux-system`
1. see instructions and caveats from section
[Deploying things manually to the Kubernetes cluster](#deploying-things-manually-to-the-kubernetes-cluster)
