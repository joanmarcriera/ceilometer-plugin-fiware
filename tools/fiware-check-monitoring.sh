#!/bin/sh
# -*- coding: utf-8; version: 1.2.0 -*-
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
#   $0 --help | --version
#   $0 [--verbose] [--region=NAME] [--poll-threshold=SECS] [--measure-time=MINS]
#   __ [--ssh-key=FILE]
#
# Options:
#   -h, --help 			show this help message and exit
#   -V, --version 		show version information and exit
#   -v, --verbose 		show verbose messages
#   -r, --region=NAME 		region name (if not given, taken from nova.conf)
#   -p, --poll-threshold=SECS 	threshold warning polling frequency (seconds)
#   -m, --measure-time=MINS 	period to query measurements up to now (minutes)
#   -k, --ssh-key=FILE 		private key to access compute nodes
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

OPTS="v(verbose)r(region):p(poll-threshold):m(measure-time):k(ssh-key):"
OPTS="${OPTS}h(help)V(version)"
PROG=$(basename $0)

# Files
TEMP_FILE=/tmp/$PROG
NOVA_CONF=/etc/nova/nova.conf
PIPELINE_CONF=/etc/ceilometer/pipeline.yaml
MONASCA_AGENT_CONF=/etc/monasca/agent/agent.yaml
CENTRAL_AGENT_LOG=/var/log/ceilometer/ceilometer-agent-central.log
COMPUTE_AGENT_LOG=/var/log/ceilometer/ceilometer-agent-compute.log

# Common definitions
MONASCA_URL=
MONASCA_USERNAME=
MONASCA_PASSWORD=
MONASCA_AGENT_HOME=
MONASCA_AGENT_USER=
CEILOMETER_PKG=
PYTHON_DIST_PKG=
AGENT_LOG_PREFIX=
alias trim='tr -d \ '

# Command line options defaults
REGION=$(awk -F= '/^(os_)?region_name/ {print $2; exit}' $NOVA_CONF | trim)
POLL_THRESHOLD=300
MEASURE_TIME=60
SSH_KEY=
VERBOSE=

# Command line processing
OPTERR=
OPTSTR=$(echo :-:$OPTS | sed 's/([-_a-zA-Z0-9]*)//g')
OPTHLP=$(awk '/^# *__/ { $2=sprintf("  %*s",'${#PROG}'," ") } { print }' $0 \
	| sed -n '21,/^$/ { s/$0/'$PROG'/; s/^#[ ]\?//; p }')
while getopts $OPTSTR OPT; do while [ -z "$OPTERR" ]; do
case $OPT in
'v')	VERBOSE=true;;
'r')	REGION=$OPTARG;;
'p')	POLL_THRESHOLD=$OPTARG;;
'm')	MEASURE_TIME=$OPTARG;;
'k')	SSH_KEY=$OPTARG;;
'h')	OPTERR="$OPTHLP";;
'V')	OPTERR=$(awk '/-\*-/ {print "v" $(NF-1) "\n"}' $0);
	printf "$OPTERR\n" 1>&2; exit 1;;
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

# Check enviroment variables required as credentials for OpenStack clients
COUNT=$(env | egrep 'OS_(AUTH_URL|USERNAME|PASSWORD|TENANT_NAME)' | wc -l)
[ -z "$OPTERR" -a $COUNT -ne 4 ] && OPTERR="Missing OS_* environment variables"

# Show error messages and exit
[ -n "$OPTERR" ] && {
	PREAMBLE=$(echo "$OPTHLP" | sed -n '0,/^Usage:/ p' | head -n -1)
	OPTIONS=$(echo "$OPTHLP" | sed -n "/^Options:/,/^\$/ p")"\n\n"
	EPILOG=$(echo "$OPTHLP" | sed -n "/Environment:/,/^\$/ p")"\n\n"
	USAGE=$(echo "$OPTHLP" | sed -n "/^Usage:/,/^\$/ p")
	TAB=4; LEN=$(echo "$OPTIONS" | awk -F'\t' '/ .+\t/ {print $1}' | wc -L)
	TABSTOPS=$TAB,$(((LEN/TAB+1)*TAB)); WIDTH=${COLUMNS:-$(tput cols)}
	[ "$OPTERR" != "$OPTHLP" ] && PREAMBLE="$OPTERR" && OPTIONS= && EPILOG=
	printf "$PREAMBLE\n\n$USAGE\n\n$OPTIONS" | fmt -$WIDTH -s 1>&2
	printf "$EPILOG" | tr -s '\t' | expand -t$TABSTOPS | fmt -$WIDTH -s 1>&2
	exit 1
}

# Common functions
check_ssh() {
	SSH=ssh
	status=0
	hosts="$*"
	for name in $hosts; do
		if ! $SSH $name "ls" >/dev/null 2>&1; then
			status=1
			break
		fi
	done
	if [ $status -ne 0 ]; then
		ssh_key_files="${SSH_KEY:-~/.ssh/fuel_id_rsa ~/.ssh/id_rsa}"
		for name in $hosts; do
			for file in $ssh_key_files; do
				SSH="ssh -i $file"
				if $SSH $name "ls" >/dev/null 2>&1; then
					status=0
					break
				fi
			done
		done
	fi
	[ $status -eq 0 ] || unset SSH
	return $status
}

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
	curl="curl -s -S -X GET \
		-H \"Accept: application/json\" \
		-H \"X-Auth-Token: $AUTH_TOKEN\" \
		\"${MONASCA_URL%/}/${query#/}\""
	(eval "$curl" | python -mjson.tool) 2>/dev/null
	[ -n "$VERBOSE" ] && echo "$curl" > $TEMP_FILE
}

printf_ok() {
	tput setaf 2; printf "$*\n"; tput sgr0
}

printf_warn() {
	tput setaf 3; printf "$*\n"; tput sgr0
}

printf_fail() {
	tput setaf 1; printf "$*\n"; tput sgr0
}

printf_curl() {
	msg="$1"
	tput setaf 1; printf "$msg"; awk '{$1=$1; print}' $TEMP_FILE; tput sgr0
}

printf_measurements() {
	measurements_query="$1"
	measurements_filter="$2"
	dimensions=$(printf_monasca_query "/metrics?${measurements_query#*\?}" \
		| awk -F'"' '/hostname|resource_id/ {print $2 ":" $4}')
	for item in $dimensions; do
		query="$measurements_query,$item"
		result=$(printf_monasca_query "$query&$measurements_filter")
		sample=$(echo "$result" | awk '/\.0,/ {print $NF}' | tail -1)
		printf_warn "* Last measurement for ${item#*:}: $sample"
	done
}

# Lists of metrics (or metadata items, when appropriate)
METRICS_FOR_IMAGES="\
	image"

METRICS_FOR_VMS="\
	instance:name \
	instance:host \
	instance:status \
	instance:image_ref \
	instance:instance_type \
	cpu_util \
	memory.usage \
	memory \
	disk.usage \
	disk.capacity"

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

METRICS_FOR_HOST_SERVICES="\
	nova-api \
	nova-cert \
	nova-conductor \
	nova-consoleauth \
	nova-novncproxy \
	nova-objectstore \
	nova-scheduler \
	neutron-dhcp-agent \
	neutron-l3-agent \
	neutron-metadata-agent \
	neutron-openvswitch-agent \
	neutron-server \
	cinder-api \
	cinder-scheduler \
	glance-api \
	glance-registry"

# Timestamps
NOW=$(date +%s)
SOME_TIME_AGO=$((NOW - $MEASURE_TIME * 60))

# Recent measurements period
printf_warn "[Considering measurements within last $MEASURE_TIME minutes]"

# Check Python interpreter
printf "Check Python interpreter... "
if [ -n "$VIRTUAL_ENV" ]; then
	printf_fail "Python virtualenv $VIRTUAL_ENV should not be active"
	exit 1
else
	printf_ok "$(python -V 2>&1) at $(which python)"
fi

# Check Monasca Agent (installation path and version)
printf "Check Monasca Agent installation... "
for DIR in /opt/monasca /monasca/monasca_agent_env; do
	if [ -d $DIR ]; then
		MONASCA_AGENT_HOME=$DIR
		INFO=$($MONASCA_AGENT_HOME/bin/pip show monasca-agent)
		VERSION=$(echo "$INFO" | awk '/^Version:/ {print $2}')
		break
	fi
done
if [ -z "$MONASCA_AGENT_HOME" ]; then
	printf_fail "Not found"
elif [ $(expr "$MONASCA_AGENT_HOME" : "^/opt/.*") -eq 0 ]; then
	printf_warn "$VERSION at $MONASCA_AGENT_HOME (this path is deprecated)"
else
	printf_ok "$VERSION at $MONASCA_AGENT_HOME"
fi

# Check Monasca Agent (daemon user)
printf "Check Monasca Agent daemon user... "
MONASCA_AGENT_USER=$(awk -F: '/mon-/ {print $1}' /etc/passwd 2>/dev/null)
if [ -z "$MONASCA_AGENT_USER" ]; then
	printf_fail "Not found"
elif [ "$(echo ~$MONASCA_AGENT_USER)" != "$MONASCA_AGENT_HOME" ]; then
	printf_warn "$MONASCA_AGENT_USER (set $MONASCA_AGENT_HOME as home dir)"
else
	printf_ok "$MONASCA_AGENT_USER"
fi

# Check Monasca Agent (configuration)
printf "Check Monasca Agent configuration... "
MONASCA_AGENT_CHECK="$MONASCA_AGENT_HOME/bin/monasca-collector configcheck"
if [ ! -r $MONASCA_AGENT_CONF ]; then
	printf_fail "Configuration file $MONASCA_AGENT_CONF not found"
elif ! su $MONASCA_AGENT_USER -c "$MONASCA_AGENT_CHECK" >/dev/null 2>&1; then
	printf_fail "Run \`$MONASCA_AGENT_CHECK' to check errors"
else
	printf_ok "OK ($MONASCA_AGENT_CONF)"
fi

# Check Monasca Agent (region)
printf "Check Monasca Agent configuration region... "
CONF_REGION=$(awk -F: '/^ *region/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ "$CONF_REGION" = "$REGION" ]; then
	printf_ok "OK"
else
	printf_fail "Fix 'region' value in $MONASCA_AGENT_CONF"
	[ -n "$VERBOSE " ] && printf_fail "'$CONF_REGION' != '$REGION'"
fi

# Check Monasca Agent (hostname)
printf "Check Monasca Agent configuration hostname... "
CONF_HOST=$(awk -F: '/^ *hostname/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ -n "$CONF_HOST" ]; then
	printf_ok "$CONF_HOST"
else
	printf_fail "Set 'hostname' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (logfile)
printf "Check Monasca Agent logfile... "
FILE=$(awk -F: '/^ *forwarder_log/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ -n "$FILE" ]; then
	MONASCA_AGENT_LOG="$FILE"
	printf_ok "$MONASCA_AGENT_LOG"
else
	printf_fail "Key 'forwarder_log_file' not found in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (monasca_url)
printf "Check Monasca API URL... "
URL=$(sed -n '/^ *monasca_url/ p' $MONASCA_AGENT_CONF | cut -d: -f2- | trim)
URL_ALT=$(sed -n '/^ *url/ p' $MONASCA_AGENT_CONF | cut -d: -f2- | trim)
if [ -n "$URL" -a "$URL" = "$URL_ALT" ]; then
	MONASCA_URL="$URL"
	printf_ok "$MONASCA_URL"
else
	printf_fail "Key 'monasca_url' not found in $MONASCA_AGENT_CONF"
	[ -n "$VERBOSE " ] && printf_fail "'$URL' != '$URL_ALT'"
fi

# Check Monasca Agent (keystone_url)
printf "Check Monasca Keystone URL... "
URL=$(sed -n '/^ *keystone_url/ p' $MONASCA_AGENT_CONF | cut -d: -f2- | trim)
if [ -n "$URL" ]; then
	printf_ok "$URL"
else
	printf_fail "Set 'keystone_url' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (username)
printf "Check Monasca Agent username... "
USERNAME=$(awk -F: '/^ *username/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ -n "$USERNAME" ]; then
	MONASCA_USERNAME="$USERNAME"
	printf_ok "$MONASCA_USERNAME"
else
	printf_fail "Set 'username' value in $MONASCA_AGENT_CONF"
fi

# Check Monasca Agent (password)
printf "Check Monasca Agent password... "
PASSWORD=$(awk -F: '/^ *password/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ -n "$PASSWORD" ]; then
	MONASCA_PASSWORD="$PASSWORD"
	printf_ok "$(echo $MONASCA_PASSWORD | tr '[:print:]' '*')"
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
POLL_RATE=$(awk -F: '/^ *check_freq/ {print $2}' $MONASCA_AGENT_CONF | trim)
if [ -n "$POLL_RATE" -a $POLL_RATE -ge $POLL_THRESHOLD ]; then
	printf_ok "$POLL_RATE seconds"
else
	printf_warn "$POLL_RATE seconds (consider a higher value)"
fi

# Check Ceilometer polling frequency
printf "Check Ceilometer polling frequency... "
POLL_RATE=$(awk -F: '/interval/ {print $2; exit}' $PIPELINE_CONF | trim)
if [ -n "$POLL_RATE" -a $POLL_RATE -ge $POLL_THRESHOLD ]; then
	printf_ok "$POLL_RATE seconds"
else
	printf_warn "$POLL_RATE seconds (consider a higher value)"
fi

# Check Ceilometer central agent logfile
printf "Check Ceilometer central agent logfile... "
for AGENT_LOG_PREFIX in "" "ceilometer-agent-"; do
	FILE=/var/log/ceilometer/${AGENT_LOG_PREFIX}central.log
	if [ -r $FILE ]; then
		CENTRAL_AGENT_LOG=$FILE
		break
	fi
done
if [ -r "$CENTRAL_AGENT_LOG" ]; then
	printf_ok "$CENTRAL_AGENT_LOG"
else
	printf_fail "Not found"
fi

# Check Ceilometer installation path and version
printf "Check Ceilometer installation path and version... "
PYTHON_DIST_PKG=$(python -c "import sys; import re; \
	pattern = re.compile(r'.*(dist|site)-packages\$'); \
	print [dir for dir in sys.path if pattern.match(dir)][-1]")
if [ -d "$PYTHON_DIST_PKG/ceilometer" ]; then
	CEILOMETER_PKG="$PYTHON_DIST_PKG/ceilometer"
	VERSION=$(pip show ceilometer | awk '/^Version:/ {print $2}')
	printf_ok "$VERSION at $CEILOMETER_PKG"
else
	printf_fail "Not found"
fi

# Check Ceilometer plugin for Monasca (Ceilosca)
printf "Check Ceilometer plugin for Monasca (Ceilosca)... "
FILE=$PYTHON_DIST_PKG/ceilometer-*.egg-info/ceilosca.txt
VERSION=$(awk -F= '{print $2}' $FILE 2>/dev/null)
if [ -n "$VERSION" ]; then
	printf_ok "$VERSION"
else
	printf_warn "Could not find version (please check installation details)"
fi

# Check Ceilometer region pollster version
printf "Check Ceilometer region pollster version... "
POLLSTER=$CEILOMETER_PKG/region/region.py
VERSION=$(awk '/# Version:/ {print $3}' $POLLSTER)
if [ -n "$VERSION" ]; then
	printf_ok "$VERSION"
else
	printf_warn "Could not find version (please check installation details)"
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

# Check Ceilometer publisher for Monasca
printf "Check Ceilometer publisher for Monasca... "
CLASSNAME=ceilometer.publisher.monasca_metric_filter.MonascaMetricFilter
CLASS=$(python -c "import ${CLASSNAME%.*}; print $CLASSNAME" 2>/dev/null)
if [ "$CLASS" = "<class '$CLASSNAME'>" ]; then
	printf_ok "$CLASSNAME"
else
	printf_fail "Could not load class (please check installation details)"
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

# Check Ceilometer entry points at this node
printf "Check Ceilometer entry points at this node... "
FILE=$PYTHON_DIST_PKG/ceilometer-*.egg-info/entry_points.txt
POINTS="poll.central|RegionPollster \
	publisher|MonascaPublisher \
	metering.storage|monasca_filtered:Connection"
EXPECTED=$(echo "$POINTS" | wc -w); ACTUAL=0
for ITEM in $POINTS; do
	SECTION=ceilometer.${ITEM%|*}
	CLASSNAME=${ITEM#*|}
	INFO=$(sed -n "/\[$SECTION\]/,/\[/ p" $FILE | grep ".*=.*$CLASSNAME")
	[ -n "$INFO" ] && ACTUAL=$((ACTUAL + 1))
done
if [ $ACTUAL -eq $EXPECTED ]; then
	printf_ok "OK ($(echo $POINTS))"
else
	printf_fail "Could not find all entry points at $FILE"
fi

# Check last poll from region pollster at this node
printf "Check last poll from region pollster at this node... "
PATTERN="$(date +%Y-%m-%d).*Polling pollster region"
TIMESTAMP=$(grep "$PATTERN" $CENTRAL_AGENT_LOG | tail -1 | cut -d' ' -f1,2)
if [ -n "$TIMESTAMP" ]; then
	printf_ok "$TIMESTAMP UTC"
elif [ -z "$(pgrep -f ceilometer-agent-central)" ]; then
	printf_warn "Skipped: ceilometer-agent-central not active in this node"
else
	printf_fail "Could not find polling today at $CENTRAL_AGENT_LOG"
fi

# Check Monasca metrics for region
printf "Check Monasca metrics for region... "
METRICS="$METRICS_FOR_REGIONS"
RESULTS=""
for NAME in $METRICS; do
	QUERY="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$QUERY")
	RESULTS="$RESULTS $(echo "$RESPONSE" | awk -F'"' '/"name"/ {print $4}')"
done
COUNT_METRICS=$(echo $METRICS | wc -w)
COUNT_RESULTS=$(echo $RESULTS | wc -w)
if [ $COUNT_METRICS -eq $COUNT_RESULTS ]; then
	printf_ok "OK ($COUNT_RESULTS:$RESULTS)"
else
	printf_fail "Missing metrics"
	[ -n "$VERBOSE" ] && printf_curl
fi

# Check Monasca recent metadata for region
printf "Check Monasca recent metadata for region... "
START_SOME_TIME_AGO=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START_SOME_TIME_AGO&merge_metrics=true"
QUERY="/metrics/measurements?name=region.pool_ip&dimensions=region:$REGION"
PATTERN="latitude|longitude|location|cpu_allocation_ratio|ram_allocation_ratio"
COUNT=$(echo "$PATTERN" | awk -F'|' '{print NF}')
RESPONSE=$(printf_monasca_query "$QUERY&$FILTER")
MEASURES_COUNT=$(echo "$RESPONSE" | grep -v '"id"' | grep 'Z"' | wc -l)
METADATA_ACTUAL=$(echo "$RESPONSE" | egrep "$PATTERN" | wc -l)
METADATA_EXPECT=$((MEASURES_COUNT * COUNT))
if [ $METADATA_ACTUAL -eq $METADATA_EXPECT ]; then
	printf_ok "OK ($COUNT: $(echo "$PATTERN" | tr '|' ' '))"
else
	printf_fail "Missing metadata"
fi

# Check Monasca recent measurements for region
START_SOME_TIME_AGO=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
START_TODAY=$(date -u -d @$NOW +%Y-%m-%dT00:00:00Z)
FILTER_1="start_time=$START_SOME_TIME_AGO&merge_metrics=true"
FILTER_2="start_time=$START_TODAY&merge_metrics=true"
METRICS="$METRICS_FOR_REGIONS"
for NAME in $METRICS; do
	printf "Check Monasca recent measurements for $NAME... "
	QUERY="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	FILTER="$FILTER_1"
	[ $NAME = "region.sanity_status" ] && FILTER="$FILTER_2"
	RESPONSE=$(printf_monasca_query "$QUERY&$FILTER")
	COUNT=$(echo "$RESPONSE" | grep -v '"id"' | grep 'Z"' | wc -l)
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT measurements)"
	else
		printf_fail "No measurements found"
		[ -n "$VERBOSE" ] && printf_curl
	fi
done

# Check last poll from image pollster at this node
printf "Check last poll from image pollster at this node... "
PATTERN="$(date +%Y-%m-%d).*Polling pollster image"
TIMESTAMP=$(grep "$PATTERN" $CENTRAL_AGENT_LOG | tail -1 | cut -d' ' -f1,2)
if [ -n "$TIMESTAMP" ]; then
	printf_ok "$TIMESTAMP UTC"
elif [ -z "$(pgrep -f ceilometer-agent-central)" ]; then
	printf_warn "Skipped: ceilometer-agent-central not active in this node"
else
	printf_fail "Could not find polling today at $CENTRAL_AGENT_LOG"
fi

# Check Monasca metrics for image
METRICS="$METRICS_FOR_IMAGES"
IMAGES=$(glance image-list | awk '/active/ {print $4}' | tr '\n' ' ')
COUNT_IMAGES=$(echo $IMAGES | wc -w)
for NAME in $METRICS; do
	printf "Check Monasca metrics for $NAME... "
	QUERY="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$QUERY")
	RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/"resource_id"/ {print $4}')
	COUNT=$(echo "$RESOURCES" | wc -w)
	if [ $COUNT -ge $COUNT_IMAGES ]; then
		printf_ok "OK ($COUNT metrics out or $COUNT_IMAGES images)"
	else
		printf_fail "Missing metrics"
		[ -n "$VERBOSE" ] && printf_curl

	fi
	eval COUNT_$NAME=$COUNT
done

# Check Monasca recent measurements for image
START_TODAY=$(date -u -d @$NOW +%Y-%m-%dT00:00:00Z)
FILTER="start_time=$START_TODAY&merge_metrics=true"
METRICS="$METRICS_FOR_IMAGES"
for NAME in $METRICS; do
	printf "Check Monasca recent measurements for $NAME... "
	QUERY="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$QUERY&$FILTER")
	COUNT=$(echo "$RESPONSE" | grep -v '"id"' | grep 'Z"' | wc -l)
	eval RES_COUNT=\$COUNT_$NAME
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT measurements, $RES_COUNT metrics)"
	else
		printf_fail "No measurements found"
		[ -n "$VERBOSE" ] && printf_curl
	fi
done

# Check list of compute nodes
printf "Check list of compute nodes... "
COMPUTE_NODES=$(nova host-list | awk '/compute/ {print $2}' | tr '\n' ' ')
COUNT_COMPUTE_NODES=$(echo $COMPUTE_NODES | wc -w)
if [ -n "$COMPUTE_NODES" ]; then
	printf_ok "$COMPUTE_NODES"
else
	printf_fail "Could not get list of compute nodes"
fi

# Check execution of remote commands at compute nodes
printf "Check execution of remote commands at compute nodes... "
if check_ssh $COMPUTE_NODES; then
	printf_ok "OK ($SSH)"
else
	printf_fail "Could not get ssh access to compute nodes (check ssh-key)"
fi

# Check Ceilometer polling frequency at compute nodes
FILE=$PIPELINE_CONF
for NAME in $COMPUTE_NODES; do
	printf "Check Ceilometer polling frequency at compute node $NAME... "
	REMOTE="$SSH $NAME"
	AWK="awk -F: '/interval/ {print \$2; exit}' $FILE"
	POLL_RATE=$($REMOTE "$AWK" 2>/dev/null | trim)
	if [ -z "$SSH" ]; then
		printf_fail "Skipped"
	elif [ -z "$POLL_RATE" ]; then
		printf_fail "Ceilometer pipeline configuration $FILE not found"
	elif [ $POLL_RATE -lt $POLL_THRESHOLD ]; then
		printf_warn "$POLL_RATE seconds (consider a higher value)"
	else
		printf_ok "$POLL_RATE seconds"
	fi
done

# Check Ceilometer entry points at compute nodes
FILE=$PYTHON_DIST_PKG/ceilometer-*.egg-info/entry_points.txt
POINTS="compute.info.*HostPollster \
	cpu.*CPUPollster \
	memory.usage.*MemoryUsagePollster \
	disk.usage.*disk:PhysicalPollster \
	disk.capacity.*CapacityPollster"
for NAME in $COMPUTE_NODES; do
	printf "Check Ceilometer entry points at compute node $NAME... "
	if [ -z "$SSH" ]; then
		printf_fail "Skipped"
		continue
	fi
	REMOTE="$SSH $NAME"
	SED="sed -n '/\[ceilometer.poll.compute\]/,/\[/ p' $FILE"
	POLL_COMPUTE_SECTION=$($REMOTE "$SED" 2>/dev/null)
	for PATTERN in $POINTS; do
		ENTRY=$(echo "$POLL_COMPUTE_SECTION" | grep $PATTERN)
		if [ -z "$ENTRY" ]; then
			POLLSTER=$(echo "$PATTERN" | sed 's/\(.*\)\.\*.*/\1/')
			printf_fail "Could not find '$POLLSTER' entry point"
			break
		fi
	done
	if [ -n "$ENTRY" ]; then
		LIST=$(echo "$POINTS" | tr '\t' '\n' | sed 's/\(.*\)\.\*.*/\1/')
		printf_ok "OK ($(echo $LIST))"
	fi
done

# Check Ceilometer host pollster class at compute nodes
CLASSNAME=ceilometer.compute.pollsters.host.HostPollster
PYTHON="python -c \"import ${CLASSNAME%.*}; print $CLASSNAME\""
for NAME in $COMPUTE_NODES; do
	printf "Check Ceilometer host pollster class at compute node $NAME... "
	REMOTE="$SSH $NAME"
	CLASS=$($REMOTE "$PYTHON" 2>/dev/null)
	if [ -z "$SSH" ]; then
		printf_fail "Skipped"
	elif [ "$CLASS" != "<class '$CLASSNAME'>" ]; then
		printf_fail "Could not load class (please check installation)"
	else
		printf_ok "$CLASSNAME"
	fi
done

# Check last poll from host pollster at compute nodes
COMPUTE_AGENT_LOG=/var/log/ceilometer/${AGENT_LOG_PREFIX}compute.log
for NAME in $COMPUTE_NODES; do
	printf "Check last poll from host pollster at compute node $NAME... "
	PATTERN="$(date +%Y-%m-%d).*Polling pollster compute\.info"
	GREP="grep \"$PATTERN\" $COMPUTE_AGENT_LOG"
	REMOTE="$SSH $NAME"
	TIMESTAMP=$($REMOTE "$GREP" 2>/dev/null | tail -1 | cut -d' ' -f1,2)
	if [ -z "$SSH" ]; then
		printf_fail "Skipped"
		continue
	elif [ -z "$TIMESTAMP" ]; then
		printf_fail "Could not find polling today at $COMPUTE_AGENT_LOG"
		continue
	fi
	PATTERN="${TIMESTAMP%.*}.*Skip polling pollster compute\.info"
	GREP="grep \"$PATTERN\" $COMPUTE_AGENT_LOG"
	SKIP=$($REMOTE "$GREP" 2>/dev/null | tail -1)
	if [ -n "$SKIP" ]; then
		printf_warn "Warning: $SKIP"
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
	QUERY="/metrics?name=$NAME&dimensions=region:$REGION"
	RESPONSE=$(printf_monasca_query "$QUERY")
	RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/resource_id/ {print $4}')
	NODE_NAMES=$(echo "$RESOURCES" | sed 's/\(.*\)_\1/\1/' | tr '\n' ' ')
	NODE_COUNT=$(echo "$NODE_NAMES" | wc -w)
	NODE_MSG="$NODE_COUNT metrics out of $COUNT_COMPUTE_NODES compute nodes"
	# get measurements
	QUERY="/metrics/measurements?name=$NAME&dimensions=region:$REGION"
	MEASUREMENTS=$(printf_monasca_query "$QUERY&$FILTER")
	COUNT=$(echo "$MEASUREMENTS" | grep -v '"id"' | grep 'Z"' | wc -l)
	if [ $COUNT -gt 0 -a $NODE_COUNT -ge $COUNT_COMPUTE_NODES ]; then
		printf_ok "OK ($COUNT measurements, $NODE_MSG)"
	elif [ $RES_COUNT -eq 0 ]; then
		printf_fail "Failed ($NODE_MSG)"
	else
		printf_warn "Warning ($COUNT measurements, $NODE_MSG)"
		[ -z "$VERBOSE" ] && continue
		printf_warn "* Compute nodes with metrics: $NODE_NAMES"
		printf_curl "* Sample Monasca API query: "
		printf "\n"
	fi
done

# Check Monasca metrics for host services
METRIC=process.pid_count
for COMPONENT in $METRICS_FOR_HOST_SERVICES; do
	printf "Check Monasca metrics for $COMPONENT... "
	DIMENSIONS="region:$REGION,component:$COMPONENT"
	QUERY="/metrics?name=$METRIC&dimensions=$DIMENSIONS"
	RESPONSE=$(printf_monasca_query "$QUERY")
	RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/"hostname"/ {print $4}')
	COUNT=$(echo "$RESOURCES" | wc -w)
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT metrics for $COMPONENT)"
	else
		printf_fail "Missing metrics"
		[ -n "$VERBOSE" ] && printf_curl

	fi
	NAME=$(echo "$COMPONENT" | tr '-' '_')
	eval COUNT_$NAME=$COUNT
done

# Check Monasca recent measurements for host services
START=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START&merge_metrics=true"
METRIC=process.pid_count
for COMPONENT in $METRICS_FOR_HOST_SERVICES; do
	printf "Check Monasca recent measurements for $COMPONENT... "
	DIMENSIONS="region:$REGION,component:$COMPONENT"
	QUERY="/metrics/measurements?name=$METRIC&dimensions=$DIMENSIONS"
	RESPONSE=$(printf_monasca_query "$QUERY&$FILTER")
	COUNT=$(echo "$RESPONSE" | grep -v '"id"' | grep 'Z"' | wc -l)
	NAME=$(echo "$COMPONENT" | tr '-' '_')
	eval RES_COUNT=\$COUNT_$NAME
	if [ $COUNT -gt 0 ]; then
		printf_ok "OK ($COUNT measurements, $RES_COUNT resources)"
		[ -n "$VERBOSE" ] && printf_measurements "$QUERY" "$FILTER"
	else
		printf_fail "No measurements found"
		[ -n "$VERBOSE" ] && printf_curl
	fi
done

# Check Monasca metrics for active VMs
printf "Check Monasca metrics for active VMs... "
VMS=$(nova list --all-tenants | awk '/ACTIVE/ {print $2}' | tr '\n' ' ')
COUNT_VMS=$(echo $VMS | wc -w)
METRIC=instance
QUERY="/metrics?name=$METRIC&dimensions=region:$REGION"
RESPONSE=$(printf_monasca_query "$QUERY")
RESOURCES=$(echo "$RESPONSE" | awk -F'"' '/"resource_id"/ {print $4}')
COUNT=$(echo "$RESOURCES" | wc -w)
if [ $COUNT -ge $COUNT_VMS ]; then
	printf_ok "OK ($COUNT metrics out or $COUNT_VMS active VMs)"
else
	printf_fail "Missing metrics"
	[ -n "$VERBOSE" ] && printf_curl
fi

# Check Monasca recent measurements for active VMs
START=$(date -u -d @$SOME_TIME_AGO +%Y-%m-%dT%H:%M:%SZ)
FILTER="start_time=$START&merge_metrics=true"
METRICS=$(echo $METRICS_FOR_VMS | awk -F: -v RS=' ' '{print $1}' | sort -u)
INSTANCE_METADATA=$(echo $METRICS_FOR_VMS | awk -F: -v RS=' ' '{print $2}')
PATTERN=$(echo $INSTANCE_METADATA | sed 's/\(\w*\)/"\1"/g' | tr ' ' '|')
EXPECTED=$(echo $METRICS $INSTANCE_METADATA)
COUNT_EXPECTED=$(echo $EXPECTED | wc -w)
for ID in $VMS; do
	printf "Check Monasca recent measurements for active VM $ID... "
	DIMENSIONS="region:$REGION,resource_id:$ID"
	ACTUAL=""
	for NAME in $METRICS; do
		QUERY="/metrics/measurements?name=$NAME&dimensions=$DIMENSIONS"
		RESPONSE=$(printf_monasca_query "$QUERY&$FILTER")
		COUNT=$(echo "$RESPONSE" | grep -v '"id"' | grep 'Z"' | wc -l)
		[ $COUNT -gt 0 ] && ACTUAL="$ACTUAL $NAME"
	done
	for NAME in "instance"; do
		QUERY="/metrics/measurements?name=$NAME&dimensions=$DIMENSIONS"
		DATA=$(printf_monasca_query "$QUERY&$FILTER" | egrep "$PATTERN")
		METADATA=$(echo "$DATA" | awk -F'"' '{print $2}' | sort -u)
		ACTUAL=$(echo $ACTUAL $METADATA)
	done
	COUNT_ACTUAL=$(echo $ACTUAL | wc -w)
	if [ $COUNT_ACTUAL -ge $COUNT_EXPECTED ]; then
		printf_ok "OK ($COUNT_ACTUAL: $EXPECTED)"
	elif [ $COUNT_ACTUAL -gt 0 ]; then
		printf_warn "$COUNT_ACTUAL out of $COUNT_EXPECTED ($ACTUAL)"
	else
		printf_fail "No measurements found"
		[ -n "$VERBOSE" ] && printf_curl
	fi
done
