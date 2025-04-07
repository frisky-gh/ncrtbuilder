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
if [ "`ls /etc/apache2/`" = "" ] ;then
	rsync -aSvx /etc/apache2_orig/ /etc/apache2/
	a2enmod proxy_http
fi

# setup naemon
if [ "`ls /etc/naemon/`" = "" ] ;then
	rsync -aSvx /etc/naemon_orig/ /etc/naemon/
fi

# setup thruk
if [ "`ls /etc/thruk/`" = "" ] ;then
	rsync -aSvx /etc/thruk_orig/ /etc/thruk/
fi

# setup grafana-dashboard-helper
if [ "`ls /etc/grafana-dashboard-helper/`" = "" ] ;then
	rsync -aSvx /etc/grafana-dashboard-helper_orig/ /etc/grafana-dashboard-helper/
fi

##
exec /sbin/init

