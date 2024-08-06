## CLOUD INIT K8s /w TRITON ## 

#### Goals:
- Bootstrap a fully functional Kubernetes Cluster with Kubeadm using Triton & CNS
- Automate the provisioning & deprovisioning of clusters
- Provide Automation for upgrades

#### TODO:
- automate provisioning of a container registry as a cache for install components `--image-repository`
- configure an apt cache server to remove bottlenecks regarding package retrevial times