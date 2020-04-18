#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

cluster_profile=/var/run/secrets/ci.openshift.io/cluster-profile
#export CLUSTER_PROFILE_DIR=/var/run/secrets/ci.openshift.io/cluster-profile

export CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}

echo "************ baremetalds packet setup command ************"
env | sort

set +x
#PACKET_PROJECT_ID=${CLUSTER_PROFILE_DIR}/.packetid
PACKET_PROJECT_ID=$(cat ${cluster_profile}/.packetid)
export PACKET_PROJECT_ID
#PACKET_AUTH_TOKEN=${CLUSTER_PROFILE_DIR}/.packetcred
PACKET_AUTH_TOKEN=$(cat ${cluster_profile}/.packetcred)
export PACKET_AUTH_TOKEN
#SLACK_AUTH_TOKEN=${CLUSTER_PROFILE_DIR}/.slackhook
export SLACK_AUTH_TOKEN=vgpj4CjdXwpueGOUTJk0xSoH

PACKET_SERVER_TAGS="e2e-metal-ipi"
export PACKET_SERVER_TAGS


# Initial check
if [ "${CLUSTER_TYPE}" != "packet" ] ; then
    echo >&2 "Unsupported cluster type '${CLUSTER_TYPE}'"
    exit 1
fi

#Packet API call to get list of servers in project
servers="$(curl -X GET --header 'Accept: application/json' --header "X-Auth-Token: ${PACKET_AUTH_TOKEN}"\
 "https://api.packet.net/projects/${PACKET_PROJECT_ID}/devices?exclude=root_password,ssh_keys,created_by&per_page=1000")"


#Assuming all servers created more than 4 hours = 14400 sec ago are leaks
leaks="$(echo "$servers" | jq --tab --arg tagMetalIpi "$PACKET_SERVER_TAGS"\
 '.devices[]|select((now-(.created_at|fromdate))>14400 and any(.tags[]; contains($tagMetalIpi)))|.hostname,.id,.created_at,.tags'|sed 's/\"/ /g')"


set -x

echo "************ report e2e-metal-ipi leaked servers in project and send slack notification ************"

if [[ -n "$leaks" ]]
then
    echo "$leaks"
    curl -X POST --data-urlencode\
     "payload={\"text\":\"New Packet.net server leaks found!\n\",\"attachments\":[{\"color\":\"warning\",\"text\":\"$leaks\"}]}"\
      https://hooks.slack.com/services/T027F3GAJ/B011TAG710V/${SLACK_AUTH_TOKEN}
fi
