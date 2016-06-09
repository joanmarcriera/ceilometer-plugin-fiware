#!/bin/sh
#
# Copyright 2016 Telefónica I+D
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#

#
# Perform several checks to verify FIWARE Monitoring configuration
#
# Usage:
#   $0 [--verbose] [--region=NAME] [--poll-threshold=SECS]
#   $0 --help
#
# Options:
#   -v, --verbose		show verbose messages
#   -r, --region=NAME		region name (if not given, taken from nova.conf)
#   -p, --poll-threshold=SECS	threshold for polling frequency (in seconds)
#   -h, --help			show this help message and exit
#
# Environment:
#   OS_AUTH_URL			default value for nova --os-auth-url
#   OS_USERNAME			default value for nova --os-username
#   OS_PASSWORD			default value for nova --os-password
#   OS_USER_ID			default value for nova --os-user-id
#   OS_TENANT_ID		default value for nova --os-tenant-id
#   OS_TENANT_NAME		default value for nova --os-tenant-name
#   OS_USER_DOMAIN_NAME		default value for nova --os-user-domain-name
#   OS_PROJECT_DOMAIN_NAME	default value for nova --os-project-domain-name
#

OPTS='v(verbose)r(region):p(poll-threshold):h(help)'
PROG=$(basename $0)

# Command line options defaults
REGION=$(awk -F= '/^region_name/ {print $2}' /etc/nova/nova.conf 2>NUL)
POLL_THRESHOLD=300
VERBOSE=

# Command line processing
OPTERR=
OPTSTR=$(echo :-:$OPTS | sed 's/([a-zA-Z0-9]*)//g')
OPTHLP=$(sed -n '20,/^$/ { s/$0/'$PROG'/; s/^#[ ]\?//p }' $0)
while getopts $OPTSTR OPT; do while [ -z "$OPTERR" ]; do
case $OPT in
'v')	VERBOSE=true;;
'r')	REGION=$OPTARG;;
'p')	POLL_THRESHOLD=$OPTARG;;
'h')	OPTERR="$OPTHLP";;
'?')	OPTERR="Unknown option -$OPTARG";;
':')	OPTERR="Missing value for option -$OPTARG";;
'-')	OPTLONG="${OPTARG%=*}";
	OPT=$(expr $OPTS : ".*\(.\)($OPTLONG):.*" '|' '?');
	if [ "$OPT" = '?' ]; then
		OPT=$(expr $OPTS : ".*\(.\)($OPTLONG).*" '|' '?')
		OPTARG=-$OPTLONG
	else
		OPTARG=$(echo =$OPTARG | cut -d= -f3)
		[ -z "$OPTARG" ] && { OPTARG=-$OPTLONG; OPT=':'; }
	fi;
	continue;;
esac; break; done; done
shift $(expr $OPTIND - 1)
[ -z "$OPTERR" -a -n "$*" ] && OPTERR="Too many arguments"
[ -z "$OPTERR" -a -z "$REGION" ] && OPTERR="Region name is unset"
[ -n "$OPTERR" ] && {
	PREAMBLE=$(printf "$OPTHLP" | sed -n '0,/^Usage:/ p' | head -n -1)
	USAGE="Usage:\n"$(printf "$OPTHLP" | sed '0,/^Usage:/ d')"\n\n"
	TAB=4; LEN=$(echo "$USAGE" | awk -F'\t' '/ .+\t/ {print $1}' | wc -L)
	TABSTOPS=$TAB,$(((LEN/TAB+2)*TAB)); WIDTH=${COLUMNS:-$(tput cols)}
	[ "$OPTERR" != "$OPTHLP" ] && PREAMBLE="$OPTERR"
	printf "$PREAMBLE\n\n" | fmt -$WIDTH 1>&2
	printf "$USAGE" | tr -s '\t' | expand -t$TABSTOPS | fmt -$WIDTH -s 1>&2
	exit 1
}

# Common functions
get_keystone_token() {
	response=$(curl -s -S -X POST \
		-H "Content-Type: application/json" \
		-H "Accept: application/json" -d '{
			"auth": {
				"tenantName": "service",
				"passwordCredentials": {
					"username": "'$MONASCA_USERNAME'",
					"password": "'$MONASCA_PASSWORD'"
				}
			}
		}' https://cloud.lab.fiware.org:5000/v2.0/tokens \
		| python -mjson.tool)
	auth=$(echo "$response" | awk '/"token"/,/\}/ {print}')
	role=$(echo "$response" | awk '/"roles"/,/\]/ {print}')
	AUTH_TOKEN=$(echo "$auth" | awk -F\" '/"id"/ {print $4; exit}')
	USER_ROLES=$(echo "$role" | awk -F\" '/"name"/ {print $4}')
}

printf_monasca_query() {
	query="$1"
	(curl -s -S -X GET \
		-H "Accept: application/json" \
		-H "X-Auth-Token: $AUTH_TOKEN" \
		"${MONASCA_URL%/}/${query#/}" \
		| python -mjson.tool) 2>/dev/null
}

printf_ok() {
	tput setaf 2; printf "$*\n"; tput sgr0
}

printf_warn() {
	tput setaf 3; printf "$*\n"; tput sgr0
}

printf_fail() {
	tput setaf 1; printf "$*\n"; tput sgr0 #; exit 1
}

# Lists of metrics
METRICS_FOR_IMAGES="\
	image"

METRICS_FOR_REGIONS="\
	region.used_ip \
	region.pool_ip \
	region.allocated_ip \
	region.sanity_status"

METRICS_FOR_COMPUTE_NODES="\
	compute.node.cpu.percent \
	compute.node.cpu.now \
	compute.node.cpu.max \
	compute.node.cpu.tot \
	compute.node.ram.now \
	compute.node.ram.max \
	compute.node.ram.tot \
	compute.node.disk.now \
	compute.node.disk.max \
	compute.node.disk.tot"

# Timestamps
NOW=$(date +%s)
SOME_TIME_AGO=$((NOW - 30 * 60))
SOME_TIME_AGO_DESC="half an hour ago"

# Check Monasca Agent (installation path)
printf "Check Monasca Agent installation path... "
for DIR in /opt/monasca/agent /monasca/monasca_agent_env; do
	if [ -d $DIR ]; then
		MONASCA_AGENT_HOME=$DIR
		printf_ok "$MONASCA_AGENT_HOME"
		break
	fi
done
[ -z "$MONASCA_AGENT_HOME" ] && printf_fail "Not found"

# Check Monasca Agent (configuration)
printf "Check Monasca Agent configuration... "
for FILE in /etc/monasca/agent/agent.yaml; do
	if [ -r $FILE ]; then
		MONASCA_AGENT_CONF=$FILE
		printf_ok "$MONASCA_AGENT_CONF"
		break
	fi
done
[ -z "$MONASCA_AGENT_CONF" ] && printf_fail "Not found"

# Check Monasca Agent (region)
printf "Check Monasca Agent configuration region... "
MONASCA_CONF_REGION=$(awk -F': ' '/^ *region/ {print $2}' $MONASCA_AGENT_CONF)
if [ "$MONASCA_CONF_REGION" = "$REGION" ]; then
	printf_ok "OK"
else
	printf_fail "Fix 'region' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (hostname)
printf "Check Monasca Agent configuration hostname... "
MONASCA_CONF_HOST=$(awk -F': ' '/^ *hostname/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_CONF_HOST" ]; then
	printf_ok "$MONASCA_CONF_HOST"
else
	printf_fail "Set 'hostname' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (logfile)
printf "Check Monasca Agent logfile... "
MONASCA_LOG=$(awk -F': ' '/^ *collector_log/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_LOG" ]; then
	printf_ok "$MONASCA_LOG"
else
	printf_fail "Key 'collector_log_file' not found in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (monasca_url)
printf "Check Monasca API URL... "
MONASCA_URL=$(awk -F': ' '/^ *monasca_url/ {print $2}' $MONASCA_AGENT_CONF)
MONASCA_URL_2=$(awk -F': ' '/^ *url/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_URL" -a "$MONASCA_URL" = "$MONASCA_URL_2" ]; then
	printf_ok "$MONASCA_URL"
else
	printf_fail "Key 'monasca_url' not found in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (keystone_url)
printf "Check Monasca Keystone URL... "
KEYSTONE_URL=$(awk -F': ' '/^ *keystone_url/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_CONF_HOST" ]; then
	printf_ok "$KEYSTONE_URL"
else
	printf_fail "Set 'keystone_url' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (username)
printf "Check Monasca Agent username... "
MONASCA_USERNAME=$(awk -F': ' '/^ *username/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_USERNAME" ]; then
	printf_ok "$MONASCA_USERNAME"
else
	printf_fail "Set 'username' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (password)
printf "Check Monasca Agent password... "
MONASCA_PASSWORD=$(awk -F': ' '/^ *password/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_PASSWORD" ]; then
	printf_ok "OK"
else
	printf_fail "Set 'password' value in $MONASCA_AGENT_CONF"
fi

# Check for monasca_user role
printf "Check Monasca Agent credentials for 'monasca_user' role... "
if get_keystone_token && expr "$USER_ROLES" : "monasca_user" >/dev/null; then
	printf_ok "OK"
else
	printf_fail "User roles: $USER_ROLES"
fi

# Check Monasca Agent (polling frequency)
printf "Check Monasca Agent polling frequency... "
MONASCA_POLL_RATE=$(awk -F': ' '/^ *check_freq/ {print $2}' $MONASCA_AGENT_CONF)
if [ -n "$MONASCA_POLL_RATE" -a $MONASCA_POLL_RATE -ge $POLL_THRESHOLD ]; then
	printf_ok "$MONASCA_POLL_RATE"
else
	printf_warn "$MONASCA_POLL_RATE (consider a higher value)"
fi

# Check Ceilometer polling frequency
printf "Check Ceilometer polling frequency... "
PIPELINE_CONF=/etc/ceilometer/pipeline.yaml
PIPELINE_POLL_RATE=$(awk -F': ' '/interval/ {print $2; exit}' $PIPELINE_CONF)
if [ -n "$PIPELINE_POLL_RATE" -a $PIPELINE_POLL_RATE -ge $POLL_THRESHOLD ]; then
	printf_ok "$PIPELINE_POLL_RATE"
else
	printf_warn "$PIPELINE_POLL_RATE (consider a higher value)"
fi

# Check Ceilometer central agent logfile
printf "Check Ceilometer central agent logfile... "
CENTRAL_AGENT_LOG=/var/log/ceilometer/ceilometer-agent-central.log
if [ -r "$CENTRAL_AGENT_LOG" ]; then
	printf_ok "$CENTRAL_AGENT_LOG"
else
	printf_fail "Not found"
fi

# Check Ceilometer entry points at central node
printf "Check Ceilometer entry points central node... "
FILE=/usr/lib/python2.7/dist-packages/ceilometer-*.egg-info/entry_points.txt
POINTS="publisher|MonascaPublisher \
	metering.storage|impl_monasca_filtered:Connection \
	poll.central|RegionPollster"
EXPECTED=$(echo "$POINTS" | wc -w); ACTUAL=0
for ITEM in $POINTS; do
	CLASS=${ITEM#*|}
	SECTION=ceilometer.${ITEM%|*}
	INFO=$(sed -n "/\[$SECTION\]/,/\[/ p" $FILE | grep ".*=.*$CLASS")
	[ -n "$INFO" ] && ACTUAL=$((ACTUAL + 1))
done
if [ $ACTUAL -eq $EXPECTED ]; then
	printf_ok "OK ($(echo $POINTS | fmt | tr '\n' ' '))"
else
	printf_fail "Could not find all entry points at $FILE"
fi

# Check Ceilometer storage driver for Monasca
printf "Check Ceilometer storage driver for Monasca... "
CLASSNAME=ceilometer.storage.impl_monasca_filtered.Connection
CLASS=$(python -c "import ${CLASSNAME%.*}; print $CLASSNAME" 2>/dev/null)
if [ "$CLASS" = "<class '$CLASSNAME'>" ]; then
	printf_ok "$CLASSNAME"
else
	printf_fail "Could not load class (please check installation details)"
fi

# Check Ceilometer publisher for Monasca
printf "Check Ceilometer publisher for Monasca... "
CLASSNAME=ceilometer.publisher.monasca_metric_filter.MonascaMetricFilter
CLASS=$(python -c "import ${CLASSNAME%.*}; print $CLASSNAME" 2>/dev/null)
if [ "$CLASS" = "<class '$CLASSNAME'>" ]; then
	printf_ok "$CLASSNAME"
else
	printf_fail "Could not load class (please check installation details)"
fi

# Check Ceilometer region pollster class
printf "Check Ceilometer region pollster class... "
CLASSNAME=ceilometer.region.region.RegionPollster
CLASS=$(python -c "import ${CLASSNAME%.*}; print $CLASSNAME" 2>/dev/null)
if [ "$CLASS" = "<class '$CLASSNAME'>" ]; then
	printf_ok "$CLASSNAME"
else
	printf_fail "Could not load class (please check installation details)"
fi

# Check last poll from region pollster
printf "Check last poll from region pollster... "
PATTERN="$(date +%Y-%m-%d).*Polling pollster region"
TIMESTAMP=$(grep "$PATTERN" $CENTRAL_AGENT_LOG | tail -1 | cut -d' ' -f1,2)
if [ -n "$TIMESTAMP" ]; then
	printf_ok "$TIMESTAMP UTC"
else
	printf_fail "Could not find polling today at $CENTRAL_AGENT_LOG"
fi

# Check Monasca metrics for region
printf "Check Monasca metrics for region... "
METRICS="$METRICS_FOR_REGIONS"
RESULTS=""
for NAME in $METRICS; do
	URL_PATH="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$URL_PATH")
	RESULTS="$RESULTS $(echo "$RESPONSE" | awk -F'"' '/"name"/ {print $4}')"
done
COUNT_METRICS=$(echo $METRICS | wc -w)
COUNT_RESULTS=$(echo $RESULTS | wc -w)
if [ $COUNT_METRICS -eq $COUNT_RESULTS ]; then
	printf_ok "OK ($COUNT_RESULTS:$RESULTS)"
else
	printf_fail "Failed"
fi

# Check Monasca recent measurements for region
START=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START&merge_metrics=true"
METRICS="$METRICS_FOR_REGIONS"
for NAME in $METRICS; do
	printf "Check Monasca recent measurements for $NAME... "
	URL_PATH="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	COUNT=$(printf_monasca_query "$URL_PATH&$FILTER" | grep 'Z"' | wc -l)
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT measurements)"
	else
		printf_fail "No measurements found"
	fi
done

# Check last poll from image pollster
printf "Check last poll from image pollster... "
PATTERN="$(date +%Y-%m-%d).*Polling pollster image"
TIMESTAMP=$(grep "$PATTERN" $CENTRAL_AGENT_LOG | tail -1 | cut -d' ' -f1,2)
if [ -n "$TIMESTAMP" ]; then
	printf_ok "$TIMESTAMP UTC"
else
	printf_fail "Could not find polling today at $CENTRAL_AGENT_LOG"
fi

# Check Monasca metrics for image
METRICS="$METRICS_FOR_IMAGES"
for NAME in $METRICS; do
	printf "Check Monasca metrics for $NAME... "
	URL_PATH="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$URL_PATH")
	RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/"resource_id"/ {print $4}')
	COUNT=$(echo "$RESOURCES" | wc -w)
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT metrics for $NAME)"
	else
		printf_fail "Failed"
	fi
	eval COUNT_$NAME=$COUNT
done

# Check Monasca recent measurements for image
START=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START&merge_metrics=true"
METRICS="$METRICS_FOR_IMAGES"
for NAME in $METRICS; do
	printf "Check Monasca recent measurements for $NAME... "
	URL_PATH="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	COUNT=$(printf_monasca_query "$URL_PATH&$FILTER" | grep 'Z"' | wc -l)
	eval RES_COUNT=\$COUNT_$NAME
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT measurements, $RES_COUNT resources)"
	else
		printf_fail "No measurements found"
	fi
done

# Check list of compute nodes
printf "Check list of compute nodes... "
COMPUTE_NODE_LIST=$(nova host-list | awk -F'|' '/compute/ {print $2}' | fmt)
COUNT_COMPUTE_NODES=$(echo $COMPUTE_NODE_LIST | wc -w)
if [ -n "$COMPUTE_NODE_LIST" ]; then
	printf_ok "$COMPUTE_NODE_LIST"
else
	printf_fail "Could not get compute nodes (check OS_* env variables)"
fi

# Check Ceilometer polling frequency at compute nodes
CONF=/etc/ceilometer/pipeline.yaml
for NAME in $COMPUTE_NODE_LIST; do
	printf "Check Ceilometer polling frequency at compute node $NAME... "
	AWK="awk -F': ' '/interval/ {print \$2; exit}' $PIPELINE_CONF"
	POLL_RATE=$(ssh $NAME "$AWK" 2>/dev/null)
	if [ -z "$POLL_RATE" ]; then
		printf_fail "Ceilometer pipeline configuration $CONF not found"
	elif [ $POLL_RATE -lt $POLL_THRESHOLD ]; then
		printf_warn "$POLL_RATE (consider a higher value)"
	else
		printf_ok "$POLL_RATE"
	fi
done

# Check Ceilometer entry points at compute nodes
FILE=/usr/lib/python2.7/dist-packages/ceilometer-*.egg-info/entry_points.txt
for NAME in $COMPUTE_NODE_LIST; do
	printf "Check Ceilometer entry points at compute node $NAME... "
	SED="sed -n '/\[ceilometer.poll.compute\]/,/\[/ p' $FILE"
	INFO=$(ssh $NAME "$SED" 2>/dev/null | grep 'compute.info.*HostPollster')
	if [ -n "$INFO" ]; then
		printf_ok "OK ($INFO)"
	else
		printf_fail "Could not find 'compute.info' entry point"
	fi
done

# Check Ceilometer host pollster class at compute nodes
CLASSNAME=ceilometer.compute.pollsters.host.HostPollster
PYTHON="python -c \"import ${CLASSNAME%.*}; print $CLASSNAME\""
for NAME in $COMPUTE_NODE_LIST; do
	printf "Check Ceilometer host pollster class at compute node $NAME... "
	CLASS=$(ssh $NAME "$PYTHON" 2>/dev/null)
	if [ "$CLASS" = "<class '$CLASSNAME'>" ]; then
		printf_ok "$CLASSNAME"
	else
		printf_fail "Could not load class (please check installation)"
	fi
done

# Check last poll from host pollster at compute nodes
COMPUTE_AGENT_LOG=/var/log/ceilometer/ceilometer-agent-compute.log
for NAME in $COMPUTE_NODE_LIST; do
	printf "Check last poll from host pollster at compute node $NAME... "
	PATTERN="$(date +%Y-%m-%d).*Polling pollster compute\.info"
	GREP="grep \"$PATTERN\" $COMPUTE_AGENT_LOG"
	TIMESTAMP=$(ssh $NAME "$GREP" 2>/dev/null | tail -1 | cut -d' ' -f1,2)
	if [ -z "$TIMESTAMP" ]; then
		printf_fail "Could not find polling today at $COMPUTE_AGENT_LOG"
		continue
	fi
	PATTERN="${TIMESTAMP%.*}.*Skip polling pollster compute\.info"
	GREP="grep \"$PATTERN\" $COMPUTE_AGENT_LOG"
	SKIP=$(ssh $NAME "$GREP" 2>/dev/null | tail -1)
	if [ -n "$SKIP" ]; then
		printf_fail "Failed: $SKIP"
	else
		printf_ok "$TIMESTAMP UTC"
	fi
done

# Check Monasca metrics and measurements for compute nodes
START=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START&merge_metrics=true"
METRICS="$METRICS_FOR_COMPUTE_NODES"
for NAME in $METRICS; do
	printf "Check Monasca recent measurements for $NAME... "
	# get metrics
	URL_PATH="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$URL_PATH")
	RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/resource_id/ {print $4}')
	RES_COUNT=$(echo "$RESOURCES" | wc -w)
	RES_MSG="$RES_COUNT metrics out of $COUNT_COMPUTE_NODES compute nodes"
	# get measurements
	URL_PATH="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	MEASUREMENTS=$(printf_monasca_query "$URL_PATH&$FILTER")
	COUNT=$(echo "$MEASUREMENTS" | grep 'Z"' | wc -l)
	if [ $COUNT -gt 0 -a $RES_COUNT -eq $COUNT_COMPUTE_NODES ]; then
		printf_ok "OK ($COUNT measurements, $RES_MSG)"
	else
		printf_fail "Failed ($COUNT measurements, $RES_MSG)"
		[ -n "$VERBOSE" ] && printf_fail "$RESOURCES" #"\n$MEASUREMENTS"
	fi
done
