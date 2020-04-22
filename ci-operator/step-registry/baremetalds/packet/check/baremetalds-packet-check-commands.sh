#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

cluster_profile=/var/run/secrets/ci.openshift.io/cluster-profile

export CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}

echo "************ baremetalds packet setup command ************"
env | sort

set +x

PACKET_PROJECT_ID=$(cat ${cluster_profile}/.packetid)
export PACKET_PROJECT_ID
PACKET_AUTH_TOKEN=$(cat ${cluster_profile}/.packetcred)
export PACKET_AUTH_TOKEN
SLACK_AUTH_TOKEN=$(cat ${cluster_profile}/.slackhook)
export SLACK_AUTH_TOKEN
export PACKET_SERVER_TAGS=e2e-metal-ipi


# Initial check
if [ "${CLUSTER_TYPE}" != "packet" ] ; then
    echo >&2 "Unsupported cluster type '${CLUSTER_TYPE}'"
    exit 1
fi

#Packet API call to get list of servers in project
servers="$(curl -X GET --header 'Accept: application/json' --header "X-Auth-Token: ${PACKET_AUTH_TOKEN}"\
 "https://api.packet.net/projects/${PACKET_PROJECT_ID}/devices?exclude=root_password,ssh_keys,created_by,project,project_lite\
,ip_addresses,plan,meta,operating_system,facility,network_ports&per_page=1000")"

#Assuming all servers created more than 4 hours = 14400 sec ago are leaks
leaks="$(echo "$servers" | jq -r --arg tagMetalIpi "$PACKET_SERVER_TAGS"\
 '.devices[]|select((now-(.created_at|fromdate))>14400 and any(.tags[]; contains($tagMetalIpi)))')"

set -x

leaks_report="$(echo "$leaks" | jq --tab  '.hostname,.id,.created_at,.tags'|sed 's/\"/ /g')"
leak_ids="$(echo "$leaks" | jq -c '.id'|sed 's/\"//g')"
leak_num="$(echo "$leak_ids" | wc -w)"

echo "************ report e2e-metal-ipi leaked servers in project and send slack notification ************"

if [[ -n "$leaks" ]]
then
    echo "$leaks_report"
    set +x
    curl -X POST --data-urlencode\
     "payload={\"text\":\"New Packet.net server leaks total: $leak_num. More details:\n\",\"attachments\":[{\"color\":\"warning\",\"text\":\"$leaks_report\"}]}"\
      https://hooks.slack.com/services/T027F3GAJ/B011TAG710V/${SLACK_AUTH_TOKEN}
    
    #delete leaks
    # for leak in $leak_ids
    # do
    #     echo $leak    
    #     curl -X DELETE --header 'Accept: application/json' --header "X-Auth-Token: ${PACKET_AUTH_TOKEN}"\
    #      "https://api.packet.net/devices/$leak"
    # done
    set -x
fi
