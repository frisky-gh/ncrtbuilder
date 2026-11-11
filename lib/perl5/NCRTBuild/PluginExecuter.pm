#!/usr/bin/perl

package NCRTBuild::PluginExecuter;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($) {
	my ($class) = @_;
	return bless {
		'pluginsdir'	=> undef,
		'confdir'	=> undef,
		'workdir'	=> undef,
		'filterdir'	=> undef,
		'agentsworkdir' 	=> undef,
		'mastersworkdir'	=> undef,

		'agenttype_plugins'	=> [],
		'agenttypes'		=> [],
		'mastertype_plugins'	=> [],
		'mastertypes'		=> [],
		'agent_plugins' 	=> [],
		'agentless_plugins'	=> [],
		'indirect_plugins'	=> [],
		'contact_plugins'	=> [],
		'reporter_plugins'	=> [],
		'session_builder_plugins'	=> [],
		'notify_builder_plugins'	=> [],
	};
}

#### load template conf.

sub setPluginDirPath ($$) {
	my ($this, $pluginsdir) = @_;
	$$this{pluginsdir} = $pluginsdir;
}

sub setPluginConfigDirPath ($$) {
	my ($this, $confdir) = @_;
	$$this{confdir} = $confdir;
}

sub setPluginWorkDirPath ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub setDistributedAgentBasePath ($$) {
	my ($this, $agentsworkdir) = @_;
	$$this{agentsworkdir} = $agentsworkdir;
}

sub setDistributedMasterBasePath ($$) {
	my ($this, $mastersworkdir) = @_;
	$$this{mastersworkdir} = $mastersworkdir;
}

sub setPlaybookDirPath ($$) {
	my ($this, $playbookdir) = @_;
	$$this{playbookdir} = $playbookdir;
}

sub load ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	die unless -d $confdir;
	die unless -d $workdir;
	die unless -d $pluginsdir;
	$this->loadPlugins;
}

sub loadPlugins ($) {
	my ($this) = @_;
	my $pluginsdir = $$this{pluginsdir};
	opendir my $d, $pluginsdir or do {
		die "$pluginsdir: cannot open, stopped";
	};
	while( my $e = readdir $d ){
		next unless $e =~ m"\Ancrtbuild_(agent|agentless|indirect|agenttype|mastertype|contact|reporter|session|notify)_([-\w]+)\z";
		my ($type, $name) = ($1, $2);
		my $field = $type eq "session" || $type eq "notify"
			? "${type}_builder_plugins"
			: "${type}_plugins";
		push @{ $$this{$field} }, $e;
		push @{ $$this{agenttypes} },  $name if $type eq "agenttype";
		push @{ $$this{mastertypes} }, $name if $type eq "mastertype";
	}
	closedir $d;
}

sub execAgentTypePlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $agentsworkdir = $$this{agentsworkdir};
	my $playbookdir   = $$this{playbookdir};
	my @plugins = sort @{ $$this{agenttype_plugins} };
	foreach my $e ( @plugins ){
		print         "$pluginsdir/$e $confdir $workdir $agentsworkdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $agentsworkdir $playbookdir";
	}
}

sub execMasterTypePlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $mastersworkdir = $$this{mastersworkdir};
	my $playbookdir    = $$this{playbookdir};
	my @plugins = sort @{ $$this{mastertype_plugins} };
	foreach my $e ( @plugins ){
		print         "$pluginsdir/$e $confdir $workdir $mastersworkdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $mastersworkdir $playbookdir";
	}
}

sub execAgentPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir = $$this{playbookdir};
	my @plugins = sort @{ $$this{agent_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

sub execAgentlessPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir    = $$this{playbookdir};
	my @plugins = sort @{ $$this{agentless_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

sub execIndirectPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir = $$this{playbookdir};
	my @plugins = sort @{ $$this{indirect_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

sub execContactPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my @plugins = sort @{ $$this{contact_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir";
	}
}

sub execReporterPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir = $$this{playbookdir};
	my @plugins = sort @{ $$this{reporter_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

sub execSessionBuilderPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir = $$this{playbookdir};
	my @plugins = sort @{ $$this{session_builder_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

sub execNotifyBuilderPlugins ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $workdir = $$this{workdir};
	my $pluginsdir = $$this{pluginsdir};
	my $playbookdir = $$this{playbookdir};
	my @plugins = sort @{ $$this{notify_builder_plugins} };
	foreach my $e ( @plugins ){
		print "$pluginsdir/$e $confdir $workdir $playbookdir\n";
		system_or_die "$pluginsdir/$e $confdir $workdir $playbookdir";
	}
}

####

sub strip_pluginname (@) {
	my @r = @_;
	foreach( @r ){ s/^ncrtbuild_(agenttype|mastertype|agent|agentless|indirect|contact|reporter|session|notify)_//; }
	return sort @r;
}

sub listMasterTypePlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{mastertype_plugins} };
}

sub listAgentTypePlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{agenttype_plugins} };
}

sub listAgentPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{agent_plugins} };
}

sub listAgentlessPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{agentless_plugins} };
}

sub listIndirectPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{indirect_plugins} };
}

sub listContactPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{contact_plugins} };
}

sub listReporterPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{reporter_plugins} };
}

sub listSessionBuilderPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{session_builder_plugins} };
}

sub listNotifyBuilderPlugins ($) {
	my ($this) = @_;
	return strip_pluginname @{ $$this{notify_builder_plugins} };
}

sub listMeasurementPlugins ($) {
	my ($this) = @_;
	return strip_pluginname
		@{ $$this{agent_plugins} },
		@{ $$this{agentless_plugins} },
		@{ $$this{indirect_plugins} };
}


####

1;

