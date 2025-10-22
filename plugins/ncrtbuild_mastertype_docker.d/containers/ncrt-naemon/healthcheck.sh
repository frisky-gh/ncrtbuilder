#!/bin/bash

/etc/init.d/naemon status || exit 1
/etc/init.d/apache2 status || exit 2
/etc/init.d/cron status || exit 3
/etc/init.d/syslog-ng status || exit 4
/etc/init.d/nullmailer status || exit 5
/etc/init.d/grafana-dashboard-helper status || exit 6

exit 0
