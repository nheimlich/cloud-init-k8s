#!/usr/bin/env sh

command -v triton >/dev/null 2>&1 || echo >&2 "I require the triton cli before running"
command -v fzf >/dev/null 2>&1 || echo >&2 "I require the fzf cli before running."

usage() {
	echo "Usage: $0 <action> [OPTIONS]"
	echo " up      -- create kubernetes cluster"
	echo " down    -- destroy a kubernetes cluster"
	echo " ls      -- show existing clusters"
	echo " config  -- get kubeconfig from an existing cluster"
	echo " upgrade -- upgrade Clusters to a new version"
	echo " bastion -- create a trk8s bastion host"
	exit 1
}

bastion() {
	printf "checking for an existing bastion host..\n"
	bastion=$(triton inst ls -Honame tag.triton.cns.services="bastion")

	if [ -n "$bastion" ]; then
		printf "current bastion:"
		printf "  - (bastion) %s\n" "$bastion" && exit 1
	else
		printf "no bastion found, creating one now..\n" && sleep 1
	fi

	bst_package=$(triton package ls | fzf --header='please select a package size for your bastion instance. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')
	bst_image=$(triton image ls type=zone-dataset os=smartos name='base-64-lts' | sort -k2,2 -k3,3r | fzf --header='please select a image for your bastion-host. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	triton inst create -n {{shortId}}-bastion "$bst_image" "$bst_package" -t triton.cns.services="bastion" -t role="bastion"
}

suffix() {
	printf "For an instance suffix, please type it now (Example: {{shortId}}.suffix), or press enter to skip:\n"
	read -r suffix

	if [ -z "$suffix" ]; then
		echo "Defaulting to no suffix..."
		name_modifier=""
	else
		name_modifier=".$suffix"
	fi
}

ctr() {
	echo "creating control-plane members:"

	triton inst create -n {{shortId}}"$name_modifier" "$image" "$ctr_package" $prd_params -t triton.cns.services="init-$cluster_id,ctr-$cluster_id" -m "ctr_count=$num_ctr" -m "wrk_count=$num_wrk" -m tag="init"

	num_ctr=$((num_ctr - 1))

	for i in $(seq 1 "$num_ctr"); do
		triton inst create -n {{shortId}}"$name_modifier" "$image" "$ctr_package" $prd_params -t triton.cns.services="ctr-$cluster_id" -m tag="ctr"
	done
	wait

}

wrk() {
	echo "creating data plane members:"

	for i in $(seq 1 "$num_wrk"); do
		triton inst create -n {{shortId}}"$name_modifier" "$image" "$wrk_package" $prd_params -t triton.cns.services="wrk-$cluster_id" -t tritoncli.ssh.proxy="$(triton inst ls -Hoshortid tag.role=bastion)" -m tag="wrk" --nic ipv4_uuid="$network"
	done
	wait

}

dev_env() {
	echo "Select a package size for your instance:"
	printf "Press enter to continue"
	read -r _

	dev_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Creating single control plane:"

	triton inst create -n {{shortId}}"$name_modifier" "$image" "$dev_package" $dev_params -m tag="dev" -t triton.cns.services="dev-$cluster_id"
}

prd_env() {
	choice=false

	while [ "$choice" = false ]; do
		echo "How many control plane members would you like to create? (Choose 3, 5, 7, or 9)"
		printf "Enter number of members: "
		read -r num_ctr

		if [ "$num_ctr" = "3" ] || [ "$num_ctr" = "5" ] || [ "$num_ctr" = "7" ] || [ "$num_ctr" = "9" ]; then
			choice=true
		else
			echo "Invalid choice. Please enter 3, 5, 7, or 9."
		fi
	done

	echo "How many data plane members would you like to create? (Choose 1-99)"
	printf "Enter number of members: "
	read -r num_wrk

	ctr_package=$(triton package ls | fzf --header='please select a package size for your control-plane instances. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')
	wrk_package=$(triton package ls | fzf --header='please select a package size for your data-plane instances. CTRL-c or ESC to exit' --layout=reverse-list | awk '{print $1}')

	ctr
	wrk
}

ls_cluster() {
	printf "checking for existing clusters..\n"
	clusterids=$(triton inst ls --json | grep -Eo '\"cluster\"\:\"[a-z0-9]{8}\"' | sed 's/"cluster":"\([a-z0-9]\{8\}\)"/\1/' | sort -u)
	if [ -z "$clusterids" ]; then
		echo "no clusters available"
		exit 1
	else
		printf "current clusters:\n"
		for cluster in $clusterids; do
			control_plane=$(triton inst ls -Honame tag.triton.cns.services="*ctr-$cluster")
			data_plane=$(triton inst ls -Honame tag.triton.cns.services="wrk-$cluster")
			standalone=$(triton inst ls -Honame tag.triton.cns.services="dev-$cluster")
			printf '%s\n' '-----------------------'
			printf "cluster: %s\ninstances:\n" "$cluster"
			if [ -n "$control_plane" ] || [ -n "$data_plane" ]; then
				for i in $control_plane; do printf "  - (control-plane) %s\n" $i; done
				for i in $data_plane; do printf "  - (data-plane) %s\n" $i; done
			elif [ -n "$standalone" ]; then
				printf "  - (standalone) %s\n" "$standalone"
			else
				printf "  - no instances found for cluster %s\n" "$cluster"
			fi
		done
	fi
}

rm_cluster() {
	ls_cluster

	printf "Enter the Cluster-ID you'd like to delete: "
	read -r cluster_id
	instances=$(triton inst ls -Hoshortid tag.cluster="$cluster_id")

	if [ -n "$instances" ]; then
		printf "\nDeleted Instances:\n"
		echo "$instances" | xargs -I {} triton inst rm -f {}
	else
		echo "No instances to delete"
	fi
}

grab_kubeconfig() {
	ls_cluster

	printf "Enter the Cluster-ID you'd like to grab your kubeconfig from: "
	read -r cluster_id

	prd=$(triton inst metadata get "$(triton inst ls -Hoshortid tag.triton.cns.services="init-$cluster_id,ctr-$cluster_id")" admin.conf 2>/dev/null)
	dev=$(triton inst metadata get "$(triton inst ls -Hoshortid tag.triton.cns.services="dev-$cluster_id")" admin.conf 2>/dev/null)

	if [ -z "$prd" ] && [ -z "$dev" ]; then
		printf "no kubeconfig was found for clusterid: %s\n" "$cluster_id" && exit 1
	elif [ -z "$prd" ]; then
		printf "%s" "$dev"
	else
		[ -z "$dev" ]
		printf "%s" "$prd"
	fi
}

main() {
	suffix

	account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
	network=$(triton network ls -Hoid public=false)                    # Fabric Network UUID
	kubernetes_version="1.29.8"
	cluster_id=$(uuidgen | cut -d - -f1 | tr '[:upper:]' '[:lower:]')
	prd_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"
	dev_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"

	echo "Would you like a Development or Production environment? (dev/prod)"
	read -r environment

	image=$(triton image ls type=zvol os=linux | sort -k2,2 -k3,3r | awk '!seen[$2]++' | fzf --header='please select a image for your kubernetes environment. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	case "$environment" in
	"prod") prd_env ;;
	"dev") dev_env ;;
	*) echo "Invalid Input, please select an environment" && exit 1 ;;
	esac

}

ACTION="$1"

if [ "$#" -ne 1 ]; then
	usage
fi

case "$ACTION" in
"up") main ;;
"down") rm_cluster ;;
"ls") ls_cluster ;;
"config") grab_kubeconfig ;;
"upgrade") printf "not implemented yet\n" ;;
"bastion") bastion ;;
*) printf "invalid action.\n" usage ;;
esac
