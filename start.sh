#!/usr/bin/env bash
account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
network=$(triton network ls -Hoid public=false)                    # Fabric Network UUID

command -v triton >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1 || {
	echo >&2 "I require both the triton cli and fzf before running."
	exit 1
}

usage() {
	echo "Usage: $0 <action> "
	echo "  <action> - 'up' or 'down'"
	exit 1
}

ctr() {
	local output=""

	echo "creating control plane members:"

	# initial control plane member to handle joins
	triton inst create -n {{shortId}}$name_modifier $image $ctr_package -b bhyve --cloud-config configs/cloud-init-ha -t triton.cns.services="ctr,init" -m "account=$account" -m "tag=init" -m "ctr_count=$num_ctr" -m "wrk_count=$num_wrk"

	num_ctr=$((num_ctr - 1))

	for i in $(seq 1 $num_ctr); do
		output+=$(triton inst create -n {{shortId}}$name_modifier $image $ctr_package -b bhyve --cloud-config configs/cloud-init-ha -t triton.cns.services=ctr -m "account=$account" -m "tag=ctr" &)
		output+="\n"
	done
	wait

	echo -e "$output"
}

wrk() {
	local output=""

	echo "creating data plane members:"

	for i in $(seq 1 $num_wrk); do
		output+=$(triton inst create -n {{shortId}}$name_modifier $image $wrk_package -b bhyve --cloud-config configs/cloud-init-ha -t triton.cns.services=wrk -m "account=$account" -m "tag=wrk" --nic ipv4_uuid="$network" &)
		output+="\n"
	done
	wait

	echo -e "$output"
}

rm_cluster() {
  #multi-select(triton inst ls | fzf --header='Press TAB or SHIFT + TAB to Select Mulitple, CTRL-c or ESC to quit' --layout=reverse-list --multi)
	echo "If you have an instance suffix, please type it now (Example: {{shortId}}.suffix), or press enter to skip:"
	read -r suffix
	if [ -z $suffix ]; then
		echo "Invalid input. Defaulting to no suffix."
		name_modifier=""
	else
		name_modifier=".$suffix"
	fi

	local instances=$(triton inst ls -Ho name | grep -E "^[a-f0-9]{8}${name_modifier}$")

	if [ -n "$instances" ]; then
		echo "$instances" | xargs -I {} triton inst rm -f {}
		echo "Deleted instances:"
		echo "$instances"
	else
		echo "No instances to delete"
	fi
}

dev_env() {

	echo "Select a package size for your instance:"
	read -p "Press enter to continue"
	dev_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Creating single control plane:"

	triton inst create -n "{{shortId}}$name_modifier" $image $dev_package -b bhyve \
		--cloud-config "configs/cloud-init" -t "triton.cns.services=dev" -m "account=$account"
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

	echo "Please select a package size for your control-plane instances:"
	read -p "Press enter to continue"
	ctr_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

	echo "Please select a package size for your data-plane instances:"
	read -p "Press enter to continue"
	wrk_package=$(triton package ls | fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')


	ctr
	wrk

}

main() {

	echo "Would you like a instance name suffix? (Y/N) (Example: N = {{shortId}} or Y = {{shortId}}.suffix)"
	read -r suffix

	case "$suffix" in
	"Y" | "y")
		echo "What would you like your suffix to be?"
		read name_modifier
		name_modifier=".$name_modifier"
		;;
	"N" | "n")
		name_modifier=""
		;;
	*)
		echo "Invalid input. Defaulting to no suffix."
		name_modifier=""
		;;
	esac

	echo "Would you like a Development (1) or Production (HA) environment? (dev/prod)"
	read -r environment

	echo "Please select a image for your kubernetes environment:"
	read -p "Press enter to continue"
	image=$(triton image ls type=zvol os=linux| fzf --header='CTRL-c or ESC to quit' --layout=reverse-list | awk '{print $1}')

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
