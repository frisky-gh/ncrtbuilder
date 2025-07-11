
ARG APT_PROXY

FROM debian:bookworm-slim
RUN test "$APT_PROXY" = "" || ( echo "Acquire::http::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf )

RUN apt update && apt install --no-install-recommends -y \
	ansible iproute2 git vim \
	sysv-rc apache2 nullmailer cron sudo rsync curl \
	liburi-query-perl libhttp-daemon-perl libjson-xs-perl libtemplate-perl \
	libstring-random-perl libmime-encwords-perl libjson-perl libjson-xs-perl \
	libjson-pp-perl libemail-sender-perl libemail-mime-perl liburi-query-perl \
	libossp-uuid-perl libcarp-always-perl \
	locales-all \
	lv zsh strace lsof jq \
	golang

#### Naemon / Thruk Installation

##
COPY --chown=root:root ./naemon.list /etc/apt/sources.list.d/naemon.list
COPY --chown=root:root ./naemon.asc /etc/apt/keyrings/naemon.asc
RUN apt update && apt install --no-install-recommends -y \
	naemon naemon-core naemon-livestatus nagios-plugins nagios-nrpe-plugin thruk naemon-thruk

##
RUN curl -L -o /root/naemon2influx-1.4-rc2.deb \
	https://github.com/frisky-gh/naemon2influx/releases/download/v1.4.2/naemon2influx-1.4-2.deb \
	&& dpkg -i /root/naemon2influx-1.4-rc2.deb

RUN curl -L -o /root/grafana-dashboard-helper_1.0-rc5_amd64.deb \
	https://github.com/frisky-gh/grafana-dashboard-helper/releases/download/v1.0-RC5/grafana-dashboard-helper_1.0_amd64.deb \
	&& dpkg -i /root/grafana-dashboard-helper_1.0-rc5_amd64.deb && \
	echo "ulimit -n 1024" > /etc/default/grafana-dashboard-helper

#### Init System Option

# sysv init
RUN apt update && apt install --no-install-recommends -y \
	sysvinit-core inetutils-syslogd \
	&& update-rc.d grafana-dashboard-helper defaults \; \
	echo "ulimit -n 1024" >> /etc/default/inetutils-syslogd

# finit
#RUN apt install --no-install-recommends -y finit rsyslog
#RUN /lib/finit/initctl disable getty && \
#    /lib/finit/initctl disable acpid && \
#    /lib/finit/initctl disable sshd  && \
#    /lib/finit/initctl disable modules 
#
#COPY --chown=root:root ./sysv-*.conf /etc/finit.d/available/
#RUN /lib/finit/initctl enable sysv-apache2
#RUN /lib/finit/initctl enable sysv-naemon
#RUN /lib/finit/initctl enable sysv-grafana-dashboard-helper
#RUN /lib/finit/initctl enable sysv-cron
#RUN /lib/finit/initctl enable sysv-nullmailer

####

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d \; \
	mkdir /opt/ncrtmaster \
	&& rsync -aSx /etc/apache2/ /etc/apache2_orig/ \
	&& rsync -aSvx /etc/default/ /etc/default_orig/ \
	&& rsync -aSx /etc/naemon/ /etc/naemon_orig/ \
	&& rsync -aSx /etc/thruk/ /etc/thruk_orig/ \
	&& rsync -aSx /etc/grafana-dashboard-helper/ /etc/grafana-dashboard-helper_orig/ \
	&& rsync -aSx /var/lib/grafana-dashboard-helper/ /var/lib/grafana-dashboard-helper_orig/ \
	&& rsync -aSx /etc/nullmailer/ /etc/nullmailer_orig/

COPY --chown=root:root ./startup.sh /startup.sh

CMD ["/startup.sh"]
