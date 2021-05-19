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
  - [Subscriptions](#subscriptions)
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
      - [Binding secrets to Pods](#binding-secrets-to-pods)
      - [Updating AKS](#updating-aks)
      - [Troubleshooting AKS](#troubleshooting-aks)
    - [7. Provisioning a Domain](#7-provisioning-a-domain)
    - [8. Provisioning a Certificate](#8-provisioning-a-certificate)
    - [9. Provisioning a Database](#9-provisioning-a-database)
      - [Database scaling](#database-scaling)
      - [DB users](#db-users)
      - [Connecting to the database](#connecting-to-the-database)
  - [Configurations](#configurations)
    - [Setting up database](#setting-up-database)
    - [Setting up database users](#setting-up-database-users)
    - [Configuring some Kubernetes services](#configuring-some-kubernetes-services)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Preliminaries

- An Azure subscription
- Azure CLI (at least version 2.19.1)
- Docker (with docker-compose)

# Development

When making changes to this codebase, CI automatically runs Github [Super-Linter](https://github.com/github/super-linter) to check the code
format. To run it manually, use `./development.sh lint`.

## How to Run

The deployment scripts are in the form of Ansible playbooks. To run the playbooks, we are using an
extended version of HSL's
[hsldevcom/azure-ansible](https://gitlab.hsl.fi/developer-resources/azure-ansible) docker image that
also contains the `postgresql-client` package.

The container maps the following volumes from the host machine:

- `./ansible` (read-only): to expose the playbooks to Ansible
- `./ansible/.cache` (read-write): to enable caching between runs
- `~/.azure` (read-write): to store the Azure login context
- `~/.ssh/jore4_key_ed25519` and `~/.ssh/jore4_key_ed25519-cert.pub` (read-only): the SSH keys of the
  developer for accessing the bastion host. Most playbooks don't require these SSH keys; the ones that
  do, explicitly mention it. Generate the SSH key
  [based on Wiki](https://github.com/HSLdevcom/jore4/blob/main/wiki/onboarding.md). If you have the
  SSH keys with a different name, edit `docker-compose.ansible.yml` and set a different path for the
  volume mapping

The playbooks are based on HSL's [aks-based](https://gitlab.hsl.fi/platforms/aks-based) platform
model.

To start the Ansible interactive shell for executing the scripts:

```
./start-ansible-shell.sh
```

This will handle the Azure login for you and start the interactive shell in a docker container. To
exit the shell, just type `exit`.

There are preconfigured aliases (`playdev`, `playtest`, `playprod`) in the interactive shell to
simplify running the scripts against a chosen environment.

## Subscriptions

When first logging in to Azure with `az login` (e.g. for your Ansible scripts or for Kubernetes),
your subscription by default will be pointed to the HSL default subscription. To be able to create
and view resources in the JORE4 subscription, you have to point your Azure CLI to the proper
context by using: `az account set --subscription "jore4"`

Note that `start-ansible-shell.sh` and `kubernetes.sh` automatically does this for you.

## Roles

For some scripts, you need to temporarily elevate your role to e.g. create new role bindings for
managed identities. You may do so [here](https://portal.azure.com/#blade/Microsoft_Azure_PIMCommon/ActivationMenuBlade/azurerbac/provider/azurerbac).

# Scripts

The following scripts either provision (create) resources to the chosen environment (dev, test,
prod) or configure them. They don't necessarily need to be done in this order, however it's advised
to do so as they have dependencies between each other.

If the given resources with the same name already exist, they are overwritten with the resources
described by the scripts. Other resources are not modified or delete unless explicitly mentioned in
the script description. Exceptions to this are the public and application gateway network security
groups (NSG), see
[1. Provisioning resource groups and network](#1-provisioning-resource-groups-and-network) for details.

_For simplicity, the scripts below are only showing what happens in the DEV environment. The exact
same outcome is expected when using the `playtest` and `playprod` aliases._

Note that in ARM deployments, the `ansible: workaround` tag has to be used in order to prevent the
removal of all tags of the resource group due to a bug in the ansible ARM plugin.

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

Note that the public and application gateway network security groups (NSG) are only deployed if they
don't exist yet. This allows for manual modifications like custom firewall settings to survive later
re-deployments.

The routing table `jore4-route` is configured on all subnets in order to be able to restrict the
traffic between the subnets and the peered vnet hosting the jore3 database. The traffic is
restricted by a firewall which is not part of the jore4 subscription or setup. Without setting
the `jore4-route` table explicitly, all traffic would be routed freely between the subnet in
question and the peered vnet hosting the jore3 database.

When adding a new subnet, make sure to apply the `jore4-route` routing table to it as well.

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
- configure the bastion host to route Jore3 test db traffic via the private subnet,
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

As the full playbook is quite long, you may use the following tags to limit the parts you want to
execute:

```
playdev play-provision-aks.yml --tags deploy-cluster
playdev play-provision-aks.yml --tags agic-preview-fixes
playdev play-provision-aks.yml --tags aci-fixes
playdev play-provision-aks.yml --tags keyvault-identity-binding
```

Requires Owner role to run as playbook assigns role bindings as well. To temporarily acquire the
Owner role, see [Roles](#roles).

As of now, only jore4-developers group are set to have access to the cluster.

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
services to the Kubernetes cluster, see [jore4-flux](https://github.com/HSLdevcom/jore4-flux).

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

#### Binding secrets to Pods

We are using [Secret Store CSI Driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure)
to bind secrets from `hsl-jore4-dev-vault` to `hsl-jore4-dev-cluster`.

For authorizing the Kubernetes cluster to access the key-vault, we are using a managed identity
for the Virtual Machine Scale-Set and set the policy in the key-vault to allow this user retrieving
secrets. [More info](https://azure.github.io/secrets-store-csi-driver-provider-azure/configurations/identity-access-modes/system-assigned-msi-mode/)

Azure article itself [suggests](https://docs.microsoft.com/en-us/azure/key-vault/general/key-vault-integrate-kubernetes)
using Pod Identities, however that does not allow Kubernetes to run transparently as it needs the
managed identity's clientId to be entered as parameter.

To set which secrets are mapped to the Pods, use a
[SecretProviderClass](https://azure.github.io/secrets-store-csi-driver-provider-azure/demos/standard-walkthrough/#5-deploy-secretproviderclass)

The secrets are mounted as a volume and show up as read-only text files in the Pods. E.g.

```sh
$ cat /mnt/secrets-store/db-username
dbuser
```

To help applications finding the secrets, the `SECRET_STORE_BASE_PATH` environment variable is set
to point to the directory containing the secret files (`/mnt/secret-store`)

#### Updating AKS

The `aks.arm.json` ARM template contains the `kubeVersion` parameter with which you can set the
desired version for both the Kubernetes Service and the Node Pools. However you cannot jump
versions, you have to do the update one version at a time. For example, from version `1.18.14` you
have to upgrade first to `1.19.9` before you can upgrade to `1.20.5`

To find out the current (DEV) cluster's version, use
`az aks show --name hsl-jore4-dev-cluster --resource-group hsl-jore4-dev --query "kubernetesVersion"`

To find out what versions are available in Azure and what upgrade steps are available, use
`az aks get-versions --location westeurope --output table`

Every time you upgrade to a new version of Kubernetes, you should test (e.g. in the playground
environment) that the CRDs and applications are still compatible, the cluster still deploys without
issues. More information on deploying to Kubernetes at
[jore4-flux](https://github.com/HSLdevcom/jore4-flux). In case of incompatibility or deprecation,
you have to update the given resource to use the latest Kubernetes API.

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

Additionally, the playbook will create a DNS "A" entry for the bastion host of the environment
(`bastion.jore.hsl.fi` for the prod environment, and e.g. `bastion.dev.jore.hsl.fi` for the dev
environment).

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

Note that the subnet for the database has to exist before deployment, otherwise you'll only get
pretty meaningless "Internal server error" and "Conflict" error messages ;)

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

### Setting up database

Preliminaries:

- Bastion host is provisioned
- Database is provisioned
- Own SSH key is generated [based on Wiki](https://github.com/HSLdevcom/jore4/blob/main/wiki/onboarding.md)
  to access the bastion host.

`playdev play-configure-database.yml`

- Will set up a temporary SSH tunnel to the PostgreSQL instance
- Will connect to the `postgres` database within the instance using db admin credentials
  from `hsl-jore4-dev-vault`. (That were generated with the database provisioning playbook)
- Will create the `jore4dev` database in PostgreSQL

### Setting up database users

Preliminaries:

- Bastion host is provisioned
- Database is provisioned
- Own SSH key is generated [based on Wiki](https://github.com/HSLdevcom/jore4/blob/main/wiki/onboarding.md)
  to access the bastion host.
- `jore4dev` database is created within the database instance

`playdev play-configure-db-users.yml`

- Will set up a temporary SSH tunnel to the PostgreSQL instance
- Will connect to the `jore4dev` database within the instance using db admin credentials
  from `hsl-jore4-dev-vault`. (That were generated with the database provisioning playbook)
- Will generate usernames and passwords and place them to `hsl-jore4-dev-vault` (`db-hasura-username`,
  `db-hasura-password`, `db-jore3importer-username`, `db-jore3importer-password`, etc.)
- Will create `dbhasuradev` and `dbjore3importer` database users in the `jore4dev` database
- Sets up permissions for these application users

### Configuring some Kubernetes services

Sets up necessary configurations that are required by Kubernetes services to run.

`playdev play-configure-kubernetes-services.yml`

- Creates admin secret for Hasura service to the DEV key-vault with the name
  `hsl-jore4-hasura-admin-secret`.
