#!/usr/bin/env sh
set -x
kubeadm_version=$(kubeadm version --output=short | sed 's/v//')
apt_version=$(apt-cache policy kubeadm | grep -i 'candidate' | awk '{print $2}' | sed 's/\-.\.1//')

command -v etcdctl >/dev/null 2>&1 || echo >&2 "I require the etcd cli before running" && apt-get install -y etcd-client

INIT_CTR="$(ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key member list | head -n1 | awk '{print $3}' | cut -d, -f1)"
CTR_HOSTNAME="$(hostname)"

kube_ver() {
	IFS='.'
	set -- $kubeadm_version
	kube_ver_1=$1
	kube_ver_2=$2
	kube_ver_3=$3

	printf "kubeadm version:\n"
	printf "major ver: $kube_ver_1\n"
	printf "minor ver: $kube_ver_2\n"
	printf "patch ver: $kube_ver_3\n"
}

apt_ver() {
	IFS='.'
	set -- $apt_version
	apt_ver_1=$1
	apt_ver_2=$2
	apt_ver_3=$3

	printf "apt version:\n"
	printf "major ver: $apt_ver_1\n"
	printf "minor ver: $apt_ver_2\n"
	printf "patch ver: $apt_ver_3\n"
}

kube_ver
apt_ver

version_check() {
	if [ "$apt_ver_1" -gt "$kube_ver_1" ]; then
		exit 1
	elif [ "$apt_ver_1" -eq "$kube_ver_1" ]; then
		continue
	fi

	if [ "$apt_ver_2" -gt "$kube_ver_2" ] || [ "$apt_ver_3" -gt "$kube_ver_3" ]; then
		echo "Minor/Patch Version Changed, intervention needed." && upgrade_node
	fi
}

upgrade_ctr() {
	KUBEADM_VERSION=$(kubeadm version --output=short)
	apt-mark unhold kubeadm
	apt-get -y upgrade kubeadm

	kubeadm upgrade apply $KUBEADM_VERSION -y
	apt-mark unhold kubelet kubectl
	apt-get -y upgrade kubelet kubectl

	apt-mark hold kubeadm kubelet kubectl

	systemctl restart kubelet
}

upgrade_node() {
	KUBEADM_VERSION=$(kubeadm version --output=short)
	apt-mark unhold kubeadm
	apt-get -y upgrade kubeadm

	kubeadm upgrade node
	apt-mark unhold kubelet kubectl
	apt-get -y upgrade kubelet kubectl

	apt-mark hold kubeadm kubelet kubectl

	systemctl restart kubelet
}

if [ "$INIT_CTR" = "$CTR_HOSTNAME" ]; then
	upgrade_ctr
else
	upgrade_node
fi
