#!/usr/bin/env bash
account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
network=$(triton network ls -Hoid public=false)                    # Fabric Network UUID
kubernetes_version="1.29.8"
cluster_id=$(uuidgen | cut -d - -f1 | tr '[:upper:]' '[:lower:]')
prd_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"
dev_params="-b bhyve --cloud-config configs/cloud-init -t cluster=$cluster_id -m cluster=$cluster_id -m account=$account -m k8ver=$kubernetes_version"

command -v triton >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1 || {
	echo >&2 "I require both the triton cli and fzf before running."
	exit 1
}

usage() {
	echo "Usage: $0 <action> [OPTIONS]"
	echo "<action> - 'up' or 'down'"
	exit 1
}

suffix() {
	echo "For an instance suffix, please type it now (Example: {{shortId}}.suffix), or press enter to skip:"
	read -r suffix

	if [ -z $suffix ]; then
		echo "Defaulting to no suffix..."
		name_modifier=""
	else
		name_modifier=".$suffix"
	fi
}

ctr() {
	local output=""
  echo "creating control-plane members:"

  output+=$(triton inst create -n {{shortId}}$name_modifier $image $ctr_package $prd_params -t triton.cns.services="init-$cluster_id,ctr-$cluster_id" -m "ctr_count=$num_ctr" -m "wrk_count=$num_wrk" -m tag="init" &)
  output+="\n"

  num_ctr=$((num_ctr - 1))

	for i in $(seq 1 $num_ctr); do
		output+=$(triton inst create -n {{shortId}}$name_modifier $image $ctr_package $prd_params -t triton.cns.services="ctr-$cluster_id" -m tag="ctr" &)
		output+="\n"
	done
	wait

	echo -e "$output"
}

wrk() {
	local output=""

	echo "creating data plane members:"

	for i in $(seq 1 $num_wrk); do
		output+=$(triton inst create -n {{shortId}}$name_modifier $image $wrk_package $prd_params -m tag="wrk" --nic ipv4_uuid="$network" &)
		output+="\n"
	done
	wait

	echo -e "$output"
}

rm_cluster() {
  suffix
	local instances=$(triton inst ls -Ho name | grep -E "^[a-f0-9]{8}${name_modifier}$")

	if [ -n "$instances" ]; then
    echo -e "\nDeleted Instances:"
		echo "$instances" | xargs -I {} triton inst rm -f {}
	else
		echo "No instances to delete"
	fi
}

dev_env() {
	echo "Select a package size for your instance:"
	read -p "Press enter to continue"

	dev_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Creating single control plane:"

	triton inst create -n "{{shortId}}$name_modifier" $image $dev_package $dev_params -m tag=dev -t triton.cns.services=dev-$cluster_id
}

prd_env() {
	local choice=false

	while [ "$choice" = false ]; do
	  echo "How many control plane members would you like to create? (Choose 3, 5, 7, or 9)"
	  read -p "Enter number of members: " num_ctr

		if [[ "$num_ctr" == "3" || "$num_ctr" == "5" || "$num_ctr" == "7" || "$num_ctr" == "9" ]]; then
			choice=true
		else
			echo "Invalid choice. Please enter 3, 5, 7, or 9."
		fi
	done

	echo "How many data plane members would you like to create? (Choose 1-99)"
	read -p "Enter number of members: " num_wrk

	ctr_package=$(triton package ls | fzf --header='please select a package size for your control-plane instances. CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')
	wrk_package=$(triton package ls | fzf --header='please select a package size for your data-plane instances. CTRL-c or ESC to exit' --layout=reverse-list | awk '{print $1}')

	ctr
	wrk
}

main() {
  suffix

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
"up") main;;
"down") rm_cluster;;
"upgrade") echo "Not added yet";;
*) echo "Invalid action. Use 'up' or 'down'" usage ;;
esac
