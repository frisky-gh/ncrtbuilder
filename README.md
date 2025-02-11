NCRT Builder
====

## Description

NCRT (Nagios / Naemon CRT Monitor) is a plugin-based simple framework. It bases from 3 parts: Builder, Master, and Agent. ncrtbuilder is the Builder part, and deployes Master and Agent part on each nodes by Ansible.

You can write plugins by your favorite language on NCRT framework. Since NCRT needs only simple rules for plugins, plugins can be also described by shell script.

## Requirement

* Perl
* Ansible
* Naemon

## Install

1. clone or unzip.

```
    % git clone https://github.com/frisky-gh/ncrtbuilder.git
```

2. setup config files.

3. run "bin/ncrtbuild".

4. complete.

## Usage


## for Users

The NCRT framework consists of three departments:
  * NCRT Builder — Manages all masters, agents, and settings.
  * NCRT Agents — Monitors the hosts themselves and measures the performance of each host.
  * NCRT Masters — Takes performance values from (typically) the NCRT Agent to determine and report on service health.

NCRT has 3 monitoring method:
  * by agent,
  * by agentless, and
  * by indirect.

Monitoring by agent is intended to monitor VMs such as Linux, Windows, and macOS.
Monitoring by agentless is intended to monitor Internet services, such as HTTP, SMTP, and SNMP.
Monitoring by indirect is intended to monitor  ystem state, such as tasks, jobs, and cluster state, which can be retrieved by commands on the VM.

You may modify setting files in ./conf/ dir.
  * ./conf/agenttype/
  * ./conf/mastertype/
  * ./conf/agent/
  * ./conf/agentless/
  * ./conf/indirect/
  * ./conf/threshold/
  * ./conf/contact/
  * ./conf/reporter/

If you use additional plugins, you put ncrtbuild_* files into ./plugins/ dir, ncrtagent_* files into ./ncrtagent/plugins/ dir, ncrtagentdaemon_* files into ./ncrtagent/bin/ dir, and ncrtmaster_* files into ./ncrtmaster/plugins/ dir.

## for Plug-in Developpers

NCRT has 7 plugin types. All plugins require  their own builder module and also can have optional modules.
  * agenttype : may have agent module.
  * mastertype : may have master module.
  * agent : may have agent module.
  * agentless : may have master module.
  * indirect :may have master and agent module.
  * contact : can not have any other modules. 
  * reporter : may have master module.

## Licence

[MIT](https://github.com/frisky-gh/panopticd/blob/master/LICENSE)

## Author

[frisky-gh](https://github.com/frisky-gh)

