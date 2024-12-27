#!/usr/bin/env sh

command -v triton >/dev/null 2>&1 || echo >&2 "I require the triton cli before running"

usage() {
	case "$1" in
	main)
		echo "Usage: $0 <action> [OPTIONS]"
		echo " up      -- create kubernetes cluster"
		echo " down    -- destroy a kubernetes cluster"
		echo " ls      -- show existing clusters"
		echo " config  -- get kubeconfig from an existing cluster"
		echo " upgrade -- upgrade Clusters to a new version"
		echo " bastion -- manage a trk8s bastion host"
		echo " clb     -- manage cloud load balancer services"
		exit 1
		;;
	up)
		echo "Usage: $0 up [-i] [-d]"
		echo "  -i              Run in interactive mode. (default)"
		echo "  -d              Delete an existing cluster."
		echo "  -h              Show this help message."
		exit 1
		;;
	down)
		echo "Usage: $0 down [-i] [-c cluster]"
		echo "  -i              Run in interactive mode. (default)"
		echo "  -c              Delete a specific cluster."
		echo "  -h              Show this help message."
		exit 1
		;;
	bastion)
		echo "Usage: $0 bastion [-i] [-d] [-p package] [-g image]"
		echo "  -i              Run in interactive mode."
		echo "  -d              Delete an existing bastion instance."
		echo "  -p package      Specify the bastion package."
		echo "  -g image        Specify the bastion image."
		echo "  -h              Show this help message."
		exit 1
		;;
	clb)
		echo "Usage: $0 clb [-i] [-d] [-p package] [-g image]"
		echo "  -i              Run in interactive mode."
		echo "  -d              Delete an existing bastion instance."
		echo "  -c cluster      Specify the associated cluster."
		echo "  -p package      Specify the clb package."
		echo "  -e ext_uuid     Specify the external network UUID."
		echo "  -n in_uuid      Specify the internal network UUID."
		echo "  -r replicas     Specify the number of replicas."
		echo "  -f fe_app       Specify the frontend app port."
		echo "  -b be_app       Specify the backend app port."
		echo "  -x fe_ssl       Specify the frontend SSL port."
		echo "  -y be_ssl       Specify the backend SSL port."
		echo "  -h              Show this help message."
		exit 1
		;;
	*)
		echo "Invalid usage. Run '$0 main' for the list of commands."
		exit 1
		;;
	esac
}

selection() {
	printf "\nPlease review the information above and confirm.\n"
	printf "Would you like to proceed? (yes/no)\n"
	read -r confirm
	case "$confirm" in
	"yes" | "y") ;;
	"no" | "n") exit 1 ;;
	*) echo "Invalid Input, please choose yes/no" && exit 1 ;;
	esac
}

prompt_for_input() {
	local prompt="$1"
	local var_name="$2"
	local allow_empty="$3"

	while true; do
		printf "\n%s\n" "$prompt"
		read -r input
		if [ -n "$input" ] || [ "$allow_empty" = true ]; then
			eval "$var_name='$input'"
			break
		else
			echo "This value is required. Please try again."
		fi
	done
}

create_cluster() {

	if [ "$environment" == "dev" ]; then
		printf "\nCreating standalone instance:\n"
		triton inst create -n {{shortId}}"$name_modifier" "$image" "$dev_package" $dev_params -m tag="dev" -t triton.cns.services="dev-$cluster_id"

	elif [ "$environment" == "prod" ]; then
		printf "\nCreating control-plane members:\n"
		triton inst create -n {{shortId}}"$name_modifier" "$image" "$ctr_package" $prd_params -t triton.cns.services="init-$cluster_id,ctr-$cluster_id" -m "ctr_count=$num_ctr" -m "wrk_count=$num_wrk" -m tag="init" $ctr_interfaces
		num_ctr=$((num_ctr - 1))
		for i in $(seq 1 "$num_ctr"); do
			triton inst create -n {{shortId}}"$name_modifier" "$image" "$ctr_package" $prd_params -t triton.cns.services="ctr-$cluster_id" -m tag="ctr" $ctr_interfaces
		done
		wait
		printf "\nCreating data-plane members:\n"
		for i in $(seq 1 "$num_wrk"); do
			triton inst create -n {{shortId}}"$name_modifier" "$image" "$wrk_package" $prd_params -t triton.cns.services="wrk-$cluster_id" -t tritoncli.ssh.proxy="$(triton inst ls -Hoshortid tag.role=bastion)" -m tag="wrk" $wrk_interfaces
		done
		wait
	else
		printf "Invalid environment type, please choose dev or prod\n" && exit 1
	fi
}

interactive_k8s() {
	dev_opts() {
		prompt_for_input "Would you like this development instance to be external? (yes/no)?" external false
		case "$external" in
		"n" | "no") external="" ;;
		"y" | "yes") triton network ls -l && prompt_for_input "Enter the External Network UUID:" ext_uuid true ;;
		*) echo "Invalid Input, please choose yes/no" && exit 1 ;;
		esac
		triton package ls
		prompt_for_input "Select a package size for your instance:" dev_package false
	}
	prod_opts() {
		prompt_for_input "Which Instances would you like to have External Interfaces (ctr, wrk, both, none)?" external false
		triton package ls
		prompt_for_input "Select a package size for your control-plane instances:" ctr_package false
		prompt_for_input "Select a package size for your data-plane instances:" wrk_package false
		choice=false
		while [ "$choice" = false ]; do
			prompt_for_input "How many control plane members would you like to create? (Choose 3, 5, 7, or 9)" num_ctr false

			if [ "$num_ctr" = "3" ] || [ "$num_ctr" = "5" ] || [ "$num_ctr" = "7" ] || [ "$num_ctr" = "9" ]; then
				choice=true
			else
				echo "Invalid choice. Please enter 3, 5, 7, or 9."
			fi
		done
		prompt_for_input "How many data plane members would you like to create? (Choose 1-99)" num_wrk false
		if [ "$external" == "ctr" ] || [ "$external" == "both" ] || [ "$external" == "wrk" ]; then
			triton network ls -l
			prompt_for_input "Enter the External Network UUID:" ext_uuid true
		fi
	}
	prompt_for_input "For an instance suffix, please type it now (Example: {{shortId}}.suffix), or press enter to skip:" suffix true
	triton image ls type=zvol os=linux | sort -k2,2 -k3,3r | awk '!seen[$2]++'
	prompt_for_input "Select an image for your kubernetes environment:" image false
	triton network ls -l
	prompt_for_input "Enter the Internal Network UUID:" in_uuid false
	prompt_for_input "Would you like a Development or Production environment? (dev/prod)" environment false
	case "$environment" in
	"dev") dev_opts ;;
	"prod") prod_opts ;;
	*) echo "Invalid Input, please choose dev/prod" && exit 1 ;;
	esac

	if [ -n "$suffix" ]; then
		name_modifier=".$suffix"
	else
		name_modifier=""
	fi

	case "$external" in
	"ctr")
		ctr_interfaces="--nic ipv4_uuid=$in_uuid --nic ipv4_uuid=$ext_uuid"
		wrk_interfaces="--nic ipv4_uuid=$in_uuid"
		;;
	"wrk")
		wrk_interfaces="--nic ipv4_uuid=$in_uuid --nic ipv4_uuid=$ext_uuid"
		ctr_interfaces="--nic ipv4_uuid=$in_uuid"
		;;
	"both")
		ctr_interfaces="--nic ipv4_uuid=$in_uuid --nic ipv4_uuid=$ext_uuid"
		wrk_interfaces="$ctr_interfaces"
		;;
	"dev") dev_interfaces="--nic ipv4_uuid=$in_uuid --nic ipv4_uuid=$ext_uuid" ;;
	esac

	# current setup information for confirmation
	printf "\nCluster: %s\n" $cluster_id
	if [ -n "$suffix" ]; then
		echo "Suffix: $suffix"
	fi
	if [ "$external" == "ctr" ] || [ "$external" == "both" ] || [ "$external" == "wrk" ] || [ "$external" == "dev" ]; then
		echo "External: true"
		echo "External Network UUID: $ext_uuid"
	fi

	if [ "$environment" == "dev" ]; then
		echo "Standalone package: $dev_package"
	else
		echo "Control-plane package: $ctr_package"
		echo "Data-plane package: $wrk_package"
		echo "Number of control-plane instances: $num_ctr"
		echo "Number of data-plane instances: $num_wrk"
	fi

	echo "Internal Network UUID: $in_uuid"
	echo "Environment: $environment"
	echo "Image: $image"

	selection

	create_cluster
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
	unset interactive cluster_id instances

	# Default values for flag options
	cluster_id=""       # Cluster ID
	instances=""        # Instances to delete
	interactive="false" # Interactive Flag

	if [ "$#" -eq 0 ]; then
		interactive="true"
	elif [ "$#" -ne 0 ]; then
		while getopts "c:hi" opt; do
			case "$opt" in
			c) cluster_id="$OPTARG" ;; # Bastion Package
			i) interactive="true" ;;   # Interactive mode flag
			h) usage down ;;
			*) usage down ;;
			esac
		done
	fi

	if [ "$interactive" == "true" ]; then
		ls_cluster
		printf "Enter the Cluster-ID you'd like to delete: "
		read -r cluster_id
	fi

	instances=$(triton inst ls -Hoshortid tag.cluster="$cluster_id")

	printf "Instances to be deleted:\n%s" "$instances"

	selection

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
	while getopts "c:p:e:n:r:f:b:x:y:hid" opt; do
		case "$opt" in
		c) cluster="$OPTARG" ;;  # Cluster ID
		p) package="$OPTARG" ;;  # Package Size
		e) ext_uuid="$OPTARG" ;; # External network UUID
		n) in_uuid="$OPTARG" ;;  # Internal network UUID
		r) replicas="$OPTARG" ;; # Replicas
		f) fe_app="$OPTARG" ;;   # Frontend app port
		b) be_app="$OPTARG" ;;   # Backend app port
		x) fe_ssl="$OPTARG" ;;   # Frontend SSL port
		y) be_ssl="$OPTARG" ;;   # Backend SSL port
		i) interactive="true" ;; # Interactive mode flag
		d) deletion="true" ;;    # Deletion of CLB instances
		h) usage clb ;;
		*) usage clb ;;
		esac
	done

	# Shift off processed options
	shift $((OPTIND - 1))

	if [ "$OPTIND" -eq 1 ]; then
		usage clb
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

	int_cns_suffix=$(triton cloudapi "/my/networks/$in_uuid" | grep -o '"svc\.[^",]*' | sed 's/^"//;s/",*$//')
	ext_cns_suffix=$(triton cloudapi "/my/networks/$ext_uuid" | grep -o '"svc\.[^",]*' | sed 's/^"//;s/",*$//')

	app_cns="wrk-$cluster.$int_cns_suffix"
	ctr_cns="ctr-$cluster.$int_cns_suffix"

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
	echo "Internal CNS: $app_cns"
	echo "External CNS: $ctr_cns"
	echo "Interactive: $interactive"

	selection

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

	# Parse options
	while getopts "p:g:hid" opt; do
		case "$opt" in
		p) bst_package="$OPTARG" ;; # Bastion Package
		g) bst_image="$OPTARG" ;;   # Bastion Image
		i) interactive="true" ;;    # Interactive mode flag
		d) deletion="true" ;;       # Deletion of Bastion Instance
		h) usage bastion ;;
		*) usage bastion ;;
		esac
	done

	# Shift off processed options
	shift $((OPTIND - 1))

	if [ "$OPTIND" -eq 1 ]; then
		usage bastion
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

	#validate bastion doesn't already exist
	bastion=$(triton inst ls -Honame tag.triton.cns.services="bastion")
	if [ -n "$bastion" ]; then
		printf "current bastion:"
		printf "  - (bastion) %s\n" "$bastion" && exit 1
	fi

	#interactive for gathering missing parameters
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

up_cluster() {
	account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
	kubernetes_version="1.29.8"
	cluster_id=$(uuidgen | cut -d - -f1 | tr '[:upper:]' '[:lower:]')
	prd_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"
	dev_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"

	if [ "$#" -eq 0 ]; then
		interactive_k8s
	elif [ "$#" -ne 0 ]; then
		while getopts "hid" opt; do
			case "$opt" in
			i) interactive_k8s ;; # Interactive mode flag
			d) rm_cluster ;;      # Deletion of tk8s instances
			h) usage up ;;
			*) usage up ;;
			esac
		done
	fi

	shift $((OPTIND - 1))

	if [ "$OPTIND" -eq 1 ]; then
		usage up
	fi

}

ACTION="$1"

shift

case "$ACTION" in
"up") up_cluster "$@" ;;
"down") rm_cluster "$@" ;;
"ls") ls_cluster ;;
"config") grab_kubeconfig ;;
"upgrade") printf "not implemented yet\n" ;;
"bastion") bastion "$@" ;;
"clb") cloud_load_balancer "$@" ;;
*) printf "invalid action.\n" && usage main ;;
esac
