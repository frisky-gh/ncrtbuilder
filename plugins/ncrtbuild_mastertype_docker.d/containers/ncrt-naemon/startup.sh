#!/bin/bash

env > /tmp/startup.env

##

if [ "$SERVERSIDE_PORT" = "" ] ; then
	SERVERSIDE_PORT=80
fi

if [ "$SERVERSIDE_PATH_PREFIX" = "" ] ; then
	SERVERSIDE_PATH_PREFIX=/
fi
test "${SERVERSIDE_PATH_PREFIX##*/}" != "" && SERVERSIDE_PATH_PREFIX=$SERVERSIDE_PATH_PREFIX/

if [ "$NAEMON2INFLUX_OUTPUT" = "" ] ; then
	NAEMON2INFLUX_OUTPUT=http://ncrt-influxdb:8086/
fi
test "${NAEMON2INFLUX_OUTPUT##*/}" != "" && NAEMON2INFLUX_OUTPUT=$NAEMON2INFLUX_OUTPUT/
if [ "$NAEMON2INFLUX_ORG" = "" ] ; then
	NAEMON2INFLUX_ORG=ncrt_org
fi
if [ "$NAEMON2INFLUX_BUCKET" = "" ] ; then
	NAEMON2INFLUX_BUCKET=ncrt_bucket
fi
if [ "$NAEMON2INFLUX_TOKEN" = "" ] ; then
	NAEMON2INFLUX_TOKEN=ncrt_token
fi

if [ "$GDH_LISTENPORT" = "" ] ; then
	GDH_LISTENPORT=46846
fi
if [ "$GDH_GRAFANAURL" = "" ] ; then
	GDH_GRAFANAURL=http://ncrt-grafana:3000/
fi
test "${GDH_GRAFANAURL##*/}" != "" && GDH_GRAFANAURL=$GDH_GRAFANAURL/
if [ "$GDH_GRAFANATOKEN" = "" ] ; then
	GDH_GRAFANATOKEN=XXXXSECRETXXXX
fi
if [ "$GDH_GRAFANADATASOURCE" = "" ] ; then
	GDH_GRAFANADATASOURCE=influxdb
fi
if [ "$GDH_INFLUXDBURL" = "" ] ; then
	GDH_INFLUXDBURL=$NAEMON2INFLUX_OUTPUT
fi
test "${GDH_INFLUXDBURL##*/}" != "" && GDH_INFLUXDBURL=$GDH_INFLUXDBURL/
if [ "$GDH_INFLUXDBBUCKET" = "" ] ; then
	GDH_INFLUXDBBUCKET=$NAEMON2INFLUX_BUCKET
fi

##

# setup apache2
rsync -aSvx /etc/apache2_orig/ /etc/apache2/

sed -i	-e "s|^Listen 80|Listen ${SERVERSIDE_PORT}|" \
	/etc/apache2/ports.conf
sed -i  -e "s|^  Alias /thruk|  Alias ${SERVERSIDE_PATH_PREFIX}thruk|" \
	-e "s|^  AliasMatch \\^/thruk|  AliasMatch ^${SERVERSIDE_PATH_PREFIX}thruk|" \
	-e "s|^  <Location /thruk|  <Location ${SERVERSIDE_PATH_PREFIX}thruk|" \
	/etc/apache2/conf-available/thruk.conf

a2enmod proxy_http
cat >> /etc/apache2/sites-enabled/000-default.conf <<EOF

ProxyPreserveHost On
ProxyPass        ${SERVERSIDE_PATH_PREFIX}grafana/ $GDH_GRAFANAURL
ProxyPassReverse ${SERVERSIDE_PATH_PREFIX}grafana/ $GDH_GRAFANAURL

ProxyPass	 ${SERVERSIDE_PATH_PREFIX}grafana-dashboard-helper/ http://localhost:46846/
ProxyPassReverse ${SERVERSIDE_PATH_PREFIX}grafana-dashboard-helper/ http://localhost:46846/
EOF

# setup naemon
rsync -aSvx /etc/naemon_orig/ /etc/naemon/
rsync -aSvx /opt/ncrtmaster/containersettings/naemon_conf/ /etc/naemon/conf.d/

cat >> /etc/naemon/naemon.cfg <<'EOF'

process_performance_data=1
service_perfdata_file_processing_command=ncrt-process-service-perfdata-naemon2influx
service_perfdata_file_mode=a
service_perfdata_file_processing_interval=5
service_perfdata_file_template=$TIMET$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEPERFDATA$
service_perfdata_file=/var/lib/naemon/service-perfdata
EOF

# setup naemon2influx
cat >> /etc/naemon/naemon2influx.cfg <<EOF

perfdata=/var/lib/naemon/service-perfdata
perflineregexp=^(?<time>\S+)\t(?<hostname>\S+)\t(?<servicename>\S+)\t(?<state>\S+)\t(?<data>.*)
enable_optional_values=1

measurement=ncrt_<servicename>,host=<hostname>
fieldkey=<label>

apiver=2
output=$NAEMON2INFLUX_OUTPUT
org=$NAEMON2INFLUX_ORG
bucket=$NAEMON2INFLUX_BUCKET
token=$NAEMON2INFLUX_TOKEN

* if <name_of_optional_value> ne ""
	measurement=ncrt_<servicename>,host=<hostname>,option=<name_of_optional_value>
	#fieldkey=<label>.<name_of_optional_value>
	bucket=$NAEMON2INFLUX_OPTIONALBUCKET
EOF

# setup thruk
rsync -aSvx /etc/thruk_orig/ /etc/thruk/
sed -i	-e "s|^url_prefix = /|url_prefix = ${SERVERSIDE_PATH_PREFIX}|" \
	/etc/thruk/thruk.conf
rsync -aSvx /opt/ncrtmaster/containersettings/thruk_conf/htpasswd /etc/thruk/htpasswd

# setup grafana-dashboard-helper
cat > /etc/grafana-dashboard-helper/grafana-dashboard-helper.conf <<EOF
GDHLISTENADDR=0.0.0.0
GDHLISTENPORT=$GDH_LISTENPORT
GDHURL=${URL_PREFIX}grafana-dashboard-helper/
GDHGRAFANAURL=${URL_PREFIX}grafana/

GRAFANAURL=$GDH_GRAFANAURL
GRAFANATOKEN=$GDH_GRAFANATOKEN
GRAFANADATASOURCE=$GDH_GRAFANADATASOURCE

INFLUXDBURL=$GDH_INFLUXDBURL
INFLUXDBBUCKET=$GDH_INFLUXDBBUCKET
INFLUXDBORG=ncrt_org
INFLUXDBTOKEN=ncrt_token

DEBUG=1

PLUGIN_NCRT_OPTIONALBUCKET=$INFLUXDBOPTIONALBUCKET
PLUGIN_NCRT_GENERIC_PANELPRIORITY=50
PLUGIN_GENERIC_PANELPRIORITY=90
EOF

##


##
exec /sbin/init

