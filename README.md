# jore4-deploy

Deployment scripts for provisioning and configuring JORE4 infrastructure in Azure.

# Table of Contents

<!-- regenerate with: npx doctoc README.md -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Preliminaries](#preliminaries)
- [How to Run](#how-to-run)
- [Roles](#roles)
- [Scripts](#scripts)
  - [Provisioning](#provisioning)
    - [1. Provisioning resource groups and network](#1-provisioning-resource-groups-and-network)
    - [2. Provisioning key vaults](#2-provisioning-key-vaults)
    - [3. Provisioning a log workspace](#3-provisioning-a-log-workspace)
    - [4. Provisioning an application gateway](#4-provisioning-an-application-gateway)
    - [5. Provisioning a Kubernetes cluster](#5-provisioning-a-kubernetes-cluster)
      - [Configuration](#configuration)
      - [Docker images](#docker-images)
      - [Networking](#networking)
      - [Nodes, ACI burst](#nodes-aci-burst)
      - [Application Gateway Ingress Controller](#application-gateway-ingress-controller)
      - [Accessing the Cluster](#accessing-the-cluster)
      - [Troubleshooting](#troubleshooting)
  - [Configuration](#configuration-1)
    - [Adding services to Kubernetes cluster](#adding-services-to-kubernetes-cluster)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Preliminaries

- An Azure subscription
- Azure CLI (at least version 2.19.1)
- Docker (with docker-compose)
- Kubectl and Helm (for deployments to Kubernetes)
- Fluxcd, Kustomize (for setting up automatic deployments to Kubernetes)

# How to Run

The deployment scripts are in the form of Ansible playbooks. To run the playbooks, we are using HSL's
[hsldevcom/azure-ansible](https://gitlab.hsl.fi/developer-resources/azure-ansible) docker image.

The scripts are based on HSL's [aks-based](https://gitlab.hsl.fi/platforms/aks-based) platform model.

To start the Ansible interactive shell for executing the scripts:

```
./start-interactive-shell.sh
```

This will handle the Azure login for you and start the interactive shell in a docker container. To
exit the shell, just type `exit`.

There are preconfigured aliases (`playdev`, `playtest`, `playprod`) in the interactive shell to
simplify running the scripts against a chosen environment.

# Roles

For some scripts, you need to temporarily elevate your role to e.g. create new role bindings for
managed identities. You may do so here:
https://portal.azure.com/#blade/Microsoft_Azure_PIMCommon/ActivationMenuBlade/azurerbac/provider/azurerbac

# Scripts

The following scripts either provision (create) resources to the chosen environment (dev, test,
prod) or configure them. They don't necessarily need to be done in this order, however it's advised
to do so as they have dependencies between each other.

If the given resources with the same name already exist, they are overwritten with the resources
described by the scripts. Other resources are not modified or delete unless explicitly mentioned in
the script description.

_For simplicity, the scripts below are only showing what happens in the DEV environment. The exact
same outcome is expected when using the `playtest` and `playprod` aliases._

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

Creates basic network setup:

- `hsl-jore4-dev-vnet`
  - `hsl-jore4-dev-subnet-private` (private subnet to deploy internal resources to. E.g. Kubernetes
    pods)
  - `hsl-jore4-dev-subnet-private-aci` (private subnet to deploy ACI resources to. E.g. Kubernetes
    ACI burst containers)
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

### 4. Provisioning an application gateway

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
Kubernetes cluster. More info at:
https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview

### 5. Provisioning a Kubernetes cluster

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

#### Troubleshooting

For troubleshooting, see article:
https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-troubleshoot

If you see Authorization errors in the AGIC pod logs
(`kubectl logs ingress-appgw-deployment-xxxx --namespace kube-system`), they probably originate from
the fact that the controller was created before the permissions were assigned in the playbook. Try
restarting the AGIC controller by setting the number of replicas first to 0 and then 1.
`kubectl scale deployment ingress-appgw-deployment --replicas=0 --namespace kube-system`

## Configuration

### Adding services to Kubernetes cluster

Adding/updating Kubernetes services does not need Ansible. To deploy JORE4 to Kubernetes from your
local machine, run `./deploy-to-kubernetes.sh` and choose the environment to log in to. Follow the
instructions in the command line.

The JORE4 Kubernetes services are deployed to the `hsl-jore4` namespace. All other controllers (AGIC,
ACI pods) can be found from the `kube-system` namespace.

For troubleshooting, visit `hsl-jore4-dev-cluster` in Azure Portal and see if all Services and
Ingresses are up. Could also check the pods under Workloads menu.

For debugging with command line, first need to log in to Azure `az login` and then to the proper
Kubernetes cluster
`az aks get-credentials --resource-group hsl-jore4-dev --name hsl-jore4-dev-cluster --overwrite-existing`

To see JORE4 pods, use `kubectl get pods --namespace hsl-jore4`, for system pods:
`kubectl get pods --namespace kube-system`. To check logs, use:
`kubectl logs [pod id] --namespace [hsl-jore | kube-system]`

### Setting up Flux

#### Installing Flux to the cluster

Based on: https://toolkit.fluxcd.io/guides/installation/#generic-git-server

1. install cli
   `https://toolkit.fluxcd.io/guides/flux-v1-migration/#install-flux-v2-cli`

2. generate manifests for setting up fluxcd system in kubernetes
   `flux install --network-policy=false --export > clusters/test/flux-system/gotk-components.yaml`

3. log in to kubernetes (az login, az aks get-credentials)

4. apply manifests to set up fluxcd in kubernetes cluster
   `kubectl apply -f clusters/test/flux-system/gotk-components.yaml`

5. check that flux is up and running in the cluster
   `flux check`

6. set up flux monitoring to repository
   flux create source git flux-system \
    --url=https://github.com/HSLdevcom/jore4-deploy \
    --branch=fluxcd \
    --interval=30s \
    --export > kubernetes/flux-system/flux-git.yaml

7. set up flux kustomization
   flux create kustomization flux-system \
   --source=flux-system \
   --path="./clusters/test" \
   --prune=true \
   --interval=30s \
   --export > kubernetes/flux-system/flux-kustomize.yaml

8. Flux is now set up and will monitor the git repository for changes
9. To fix the flux sync manually, change settings in the yaml files and use kubectl apply -f ...

10. Just set it up in a new kube system with kubectl apply -k kubernetes/flux-system

Helm chart as github pages

#### Troubleshooting

If the flux controllers don't start... if pods are stuck in pending, you may need to increare the number of nodes that are assigned for Kubernetes

uninstall flux with `flux uninstall --namespace=flux-system`

Cannot delete flux-system namespace
Trick : 1

`kubectl get namespace flux-system -o json > tmp.json`

then edit tmp.json and remove "kubernetes"

Open another terminal and Run `kubectl proxy`

`curl -k -H "Content-Type: application/json" -X PUT --data-binary @tmp.json https://localhost:8001/api/v1/namespaces/flux-system/finalize`
