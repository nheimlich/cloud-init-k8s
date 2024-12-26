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
	echo " clb     -- create a load balancer service"
	exit 1
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
	image=$(triton image ls type=zvol os=linux | sort -k2,2 -k3,3r | awk '!seen[$2]++' | fzf --header='please select a image for your kubernetes environment. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Select a package size for your instance:"
	printf "Press enter to continue"
	read -r _

	dev_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Creating single control plane:"

	triton inst create -n {{shortId}}"$name_modifier" "$image" "$dev_package" $dev_params -m tag="dev" -t triton.cns.services="dev-$cluster_id"
}

prd_env() {
	choice=false

	image=$(triton image ls type=zvol os=linux | sort -k2,2 -k3,3r | awk '!seen[$2]++' | fzf --header='please select a image for your kubernetes environment. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

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
			load_balancer=$(triton inst ls -Honame tag.triton.cns.services="clb-$cluster")
			data_plane=$(triton inst ls -Honame tag.triton.cns.services="wrk-$cluster")
			standalone=$(triton inst ls -Honame tag.triton.cns.services="dev-$cluster")
			printf '%s\n' '-----------------------'
			printf "cluster: %s\ninstances:\n" "$cluster"
			if [ -n "$control_plane" ] || [ -n "$data_plane" ]; then
				if [ -n "$load_balancer" ]; then
					for i in $load_balancer; do printf "  - (load-balancer) %s\n" $i; done
				fi
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

interactive() {
	suffix
	echo "Would you like a Development or Production environment? (dev/prod)"
	read -r environment

	case "$environment" in
	"prod") prd_env ;;
	"dev") dev_env ;;
	*) echo "Invalid Input, please select an environment" && exit 1 ;;
	esac

}

cloud_load_balancer() {
	unset fe_ctr be_ctr fe_app be_app fe_ssl be_ssl cluster package replicas interactive ext_uuid in_uuid interactive deletion

	# Default values for the options
	fe_ctr=6443         # frontend for kubeapi
	be_ctr=6443         # backend port for kubeapi
	fe_app=80           # frontend for kube app
	be_app=80           # backend for kube app
	fe_ssl=443          # SSL frontend for kube app
	be_ssl=443          # SSL backend for kube app
	cluster=""          # Cluster ID to associate with CLB
	package=""          # Package Size for CLB
	replicas=2          # Default replicas count
	interactive="false" # Interactive mode flag
	ext_uuid=""         # External network UUID
	in_uuid=""          # Internal network UUID
	deletion="false"    # Deletion of CLB instances

	# Parse options
	while getopts "c:p:f:b:x:y:r:e:n:hid" opt; do
		case "$opt" in
		c) cluster="$OPTARG" ;;  # Cluster ID
		p) package="$OPTARG" ;;  # Package Size
		f) fe_app="$OPTARG" ;;   # Frontend app port
		b) be_app="$OPTARG" ;;   # Backend app port
		x) fe_ssl="$OPTARG" ;;   # Frontend SSL port
		y) be_ssl="$OPTARG" ;;   # Backend SSL port
		r) replicas="$OPTARG" ;; # Replicas
		i) interactive="true" ;; # Interactive mode flag
		e) ext_uuid="$OPTARG" ;; # External network UUID
		n) in_uuid="$OPTARG" ;;  # Internal network UUID
		d) deletion="true" ;;    # Deletion of CLB instances
		h) echo "Usage: $0 [-i]|[-d] [-c cluster] [-p package] [-e ext_uuid] [-n in_uuid] [-r replicas] [-f fe_app] [-b be_app] [-x fe_ssl] [-y be_ssl]\n" && exit 0 ;;
		*) echo "Usage: $0 [-i]|[-d] [-c cluster] [-p package] [-e ext_uuid] [-n in_uuid] [-r replicas] [-f fe_app] [-b be_app] [-x fe_ssl] [-y be_ssl]\n" && exit 0 ;;
		esac
	done

	# Shift off processed options
	shift $((OPTIND - 1))

	if [ "$OPTIND" -eq 1 ]; then
		echo "Usage: $0 [-i]|[-d] [-c cluster] [-p package] [-e ext_uuid] [-n in_uuid] [-r replicas] [-f fe_app] [-b be_app] [-x fe_ssl] [-y be_ssl]" &&
			exit 0
	fi

	if [ "$deletion" == "true" ]; then
		# Ask for the cluster ID if not provided
		if [ -z "$cluster" ]; then
			ls_cluster
			printf "Enter the Cluster-ID you'd like to de-associate from your cloud-load-balancer:\n"
			read -r cluster
		fi

		instances=$(triton inst ls -Hoshortid tag.triton.cns.services="clb-$cluster")

		if [ -n "$instances" ]; then
			printf "\nDeleted Instances:\n"
			echo "$instances" | xargs -I {} triton inst rm -f {}
			exit 0
		else
			echo "No instances to delete"
			exit 0
		fi
	fi

	# Check if interactive mode is enabled and ask for cluster if not provided
	if [ "$interactive" == "true" ]; then
		if [ -z "$cluster" ]; then
			ls_cluster
			printf "Enter the Cluster-ID you'd like to associate with your cloud-load-balancer:\n"
			read -r cluster
			clb=$(triton inst ls -Honame tag.triton.cns.services="clb-$cluster")
			if [ -n "$clb" ]; then
				echo "Existing load balancer(s) found. Please delete them before proceeding."
				echo "Usage: ./tk8s -d"
				exit 1
			fi
		fi
		# Ask for the external and internal network UUIDs if not provided
		if [ -z "$ext_uuid" ]; then
			triton network ls -l
			printf "\nEnter the External Network UUID:\n"
			read -r ext_uuid
		fi
		if [ -z "$in_uuid" ]; then
			triton network ls -l
			printf "\nEnter the Internal Network UUID:\n"
			read -r in_uuid
		fi
		if [ -z "$package" ]; then
			(triton package ls)
			printf "\nEnter the Package Short ID:\n"
			read -r package
		fi
		if [ -z "$cluster" ] || [ -z "$ext_uuid" ] || [ -z "$in_uuid" ] || [ -z "$package" ]; then
			echo "Missing required parameters: cluster, ext_uuid, or in_uuid"
			exit 1
		fi
	fi

	if [ -z "$cluster" ] || [ -z "$ext_uuid" ] || [ -z "$in_uuid" ] || [ -z "$package" ]; then
		echo "Missing required parameters: cluster, package, ext_uuid, or in_uuid"
		exit 1
	fi

	clb=$(triton inst ls -Honame tag.triton.cns.services="clb-$cluster")

	if [ -n "$clb" ]; then
		echo "Existing load balancer(s) found. Please delete them before proceeding."
		exit 1
	else
		echo "No existing load balancer found, creating a new one..."
	fi

	# current setup information for confirmation
	echo "Cluster: $cluster"
	echo "Package: $package"
	echo "Replicas: $replicas"
	echo "External Network UUID: $ext_uuid"
	echo "Internal Network UUID: $in_uuid"
	echo "Frontend Kube API port: $fe_ctr"
	echo "Backend Kube API port: $be_ctr"
	echo "Frontend SSL port: $fe_ssl"
	echo "Backend SSL port: $be_ssl"
	echo "Interactive: $interactive"

	printf "\nWould you like to proceed?\n"
	read -r selection
	case "$selection" in
	"n" | "no") exit 1 ;;
	"y" | "yes") continue ;;
	*) echo "Invalid Input, please choose yes/no" && exit 1 ;;
	esac

	int_cns_suffix=$(triton cloudapi "/my/networks/$in_uuid" | grep -o '"svc\.[^",]*' | sed 's/^"//;s/",*$//')
	ext_cns_suffix=$(triton cloudapi "/my/networks/$ext_uuid" | grep -o '"svc\.[^",]*' | sed 's/^"//;s/",*$//')

	app_cns="wrk-$cluster.$int_cns_suffix"
	ctr_cns="ctr-$cluster.$int_cns_suffix"

	# Create load balancer instances
	for i in $(seq 1 "$replicas"); do
		triton inst create cloud-load-balancer $package --name {{shortId}}-clb \
			--network $ext_uuid --network $in_uuid \
			-m cloud.tritoncompute:loadbalancer=true \
			-m cloud.tritoncompute:max_rs="64" \
			-m cloud.tritoncompute:portmap="tcp://$fe_ssl:$app_cns:$be_ssl,tcp://$fe_app:$app_cns:$be_app,tcp://$fe_ctr:$ctr_cns:$be_ctr" \
			-t triton.cns.services="clb-$cluster" -t cluster="$cluster"
	done
}

bastion() {
	unset interactive deletion bastion bst_package bst_image

	# Default values for flag options
	interactive="false" # Interactive Flag
	deletion="false"    # Deletion Flag
	bst_package=""      # Bastion Package
	bst_image=""        # Bastion Image

	usage() {
		echo "Usage: $0 [-i] [-d] [-p package] [-g image]"
		echo "  -i              Run in interactive mode."
		echo "  -d              Delete an existing bastion instance."
		echo "  -p package      Specify the bastion package."
		echo "  -g image        Specify the bastion image."
		echo "  -h              Show this help message."
		exit 1
	}

	# Parse options
	while getopts "p:g:hid" opt; do
		case "$opt" in
		p) bst_package="$OPTARG" ;; # Bastion Package
		g) bst_image="$OPTARG" ;;   # Bastion Image
		i) interactive="true" ;;    # Interactive mode flag
		d) deletion="true" ;;       # Deletion of Bastion Instance
		h) usage ;;
		*) usage ;;
		esac
	done

	# Shift off processed options
	shift $((OPTIND - 1))

	if [ "$OPTIND" -eq 1 ]; then
		usage
	fi

	printf "checking for an existing bastion host..\n"
	bastion=$(triton inst ls -Honame tag.triton.cns.services="bastion")

	if [ -n "$bastion" ]; then
		printf "current bastion:"
		printf "  - (bastion) %s\n" "$bastion" && exit 1
	fi

	if [ "$deletion" == "true" ]; then
		printf "checking for an existing bastion host..\n"
		bastion=$(triton inst ls -Honame tag.triton.cns.services="bastion")
		if [ -n "$bastion" ]; then
			printf "\nDeleted Instances:\n"
			echo "$bastion" | xargs -I {} triton inst rm -f {}
			exit 0
		else
			echo "No instances to delete"
			exit 0
		fi
	fi


	if [ "$interactive" == "true" ]; then
		if [ -z "$bst_package" ]; then
			triton package ls
			printf "\nEnter the desired bastion package:\n"
			read -r bst_package
		fi
		if [ -z "$bst_image" ]; then
			triton image ls type=zone-dataset os=smartos name='base-64-lts' | sort -k2,2 -k3,3r
			printf "\nEnter the desired bastion image:\n"
			read -r bst_image
		fi
		if [ -z "$bst_package" ] || [ -z "$bst_image" ]; then
			echo "Missing required parameters: bst_package or bst_image"
			exit 1
		fi
	fi

	triton inst create -n {{shortId}}-bastion "$bst_image" "$bst_package" -t triton.cns.services="bastion" -t role="bastion"
}

main() {
	account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
	network=$(triton network ls -Hoid public=false)                    # Fabric Network UUID
	kubernetes_version="1.29.8"
	cluster_id=$(uuidgen | cut -d - -f1 | tr '[:upper:]' '[:lower:]')
	prd_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"
	dev_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"

	interactive
}

ACTION="$1"

shift

case "$ACTION" in
"up") main ;;
"down") rm_cluster ;;
"ls") ls_cluster ;;
"config") grab_kubeconfig ;;
"upgrade") printf "not implemented yet\n" ;;
"bastion") bastion "$@" ;;
"clb") cloud_load_balancer "$@" ;;
*) printf "invalid action.\n" && usage ;;
esac
