
ARG APT_PROXY

FROM debian:bookworm-slim
RUN test "$APT_PROXY" = "" || ( echo "Acquire::http::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf )

COPY --chown=root:root ./naemon.list /etc/apt/sources.list.d/naemon.list
COPY --chown=root:root ./naemon.asc /etc/apt/keyrings/naemon.asc
RUN apt update
RUN apt install --no-install-recommends -y ansible iproute2 git vim
RUN apt update
RUN apt install --no-install-recommends -y finit-sysv sysv-rc rsyslog apache2 nullmailer cron sudo rsync curl naemon naemon-core naemon-livestatus nagios-plugins nagios-nrpe-plugin thruk naemon-thruk

RUN /lib/finit/initctl disable getty && \
    /lib/finit/initctl disable acpid && \
    /lib/finit/initctl disable sshd  && \
    /lib/finit/initctl disable modules 

##
RUN apt install --no-install-recommends -y liburi-query-perl libhttp-daemon-perl libjson-xs-perl libtemplate-perl

RUN curl -o /root/naemon2influx-1.4-rc2.deb -L https://github.com/frisky-gh/naemon2influx/releases/download/v1.4.2/naemon2influx-1.4-2.deb
RUN dpkg -i /root/naemon2influx-1.4-rc2.deb

RUN curl -o /root/grafana-dashboard-helper_1.0-rc4_amd64.deb -L https://github.com/frisky-gh/grafana-dashboard-helper/releases/download/v1.0-RC/grafana-dashboard-helper_1.0_amd64.deb
RUN dpkg -i /root/grafana-dashboard-helper_1.0-rc4_amd64.deb

##
RUN apt install --no-install-recommends -y lv zsh strace lsof
COPY --chown=root:root ./.zshrc /root/.zshrc

##
COPY --chown=root:root ./sysv-*.conf /etc/finit.d/available/
RUN /lib/finit/initctl enable sysv-apache2
RUN /lib/finit/initctl enable sysv-naemon
RUN /lib/finit/initctl enable sysv-grafana-dashboard-helper
RUN /lib/finit/initctl enable sysv-cron
RUN /lib/finit/initctl enable sysv-nullmailer

RUN rsync -aSvx /etc/apache2/ /etc/apache2_orig/
RUN rsync -aSvx /etc/naemon/ /etc/naemon_orig/
RUN rsync -aSvx /etc/thruk/ /etc/thruk_orig/
RUN rsync -aSvx /etc/grafana-dashboard-helper/ /etc/grafana-dashboard-helper_orig/
RUN rsync -aSvx /var/lib/grafana-dashboard-helper/ /var/lib/grafana-dashboard-helper_orig/

COPY --chown=root:root ./startup.sh /startup.sh
RUN mkdir /opt/ncrtmaster

CMD ["/startup.sh"]
