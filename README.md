## CLOUD INIT K8s /w TRITON

#### Goals:

- Bootstrap a fully functional Kubernetes Cluster with Kubeadm using Triton & CNS
- Automate the provisioning & deprovisioning of clusters
- Provide Automation for upgrades

#### TODO:

- automate provisioning of a container registry as a cache for install components `--image-repository`
- configure an apt cache server to remove bottlenecks regarding package retrevial times

#### listing out instances per available cluster

```
❯ ./start.sh ls
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
> ./start.sh config
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
