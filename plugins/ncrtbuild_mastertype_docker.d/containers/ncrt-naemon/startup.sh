#!/bin/bash

env > /tmp/startup.env

##

if [ "`ls /etc/default/`" = "" ] ;then
	rsync -aSvx /etc/default_orig/ /etc/default/
fi

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
if [ "`ls /var/lib/grafana-dashboard-helper/`" = "" ] ;then
	rsync -aSvx /var/lib/grafana-dashboard-helper_orig/ /var/lib/grafana-dashboard-helper/
fi

##
exec /sbin/init

