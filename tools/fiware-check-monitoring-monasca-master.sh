#!/bin/sh
# -*- coding: utf-8; version: 1.0.0 -*-
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
# Perform several checks to verify FIWARE Monitoring at Monasca master node
#
# Usage:
#   $0 --help | --version
#   $0 [--verbose] [--context-broker]
#
# Options:
#   -h, --help  		show this help message and exit
#   -V, --version		show version information and exit
#   -v, --verbose		enable verbose messages
#   -b, --context-broker	also perform checks related to ContextBroker
#
# Environment:
#   OS_AUTH_URL			authentication url (Keystone)
#   OS_USERNAME			authentication username
#   OS_PASSWORD			authentication password
#   OS_PROJECT_NAME		authentication project name
#

OPTS='h(help)V(version)v(verbose)b(context-broker)'
PROG=$(basename $0)

# Files
ZOOKEEPER_CONF=/etc/zookeeper/conf/zoo.cfg
PERSISTER_CONF=/etc/monasca/persister-config.yml

# Common definitions
MONASCA_TOPIC=metrics
ZOOKEEPER_PORT=
KAFKA_HOME=
KAFKA_MIN_VER=2.11
ADAPTER_HOME=
ADAPTER_MIN_VER=1.4.1
BROKER_URL=
BROKER_HOST=
BROKER_MIN_VER=0.27.0

# Command line options defaults
VERBOSE=
WITH_BROKER=

# Command line processing
OPTERR=
OPTSTR=$(echo :-:$OPTS | sed 's/([-_a-zA-Z0-9]*)//g')
OPTHLP=$(sed -n '21,/^$/ { s/$0/'$PROG'/; s/^#[ ]\?//; p }' $0)
while getopts $OPTSTR OPT; do while [ -z "$OPTERR" ]; do
case $OPT in
'v')	VERBOSE=true;;
'b')	WITH_BROKER=true;;
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

# Check enviroment variables required as credentials for OpenStack
COUNT=$(env | egrep 'OS_(AUTH_URL|USERNAME|PASSWORD|PROJECT_NAME)' | wc -l)
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
printf_ok() {
	tput setaf 2; printf "$*\n"; tput sgr0
}

printf_warn() {
	tput setaf 3; printf "$*\n"; tput sgr0
}

printf_fail() {
	tput setaf 1; printf "$*\n"; tput sgr0
}

printf_kafka_topics() {
	kafka_home=$1
	zookeeper_endpoint=localhost:$2
	$kafka_home/bin/kafka-topics.sh --list --zookeeper $zookeeper_endpoint
}

version_ge() {
	test "$(printf "$1\n$2" | sort -V | head -1)" = "$2"
}

# Check Zookeeper configuration
printf "Check Zookeeper configuration... "
if [ ! -r $ZOOKEEPER_CONF ]; then
	printf_fail "Configuration file $ZOOKEEPER_CONF not found"
else
	ZOOKEEPER_PORT=$(awk -F= '/clientPort/ {print $2}' $ZOOKEEPER_CONF)
	printf_ok "$ZOOKEEPER_CONF"
fi

# Check Zookeeper server
printf "Check Zookeeper server... "
NAME=zookeeper
PID=$(ps -f -C java | awk '/'$NAME'/ {print $2}')
PORTS=$(netstat -lnpt | awk -F: '/'${PID:-none}'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Kafka installation
printf "Check Kafka installation... "
for DIR in /opt/kafka /opt/kafka_2.*; do
	if [ -d $DIR ]; then
		KAFKA_HOME=$DIR
		LIB=$(find $DIR/libs -name "kafka_*.[0-9].jar" -printf "%f")
		VERSION=$(echo $LIB | awk -F'[-_]' '{print $2}')
		break
	fi
done
if [ -z "$KAFKA_HOME" ]; then
	printf_fail "Not found"
elif ! version_ge $VERSION $KAFKA_MIN_VER; then
	printf_fail "Found version $VERSION, but $KAFKA_MIN_VER is required"
else
	printf_ok "Version $VERSION at $KAFKA_HOME"
fi

# Check Kafka server
printf "Check Kafka server... "
NAME=kafka
PID=$(ps -f -C java | awk '/'$NAME'/ {print $2}')
PORTS=$(netstat -lnpt | awk -F: '/'${PID:-none}'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Kafka topics
printf "Check Kafka topics... "
RESULT=$($KAFKA_HOME/bin/kafka-topics.sh \
	--describe \
	--zookeeper localhost:$ZOOKEEPER_PORT \
	--topic $MONASCA_TOPIC | head -1 | expand -t1 | tr ':' '=')
if [ -z "$RESULT" ]; then
	printf_fail "Topic '$MONASCA_TOPIC' not found"
	[ -n "$VERBOSE" ] && printf_kafka_topics "$KAFKA_HOME" "$ZOOKEEPER_PORT"
else
	printf_ok "$RESULT"
fi

# Check InfluxDB
printf "Check InfluxDB... "
NAME=influxdb
PID=$(ps -f -u $NAME | awk '/'$NAME'/ {print $2}')
PORTS=$(netstat -lnpt | awk -F: '/'${PID:-none}'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Monasca API
printf "Check Monasca API... "
NAME=monasca-api
PID=$(ps -f -C java | awk '/'$NAME'/ {print $2}')
PORTS=$(netstat -lnpt | awk -F: '/'${PID:-none}'/ {print $4}' | sort -n | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check Monasca Agent
printf "Check Monasca Agent... "
NAME=monasca-agent
PID=$(ps -ef | fgrep python | awk '/'$NAME'/ {print $2}')
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID"
fi

# Check Monasca Notification
printf "Check Monasca Notification... "
NAME=monasca-notification
PID=$(ps -ef | fgrep python | awk '/'$NAME'/ {print $2}')
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID"
fi

# Check Monasca Persister server
printf "Check Monasca Persister server... "
NAME=monasca-persister
PID=$(ps -f -C java | awk '/'$NAME'/ {print $2}')
LIB_VER=$(ps -f -C java \
	| sed -n '/'$NAME'/ { s/.*'$NAME'-\?\([^:]*\).*/\1/; s/\.jar//; p }')
VERSION="${PID:+${LIB_VER:-N/A}}"
if [ -z "$PID" ]; then
	printf_fail "Not running"
elif [ -n "$WITH_BROKER" -a "$VERSION" = "${VERSION%-FIWARE}" ]; then
	printf_fail "Found $VERSION, but FIWARE specific version is required"
else
	printf_ok "OK: pid=$PID version=$VERSION"
fi

# Check Monasca Persister configuration
printf "Check Monasca Persister configuration... "
if [ ! -r $PERSISTER_CONF ]; then
	printf_fail "Configuration file $PERSISTER_CONF not found"
else
	printf_ok "$PERSISTER_CONF"
fi

#
# Finalize here, unless --context-broker is enabled
#
[ -n "$WITH_BROKER" ] || exit

# Check NGSI Adapter installation
printf "Check NGSI Adapter installation... "
for DIR in  /opt/fiware/ngsi_adapter; do
	if [ -d $DIR ]; then
		ADAPTER_HOME=$DIR
		VERSION=$(awk -F'"' '/"version"/ {print $4}' $DIR/package.json)
		break
	fi
done
if [ -z "$ADAPTER_HOME" ]; then
	printf_fail "Not found"
elif ! version_ge $VERSION $ADAPTER_MIN_VER; then
	printf_fail "Found version $VERSION, but $ADAPTER_MIN_VER is required"
else
	printf_ok "Version $VERSION at $ADAPTER_HOME"
fi

# Check NGSI Adapter server
printf "Check NGSI Adapter server... "
NAME=ngsi_adapter
PID=$(ps -f -C nodejs | awk '/'$NAME'\/adapter/ {print $2}')
ENV=$(xargs --null --max-args=1 < /proc/$PID/environ)
PORTS=$(netstat -anp \
	| egrep 'udp|LISTEN' \
	| awk '/'${PID:-none}'/ { sub(/0.0.0.0:/,"/"); print toupper($1) $4 }' \
	| sort  | fmt)
if [ -z "$PID" ]; then
	printf_fail "Not running"
else
	printf_ok "OK: pid=$PID ports=${PORTS:-N/A}"
fi

# Check NGSI Adapter configuration
printf "Check NGSI Adapter configuration... "
PARSERS_PATH=$(echo "$ENV" | awk -F= '/ADAPTER_PARSERS_PATH/ {print $2}')
BROKER_URL=$(echo "$ENV" | awk -F= '/ADAPTER_BROKER_URL/ {print $2}')
if [ -z "$PARSERS_PATH" ]; then
	printf_fail "Could not find NGSI Adapter parsers path"
elif [ -z "$BROKER_URL" ]; then
	printf_fail "Could not find NGSI Adapter ContextBroker URL"
else
	printf_ok "parsersPath=$PARSERS_PATH brokerUrl=$BROKER_URL"
fi

# Check NGSI Adapter parser for Monasca
printf "Check NGSI Adapter parser for Monasca... "
PARSER_FILE=
PARSER_DIRS=$(echo $PARSERS_PATH | cut -d: -f2- | tr ':' ' ')
for DIR in $PARSER_DIRS; do
	PARSER_FILE=$(ls -1 $DIR/monasca_*.js)
done
if [ -z "$PARSER_FILE" ]; then
	printf_fail "Could not find parser at $PARSERS_PATH"
else
	PACKAGE=$(dirname $PARSER_FILE)/../package.json
	VERSION=$(awk -F'"' '/version/ {print $4}' $PACKAGE 2>/dev/null)
	printf_ok "Version ${VERSION:-N/A} at $PARSER_FILE"
fi

# Check ContextBroker version
printf "Check ContextBroker version... "
VERSION=$(curl -s -S -H "Accept: application/json" $BROKER_URL/version \
	| awk -F'"' '/version/ {print $4}')
if ! version_ge $VERSION $BROKER_MIN_VER; then
	printf_fail "Found version $VERSION, but $BROKER_MIN_VER is required"
else
	BROKER_HOST=$(echo $BROKER_URL | awk -F'[:/]' '{print $4}')
	printf_ok "Version $VERSION at $BROKER_HOST"
fi

# Check ContextBroker regions
printf "Check ContextBroker regions... "
QUERY="{\"_id.type\": \"region\"}, {\"modDate\": 1}"
REGIONS=$(mongo --quiet --eval "DBQuery.shellBatchSize=100; \
	db.entities.find($QUERY).shellPrint()" $BROKER_HOST/orion 2>/dev/null)
UPDATE_TIMESTAMPS=$(echo "$REGIONS" | awk -F'[ "]' '{print $12 ":" $(NF-1)}')
CURRENT_TIMESTAMP=$(date -u +%s)
VALIDITY_THRESHOLD=$((CURRENT_TIMESTAMP - 3 * 3600))
if [ -z "$(which mongo)" ]; then
	printf_warn "Skipped: no 'mongo' client available"
elif [ -z "$REGIONS" ]; then
	printf_fail "Could not connect to Mongo database at $BROKER_HOST"
else
	printf_ok "$(echo "$REGIONS" | wc -l)"
	for ITEM in $UPDATE_TIMESTAMPS; do
		REGION=${ITEM%:*}
		TIMESTAMP=${ITEM#*:}
		DATE="last update $(date -d @$TIMESTAMP)"
		DIFF=$((TIMESTAMP - VALIDITY_THRESHOLD))
		if [ $DIFF -ge 0 ]; then
			printf_warn "* $REGION: $DATE"
		else
			printf_fail "* $REGION: $DATE ($DIFF seconds outdated)"
		fi
	done
fi
