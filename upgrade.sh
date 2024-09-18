#!/usr/bin/env sh

_pre() {
	test -r /etc/kubernetes/pki/etcd/ca.crt || sudo command -v etcdctl >/dev/null 2>&1 || apt-get install -y etcd-client
}

kube_ver() {
	kubeadm_version=$(sudo kubeadm version --output=short | sed 's/v//')
	IFS='.'
	set -- $kubeadm_version
	kube_ver_1=$1
	kube_ver_2=$2
	kube_ver_3=$3
}

apt_ver() {
	export apt_version=$(sudo apt-cache policy kubeadm | grep -i 'candidate' | awk '{print $2}' | sed 's/\-.\.1//')
	IFS='.'
	set -- $apt_version
	apt_ver_1=$1
	apt_ver_2=$2
	apt_ver_3=$3
}

print_ver() {
	printf "kubeadm version:\n"
	printf "major ver: $kube_ver_1\n"
	printf "minor ver: $kube_ver_2\n"
	printf "patch ver: $kube_ver_3\n"

	printf "apt version:\n"
	printf "major ver: $apt_ver_1\n"
	printf "minor ver: $apt_ver_2\n"
	printf "patch ver: $apt_ver_3\n"
}

version_check() {
	kube_ver
	apt_ver
	if [ "$apt_ver_1" -gt "$kube_ver_1" ]; then
		exit 1
	elif [ "$apt_ver_1" -ne "$kube_ver_1" ]; then
		printf "Major Version Changed from $kube_ver_1 to $apt_ver_1, please upgrade manually\n" &&
			exit 1
	elif [ "$apt_ver_2" -gt "$kube_ver_2" ]; then
		printf "Minor Version Changed from $kube_ver_2 to $apt_ver_2\n" &&
			printf "This upgrade path hasn't been implemented yet" && exit 1
	elif [ "$apt_ver_3" -gt "$kube_ver_3" ]; then
		printf "Patch Version Changed from $kube_ver_3 to $apt_ver_3, proceeding..\n"
	fi
}

minor_upgrade() {
	sudo current_version=$(kubeadm version --output=short | sed 's/v//')
	sudo echo "New Minor Release Selected"
	sudo cp -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/sources.list.d/.kubernetes.list.bak
	sudo sed -i "s/v$current_version/v$selected_version/" /etc/apt/sources.list.d/kubernetes.list
}

upgrade() {
	INIT_CTR=""
	test -r /etc/kubernetes/pki/etcd/ca.crt || export INIT_CTR="$(ETCDCTL_API=3 sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key member list | head -n1 | awk '{print $3}' | cut -d, -f1)"

	sudo apt-get update
	sudo apt-mark unhold kubeadm
	sudo apt-get -y upgrade kubeadm

	export CTR_HOSTNAME="$(hostname)"

	if [ "$INIT_CTR" = "$CTR_HOSTNAME" ]; then
		export ADM_VERSION=$(kubeadm version --output=short)
		kubeadm upgrade plan
		kubeadm upgrade apply "$ADM_VERSION" -y
	else
		kubeadm upgrade node
	fi

	sudo apt-mark unhold kubelet kubectl
	sudo apt-get -y upgrade kubelet kubectl
	sudo apt-mark hold kubeadm kubelet kubectl
	sudo systemctl restart kubelet
}

main() {
	_pre
	version_check

	printf "this utility will upgrade kubernetes from the $kubeadm_version to $apt_version\n"
	printf "please ensure $INIT_CTR is upgraded before continuing\n"
	printf "would you like to continue?"

	read -r prompt
	case $prompt in
	"y" | "Y") version_check && upgrade_node ;;
	"n" | "N") exit 1 ;;
	*) exit 1 ;;
	esac
}

main
