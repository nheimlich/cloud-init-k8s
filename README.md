## CLOUD INIT K8s /w TRITON

## Requirements
- **Triton CLI**: Version 7.17.0 or higher.
- **Triton Container Naming Service (CNS)**: Must be enabled for your account.

## Features
- Automate Kubernetes cluster provisioning and deprovisioning using Triton and CNS.
- Bootstrap a fully functional Kubernetes cluster with `kubeadm`.
- Provide additional addons such as CLB and a Bastion Host.

## Features
### Script: `tk8s.sh`
A utility script for Cluster provisioning on Triton /w Addons. Actions:
- **up**: Create a Kubernetes cluster.
- **down**: Destroy a Kubernetes cluster.
- **ls**: List existing clusters.
- **config**: Fetch cluster kubeconfig.
- **bastion**: Manage a bastion host.
- **clb**: Manage cloud load balancers.

**Usage**:
```sh
./tk8s.sh <action> [OPTIONS]
 up      -- create kubernetes cluster
 down    -- destroy a kubernetes cluster
 ls      -- show existing clusters
 config  -- get kubeconfig from an existing cluster
 bastion -- manage a trk8s bastion host
 clb     -- manage cloud load balancer services
```
- All actions by default run in interactive mode `-i`, to see additonal options run `./tk8s.sh <action> -h`

**Example: Available CLB options:**
```sh


./tk8s.sh clb -h 

Usage: ./tk8s.sh clb [-i] [-d] [-p package] [-g image]
  -i              Run in interactive mode. (default)
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

### Cloud-Init Configuration
The included `cloud-init` file automates node setup for the Kubernetes cluster.

**Snippet**:
```yaml
#cloud-config
package_update: false
package_upgrade: false

write_files:
  - path: /usr/local/bin/setup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      set -x
      export DEBIAN_FRONTEND=noninteractive
      export k8ver=$(mdata-get k8ver)

      apt-get update && apt-get install -y ca-certificates curl gnupg apt-transport-https
      install -m 0755 -d /etc/apt/keyrings
      curl --retry 5 -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.gpg
      ...
```

For full details, see the `configs/cloud-init` file included in this repository.

## Future Improvements
- Language Rewrite to support lifecycle operations such as Upgrades & Resizing
- Provide options for provisioning different K8s versions

## License
This project is provided "as-is" without warranties. Contributions are welcome.
