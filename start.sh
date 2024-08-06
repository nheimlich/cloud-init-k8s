#!/usr/bin/env bash
account=$(triton account get | grep -e 'id:' | sed -e 's/id:\ //') # account UUID
network=$(triton network ls -Hoid public=false) # Fabric Network UUID

name_modifier="nhlabs.org-new"
image="debian-12@20240612"
package_ctr="b0a814d9"
package_wrk="b0a814d9"

ACTION="$1"

usage() {
  echo "Usage: $0 <action> "
  echo "  <action> - 'up' or 'down'"
  exit 1
}

create_ctr() {
  local output=""
  for i in {0..2}; do
    output+=$(triton inst create -n k8s-$i.$name_modifier $image $package_ctr -b bhyve --cloud-config configs/cloud-init-ha -t triton.cns.services=ctr --metadata="account=$account" --metadata="tag=ctr" &)
    output+="\n"
  done
  wait
  echo -e "$output"
}

create_wrk() {
  local output=""
  for i in {3..5}; do
    output+=$(triton inst create -n k8s-$i.$name_modifier $image $package_wrk -b bhyve --cloud-config configs/cloud-init-ha -t triton.cns.services=wrk --metadata="account=$account" --metadata="tag=wrk" --nic ipv4_uuid="$network" &)
    output+="\n"
  done
  wait
  echo -e "$output"
}

rm_cluster() {
  local output=""
  for i in {0..5}; do
    output+=$(triton inst rm -f k8s-$i.$name_modifier &)
  done
  wait
  echo -e "$output"
}

if [ "$#" -ne 1 ]; then
  usage
fi

case "$ACTION" in
  "up")
    create_ctr && create_wrk
    ;;
  "down")
    rm_cluster | tee -a 
    ;;
  *)
    echo "Invalid action. Use 'up' or 'down'"
    usage
    ;;
esac

