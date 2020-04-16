#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

cluster_profile=/var/run/secrets/ci.openshift.io/cluster-profile

export CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}

echo "************ baremetalds packet setup command ************"
env | sort

set +x
export PACKET_PROJECT_ID=b3c1623c-ce0b-45cf-9757-c61a71e06eac
PACKET_AUTH_TOKEN=$(cat ${cluster_profile}/.packetcred)
export PACKET_AUTH_TOKEN
PACKET_SERVER_TAGS="e2e-metal-ipi"
export PACKET_SERVER_TAGS


# Initial check
if [ "${CLUSTER_TYPE}" != "packet" ] ; then
    echo >&2 "Unsupported cluster type '${CLUSTER_TYPE}'"
    exit 1
fi

#Packet API call to get list of servers in project
servers="$(curl -X GET --header 'Accept: application/json' --header "X-Auth-Token: ${PACKET_AUTH_TOKEN}"\
 "https://api.packet.net/projects/${PACKET_PROJECT_ID}/devices?exclude=root_password,ssh_keys,created_by")"



#Assuming all servers created more than 4 hours = 14400 sec ago are leaks
#(now-(.created_at|fromdate) starts from -3600 for some reason
#using 14400-3600=10800 sec until mystery resolved

leaks="$(echo $servers | jq -c --arg tagMetalIpi "$PACKET_SERVER_TAGS" '.devices[]|select((now-(.created_at|fromdate))>10800 and any(.tags[]; contains($tagMetalIpi)))|[.hostname,.id,.tags]')"

#timestamps
timestamps="(echo $servers | jq -c '.devices[]|[.created_at, now, (now - (.created_at|fromdate))]'

set -x
echo "************ current time and timestamps processed by jq ************"
echo $"(date)"
echo $"(date -u)"
echo $timestamps | jq .


echo "************ all potential leaked servers in project ************"

if [[ -n "$leaks" ]]
then
    echo $leaks  
fi
