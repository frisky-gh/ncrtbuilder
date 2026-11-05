NCRT Builder
====

## Description

NCRT (Nagios / Naemon CRT Monitor) is a plugin-based simple framework. It bases from 3 parts: Builder, Master, and Agent. ncrtbuilder is the Builder part, and deployes Master and Agent part on each nodes by Ansible.

You can write plugins by your favorite language on NCRT framework. Since NCRT needs only simple rules for plugins, plugins can be also described by shell script.

## Features

NCRT Builder generates Naemon definitions and plugin configurations from monitoring targets and rules, then distributes them to monitoring masters and agents with Ansible. Its main features include:

* **Multiple monitoring methods** — Monitor hosts with agents, check services such as HTTP without agents, or combine agents and masters for indirect monitoring.
* **Automated configuration generation** — Generate Naemon definitions for hosts, services, groups, and contacts, as well as plugin configurations, thresholds, and metric and threshold filters.
* **Distribution and deployment** — Assign the required configurations and plugins to each target host and deploy them to masters and agents with Ansible.
* **Plugin extensibility** — Extend functionality with plugins for agent types, master types, monitoring, contacts, and reporting.
* **Deployment controls** — Run deployments for masters or agents only, select target hosts, or use dry-run mode.

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

```
    % bin/ncrtbuild [options]
```

### Command-line options

| Option | Description |
|---|---|
| `--workdir DIR`, `--work-dir DIR` | Use `DIR` as the work directory instead of `/tmp/ncrt_work.<PID>`. Implies `--no-cleanup`. |
| `--no-cleanup` | Keep the work directory after the run. |
| `--master-only` | Deploy only to NCRT Masters (skip Agents). |
| `--agent-only` | Deploy only to NCRT Agents (skip Masters). |
| `--target-master REGEX` | Deploy only to Masters whose name matches `REGEX` (anchored as `^REGEX$`). |
| `--target-agent REGEX` | Deploy only to Agents whose name matches `REGEX` (anchored as `^REGEX$`). |
| `--dryrun`, `--dry-run` | Print the `ansible-playbook` commands without running them. |
| `--quick` | Skip the `commoninstall` tag in Ansible, omitting package installation steps. |
| `--threshold-only` | Accepted, but currently has no effect. |


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

NCRT official reository contains following plugins:
  * agenttype
      * linux
      * macos
      * windows
  * mastertype
      * docker
      * linux
  * agent
      * disk
      * io
      * logfile
      * networkserverperf
      * networktraffic
      * osperf
      * proc
  * agentless
      * livestatus
      * webactivity
  * indirect
      * ltsv
  * contact
      * hostmanagementteam
  * reporter
      * servicegroup

You may modify setting files in ./conf/ dir.
  * ./conf/agenttype/
  * ./conf/mastertype/
  * ./conf/agent/
  * ./conf/agentless/
  * ./conf/indirect/
  * ./conf/threshold/
  * ./conf/contact/
  * ./conf/reporter/

If you use additional plugins, you put ncrtbuild_* files into ./plugins/ dir, ncrtagent_* files into ./ncrtagent/plugins/ dir, and ncrtmaster_* files into ./ncrtmaster/plugins/ dir.

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
