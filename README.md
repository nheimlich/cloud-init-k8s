## CLOUD INIT K8s /w TRITON

#### REQUIREMENTS:
- Triton cli v7.17.0 or higher
- fzf cli v0.55.0 or higher
- Triton Container Naming Service should be enabled for your account.

#### Goals:

- Bootstrap a fully functional Kubernetes Cluster with Kubeadm using Triton & CNS
- Automate the provisioning & deprovisioning of clusters
- Provide Automation for upgrades

#### TODO:

- automate provisioning of a container registry as a cache for install components `--image-repository`
- configure an apt cache server to remove bottlenecks regarding package retrevial times

#### listing out instances per available cluster

```
❯ ./tk8s.sh ls
current clusters:
-----------------------
cluster: 059b69b4
instances:
  - (standalone) ed205fa5.nhlabs.test
-----------------------
cluster: ae78e3f9
instances:
  - (control-plane) 1862a334.nhlabs.org
  - (control-plane) 8640ffe6.nhlabs.org
  - (control-plane) 283f7b28.nhlabs.org
  - (data-plane) 43b4b466.nhlabs.org
  - (data-plane) 5347243a.nhlabs.org
  - (data-plane) f6dae9dc.nhlabs.org
  - (data-plane) ec652d86.nhlabs.org
  - (data-plane) 4a90cfdc.nhlabs.org
```

#### grabbing admin kubeconfig from a Cluster

```
> ./tk8s.sh config
current clusters:
-----------------------
cluster: ae78e3f9
instances:
  - (control-plane) 1862a334.nhlabs.org
  - (control-plane) 8640ffe6.nhlabs.org
  - (control-plane) 283f7b28.nhlabs.org
  - (data-plane) 43b4b466.nhlabs.org
  - (data-plane) 5347243a.nhlabs.org
  - (data-plane) f6dae9dc.nhlabs.org
  - (data-plane) ec652d86.nhlabs.org
  - (data-plane) 4a90cfdc.nhlabs.org
Enter the Cluster-ID you'd like to grab your kubeconfig from: ae78e3f9
---
apiVersion: v1
****
```

## Addons
### Cloud Load Balancer
##### Cloud Load Balancer Options:
```
❯ ./tk8s.sh clb
Usage: ./tk8s.sh clb [-i] [-d] [-p package] [-g image]
  -i              Run in interactive mode.
  -d              Delete an existing bastion instance.
  -c cluster      Specify the associated cluster.
  -p package      Specify the clb package.
  -e ext_uuid     Specify the external network UUID.
  -n in_uuid      Specify the internal network UUID.
  -r replicas     Specify the number of replicas.
  -f fe_app       Specify the frontend app port.
  -b be_app       Specify the backend app port.
  -x fe_ssl       Specify the frontend SSL port.
  -y be_ssl       Specify the backend SSL port.
  -h              Show this help message.
```
##### Creating a Cloud Load Balancer /w flags
```
❯ ./tk8s.sh clb -c a3de2066 -p 48adbe6c -e 468473cf-6450-455d-b298-4e826a5cfce7 -n 468473cf-6450-455d-b298-4e826a5cfce7
```
##### Creating a Cloud Load Balancer Interactively
```
❯ ./tk8s.sh clb -i
checking for existing clusters..
current clusters:
-----------------------
cluster: 455cca75
instances:
  - (control-plane) f5d0cd06
  - (control-plane) 7e3ecf6e
  - (control-plane) f1438a2a
  - (data-plane) 6fb2a961
-----------------------
cluster: a3de2066
...

Enter the Cluster-ID you'd like to associate with your cloud-load-balancer:
455cca75

ID                                    NAME               SUBNET            GATEWAY        FABRIC  VLAN  PUBLIC
468473cf-6450-455d-b298-4e826a5cfce7  Public-01          -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  Public-02          -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  PRIVATE_123        -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  My-Fabric-Network  192.168.128.0/22  192.168.128.1  true    2     false

Enter the External Network UUID:
468473cf-6450-455d-b298-4e826a5cfce7

ID                                    NAME               SUBNET            GATEWAY        FABRIC  VLAN  PUBLIC
468473cf-6450-455d-b298-4e826a5cfce7  Public-01          -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  Public-02          -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  PRIVATE_123        -                 -              -       -     true
468473cf-6450-455d-b298-4e826a5cfce7  My-Fabric-Network  192.168.128.0/22  192.168.128.1  true    2     false

Enter the Internal Network UUID:
468473cf-6450-455d-b298-4e826a5cfce7

SHORTID   NAME            MEMORY  SWAP   DISK  VCPUS
48adbe6c  lb1.small           4G    8G    50G      4
5b82556d  g1.nano           512M    1G     5G      1
...

Enter the Package Short ID:
48adbe6c

No existing load balancer found, creating a new one...
Cluster: 455cca75
Package: 48adbe6c
Replicas: 2
External Network UUID: 468473cf-6450-455d-b298-4e826a5cfce7
Internal Network UUID: 468473cf-6450-455d-b298-4e826a5cfce7
Frontend Kube API port: 6443
Backend Kube API port: 6443
Frontend SSL port: 443
Backend SSL port: 443
Interactive: true

Would you like to proceed?
y

Creating instance 9529af7f-clb (9529af7f-eaf5-4cc5-a370-a44888950d40, cloud-load-balancer@)
Creating instance 97ae7dee-clb (97ae7dee-46e6-4e83-855e-aa993bfc8907, cloud-load-balancer@)
```
##### Deleting a Cloud Load Balancer
```
❯ ./tk8s.sh clb -d
```
### Bastion (SSH)
##### Bastion Options:
```
Usage: ./tk8s.sh bastion [-i] [-d] [-p package] [-g image]
  -i              Run in interactive mode.
  -d              Delete an existing bastion instance.
  -p package      Specify the bastion package.
  -g image        Specify the bastion image.
  -h              Show this help message.
```
##### Creating a Bastion Instance /w flags
```
❯ ./tk8s.sh bastion -p 5b82556d -g 8adac45a
Checking for an existing bastion host..

Creating instance f47f4d0e-bastion (f47f4d0e-fd99-4ab0-ae98-18e32899df83, base-64-lts@23.4.0)
```
##### Creating a Bastion Instance Interactively
```
❯ ./tk8s.sh bastion -i
checking for an existing bastion host..

SHORTID   NAME            MEMORY  SWAP   DISK  VCPUS
48adbe6c  lb1.small           4G    8G    50G      4
5b82556d  g1.nano           512M    1G     5G      1
...

Enter the desired bastion package:
5b82556d

SHORTID   NAME         VERSION  FLAGS  OS       TYPE          PUBDATE
8adac45a  base-64-lts  23.4.0   P      smartos  zone-dataset  2024-01-06
e44ed3e0  base-64-lts  22.4.0   P      smartos  zone-dataset  2023-01-10
...

Enter the desired bastion image:
8adac45a

Creating instance 967a4b0c-bastion (967a4b0c-30ef-444a-abc5-2b9ee0aa289e, base-64-lts@23.4.0)
```
##### Deleting a Bastion Instance
```
❯ ./tk8s.sh bastion -d
checking for an existing bastion host..

Deleted Instances:
Delete (async) instance 967a4b0c-bastion (967a4b0c-30ef-444a-abc5-2b9ee0aa289e)
```
