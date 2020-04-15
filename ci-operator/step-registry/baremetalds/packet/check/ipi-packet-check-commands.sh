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
set -x

# Initial check
if [ "${CLUSTER_TYPE}" != "packet" ] ; then
    echo >&2 "Unsupported cluster type '${CLUSTER_TYPE}'"
    exit 1
fi

#Packet API call to get list of servers in project
servers="$(curl -X GET --header 'Accept: application/json' --header "X-Auth-Token: ${PACKET_AUTH_TOKEN}"\
 "https://api.packet.net/projects/${PACKET_PROJECT_ID}/devices")"

#Assuming all servers created more than 4 hours = 14400 sec ago are leaks
leaks="$(echo $servers | jq -c '.devices[]|select((now-(.created_at|fromdate))>14400)|[.hostname,.id,.tags]')"

echo "************ all potential leaked servers in project ************"
echo $leaks

if [[ -n "$leaks" ]]
then
    echo $leaks | mail -s "Packet suspected leaks 4+ hours old" akiselev@redhat.com afasano@redhat.com 
fi
