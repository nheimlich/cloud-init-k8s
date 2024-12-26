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
