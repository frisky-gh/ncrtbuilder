#
package NCRTBuild::ResourceDistributor;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'workdir' => undef,
		'generator'  => undef,
		'host_service'  => undef,
		'masterhosts'  => undef,
		'reporterpluginsforncrtreport' => [],
		'sessionpluginsforncrtreport' => [],
		'notifypluginsforncrtreport' => [],
	};
}

####

sub setPluginDirPath ($$) {
	my ($this, $plugindir) = @_;
	$$this{plugindir} = $plugindir;
}

sub setFilterDirPath ($$) {
	my ($this, $filterdir) = @_;
	$$this{filterdir} = $filterdir;
}

sub setDistributedDirPathForAgents ($$) {
	my ($this, $workdir4a) = @_;
	$$this{workdir4a} = $workdir4a;
}

sub setDistributedDirPathForMasters ($$) {
	my ($this, $workdir4m) = @_;
	$$this{workdir4m} = $workdir4m;
}

sub setReporterPluginsForNCRTReport ($@) {
	my ($this, @plugins) = @_;
	$$this{reporterpluginsforncrtreport} = \@plugins;
}

sub setSessionPluginsForNCRTReport ($@) {
	my ($this, @plugins) = @_;
	$$this{sessionpluginsforncrtreport} = \@plugins;
}

sub setNotifyPluginsForNCRTReport ($@) {
	my ($this, @plugins) = @_;
	$$this{notifypluginsforncrtreport} = \@plugins;
}

sub setAgentHosts ($@) {
	my ($this, @agenthosts) = @_;
	$$this{agenthosts} = \@agenthosts;
}

sub setMasterHosts ($@) {
	my ($this, @masterhosts) = @_;
	$$this{masterhosts} = \@masterhosts;
}

sub run ($) {
	my ($this) = @_;
	my $plugindir = $$this{plugindir};
	my $filterdir = $$this{filterdir};
	my $workdir4a   = $$this{workdir4a};
	my $workdir4m   = $$this{workdir4m};
	my $agenthosts  = $$this{agenthosts};
	my $masterhosts = $$this{masterhosts};
	my $reporterplugins = $$this{reporterpluginsforncrtreport};
	my $sessionplugins = $$this{sessionpluginsforncrtreport};
	my $notifyplugins = $$this{notifypluginsforncrtreport};

	foreach( @$agenthosts ){
		my $host = $$_{agenthost};
		system_or_die "rsync -aJUSx --include=ncrtagent_\\*\\* --exclude=\\*" .
			" $plugindir/ $workdir4a/$host/plugins/";
	}
	foreach( @$masterhosts ){
		my $host = $$_{masterhost};
		system_or_die "rsync -aJUSx --include=ncrtmaster_\\*\\* --exclude=\\*" .
			" $plugindir/ $workdir4m/$host/plugins/";
		system_or_die "rsync -aJUSx --include=\\*.filter     --exclude=\\*" .
			" $filterdir/ $workdir4m/$host/filters/";
#		system_or_die "rsync -aJUSx" .
#			" $plugindir/ $workdir4a/$host/plugins/";

		# create agenthosts configuration file.
		my $f = "$workdir4m/$host/ncrtconf/agenthosts";
		open my $h, ">", $f or die "$f: cannot open, stopped";
		foreach( sort { $$a{agenthost} cmp $$b{agenthost} } @$agenthosts ){
			my $agenthost = $$_{agenthost};
			my $agenttype = $$_{agenttype};
			my $ansibleparam = $$_{ansibleparam};
			my @params;
			foreach my $k ( sort keys %$ansibleparam ){
				my $v = $$ansibleparam{$k};
				push @params, "$k=$v";
			}
			print $h join("\t", $agenthost, $agenttype, @params), "\n";
		}
		close $h;

		foreach my $entry (
			[ "reporter_plugins", $reporterplugins ],
			[ "session_plugins", $sessionplugins ],
			[ "notify_plugins", $notifyplugins ],
		){
			my ($filename, $plugins) = @$entry;
			my $f = "$workdir4m/$host/ncrtconf/$filename";
			open my $h, ">", $f or die "$f: cannot open, stopped";
			print $h "$_\n" foreach sort @$plugins;
			close $h or die "$f: cannot close, stopped";
		}
	}
}

####

1;

