#!/usr/bin/perl

package NCRTBuild::NaemonDefinitionDistributor;

use Exporter import;
our @EXPORT = (
);

use strict;
use URI::Escape;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'conf'		=> undef,
		'outputdir'	=> undef,

		'action_url' => undef,
		'generator' => undef,

		'agenttypetemplates' => undef,
		'measurementtemplates' => undef,
		'agenthosts' => undef,
		'pseudohosts' => undef,
	};
}

####

sub setActionURL ($$) {
	my ($this, $action_url) = @_;
	$$this{action_url} = $action_url;
}

sub setAgentTypes ($@) {
	my ($this, @agenttypes) = @_;
	$$this{agenttypes} = \@agenttypes;

	my %agenttype2naemondirective;
	foreach( @agenttypes ){
		my $agenttype       = $$_{agenttype};
		my $naemondirective = $$_{naemondirective_of_instance};
		$agenttype2naemondirective{$agenttype} = $naemondirective;
	}
	$$this{agenttype2naemondirective} = \%agenttype2naemondirective;
}

sub setMeasurements ($@) {
	my ($this, @measurements) = @_;
	$$this{measurements} = \@measurements;

	my %measurement2type2naemondirective;
	foreach( @measurements ){
		my $measurement     = $$_{measurement};
		my $type            = $$_{type};
		my $naemondirective = $$_{naemondirective_of_instance};
		$measurement2type2naemondirective{$measurement}->{$type} = $naemondirective;
	}
	$$this{measurement2type2naemondirective} = \%measurement2type2naemondirective;
}

sub setAgentHosts ($@) {
	my ($this, @agenthosts) = @_;
	$$this{agenthosts} = \@agenthosts;
}

sub setPseudoHosts ($@) {
	my ($this, @pseudohosts) = @_;
	$$this{pseudohosts} = \@pseudohosts;
}

sub setMonitoredHostServices ($@) {
	my ($this, @monitoredhostservices) = @_;
	$$this{monitoredhostservices} = \@monitoredhostservices;
}

sub setUsers ($@) {
	my ($this, @monitoredhostusers) = @_;
	$$this{monitoredhostusers} = \@monitoredhostusers;
}

sub setMonitoredHostGroups ($@) {
	my ($this, @monitoredhostgroups) = @_;
	$$this{monitoredhostgroups} = \@monitoredhostgroups;

	my %group2monitoredhosts;
	foreach( @monitoredhostgroups ){
		my $host  = $$_{host};
		my $groups = $$_{groups};
		foreach my $group ( @$groups ){
			$group2monitoredhosts{$group}->{$host} = 1;
		}
	}
	$$this{group2monitoredhosts} = \%group2monitoredhosts;
}

sub setMonitoredHostUsers ($@) {
	my ($this, @monitoredhostusers) = @_;
	$$this{monitoredhostusers} = \@monitoredhostusers;

	my %monitoredhost2users;
	foreach( @monitoredhostusers ){
		my $host  = $$_{host};
		my $users = $$_{users};
		foreach my $user ( @$users ){
			$monitoredhost2users{$host}->{$user} = 1;
		}
	}
	$$this{monitoredhost2users} = \%monitoredhost2users;
}

sub setMonitoredHostServiceGroups ($@) {
	my ($this, @monitoredhostservicegroups) = @_;
	$$this{monitoredhostservicegroups} = \@monitoredhostservicegroups;

	my %group2monitoredhost2services;
	foreach( @monitoredhostservicegroups ){
		my $host    = $$_{host};
		my $service = $$_{service};
		my $groups  = $$_{groups};
		foreach my $group ( @$groups ){
			$group2monitoredhost2services{$group}->{$host}->{$service} = 1;
		}
	}
	$$this{group2monitoredhost2services} = \%group2monitoredhost2services;
}

sub setMonitoredHostServiceUsers ($@) {
	my ($this, @monitoredhostserviceusers) = @_;
	$$this{monitoredhostserviceusers} = \@monitoredhostserviceusers;

	my %monitoredhost2service2users;
	foreach( @monitoredhostserviceusers ){
		my $host    = $$_{host};
		my $service = $$_{service};
		my $users   = $$_{users};
		foreach my $user ( @$users ){
			$monitoredhost2service2users{$host}->{$service}->{$user} = 1;
		}
	}
	$$this{monitoredhost2service2users} = \%monitoredhost2service2users;
}

sub setOutputDir ($$) {
	my ($this, $outputdir) = @_;
	$$this{outputdir} = $outputdir;
}

sub setMasterHosts ($@) {
	my ($this, @masterhosts) = @_;
	$$this{masterhosts} = \@masterhosts;
}

sub setNaemonDirectiveGenerator ($@) {
	my ($this, $generator) = @_;
	$$this{generator} = $generator;
}


####

sub merge ($) {
	my ($this) = @_;
	my $monitoredhostservices       = $$this{monitoredhostservices};
	my $agenthosts                  = $$this{agenthosts};
	my $pseudohosts                 = $$this{pseudohosts};

	my $generator                           = $$this{generator};
	my $agenttype2naemondirective        = $$this{agenttype2naemondirective};
	my $measurement2type2naemondirective = $$this{measurement2type2naemondirective};
	my $monitoredhost2users              = $$this{monitoredhost2users};
	my $monitoredhost2service2users      = $$this{monitoredhost2service2users};

	## merge Naemon directives
	# merge AgentHosts and AgentTypes
	foreach( @$agenthosts ){
		my $agenttype = $$_{agenttype};
		$$_{naemondirective} = { %{$$agenttype2naemondirective{$agenttype}} };
	}
	# merge MonitoredHostService and Measurements
	foreach( @$monitoredhostservices ){
		my $measurement     = $$_{measurement};
		my $measurementtype = $$_{measurementtype};
		$$_{naemondirective} = { %{$$measurement2type2naemondirective{$measurement}->{$measurementtype}} };
	}
	# merge MonitoredHostService and NaemonDirectiveRules
	foreach( @$monitoredhostservices ){
		my $host = $$_{host};
		my $service = $$_{service};
		my $naemondirective = $$_{naemondirective};
		my %overridenaemondirective = $generator->generate( $host, $service );
		$$_{naemondirective} = { %$naemondirective, %overridenaemondirective };
	}

	## merge contacts
	# merge AgentHosts and MonitoredHostUsers
	foreach( @$agenthosts ){
		my $host = $$_{agenthost};
		$$_{contacts} = $$monitoredhost2users{$host};
	}
	# merge PseudoHosts and MonitoredHostUsers
	foreach( @$pseudohosts ){
		my $host = $$_{pseudohost};
		$$_{contacts} = $$monitoredhost2users{$host};
	}
	# merge MonitoredHostService and MonitoredHostServiceUsers
	foreach( @$monitoredhostservices ){
		my $host = $$_{host};
		my $service = $$_{service};
		$$_{contacts} = $$monitoredhost2service2users{$host}->{$service};
	}
}

####

sub run ($) {
	my ($this) = @_;

	$this->merge;

	$this->writeAgentTypeTemplates;
	$this->writeMeasurements;
	$this->writeAgentHosts;
	$this->writePseudoHosts;
	$this->writeMonitoredHostServices;
	$this->writeMonitoredHostGroups;
	$this->writeMonitoredHostServiceGroups;
	$this->writeUsers;
	$this->writeGroups;
	$this->writeGenericHostTemplate;
	$this->writeGenericServiceTemplate;
}

sub writeAgentTypeTemplates ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $agenttypes = $$this{agenttypes};

	my @content;
	foreach my $entry ( @$agenttypes ){
		my $agenttype = $$entry{agenttype};
		my $naemondirective = $$entry{naemondirective};

		my @line = generate_naemondirectiveline $naemondirective, %$entry;
		push @content,
			"define host {",
			"	name			ncrt-agenttype-$agenttype",
			"	use			ncrt-generic-host",
			@line,
			"	register		0",
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_agenttypetemplates.cfg", @content );
}

sub writeMeasurements ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $measurements = $$this{measurements};

	my @content;
	foreach my $entry ( @$measurements ){
		my $measurement = $$entry{measurement};
		my $type        = $$entry{type};
		my $naemondirective = $$entry{naemondirective};
		my $check_command;
		if   ( $type eq 'agent' )    { $check_command = "ncrtmaster_detect_by_targetagent"; }
		elsif( $type eq 'agentless' ){ $check_command = "ncrtmaster_detect"; }
		elsif( $type eq 'indirect' ) { $check_command = "ncrtmaster_detect_by_proxyagent"; }
		else{ die; }

		my @line = generate_naemondirectiveline $naemondirective, %$entry;
		push @content,
			"define service {",
			"	name		ncrtdetector-$measurement",
			"	check_command	$check_command",
			"	_measure	$measurement",
			"	use		ncrt-generic-service",
			@line,
			"	register	0",
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_measurementtemplates.cfg", @content );
}

sub writeAgentHosts ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $agenthosts = $$this{agenthosts};

	my @content;
	foreach my $entry ( @$agenthosts ){
		my $agenthost       = $$entry{agenthost};
		my $agenttype       = $$entry{agenttype};
		my $naemondirective = $$entry{naemondirective};
		my $contacts        = generate_shortnamelist_or_nobody sort keys %{$$entry{contacts}};

		my @line = generate_naemondirectiveline $naemondirective, %$entry;
		my $host_urlencoded = uri_escape_utf8($agenthost);
		push @content,
			"define host {",
			"	host_name		$agenthost",
			"	use			ncrt-agenttype-$agenttype",
			"	check_command		ncrtmaster_ping",
			"	contacts		$contacts",
			"	_urlencoded		$host_urlencoded",
			"	_agenttype		$agenttype",
			@line,
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_agenthosts.cfg", @content );
}

sub writePseudoHosts ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $pseudohosts = $$this{pseudohosts};

	my @content;
	foreach my $entry ( @$pseudohosts ){
		my $host            = $$entry{pseudohost};
		my $naemondirective = $$entry{naemondirective};
		my $contacts        = generate_shortnamelist_or_nobody sort keys %{$$entry{contacts}};
		my @line = generate_naemondirectiveline $naemondirective, %$entry;
		my $host_urlencoded = uri_escape_utf8($host);
		push @content,
			"define host {",
			"	host_name		$host",
			"	use			ncrt-agenttype-pseudo",
			"	check_command		ncrtmaster_nothing",
			"	contacts		$contacts",
			"	_urlencoded		$host_urlencoded",
			"	_agenttype		pseudo",
			@line,
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_pseudohosts.cfg", @content );
}

sub writeMonitoredHostServices ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $monitoredhostservices = $$this{monitoredhostservices};

	my @content;
	foreach my $entry ( @$monitoredhostservices ){
		my $host        = $$entry{host};
		my $service     = $$entry{service};
		my $agenttype   = $$entry{agenttype};
		my $measurement = $$entry{measurement};
		my $naemondirective = $$entry{naemondirective};
		my @contacts = sort keys %{$$entry{contacts}};
		my $contacts = generate_shortnamelist_or_nobody @contacts;

		my @line = generate_naemondirectiveline $naemondirective, %$entry;
		my $service_urlencoded = uri_escape_utf8($service);

		####
		push @content,
			"define service {",
			"	host_name		$host",
			"	service_description	$service",
			"	use			ncrtdetector-$measurement",
			"	contacts		$contacts",
			"	_urlencoded		$service_urlencoded",
			"	_agenttype		$agenttype",
			@line,
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_hostservices.cfg", @content );
}

sub writeMonitoredHostGroups ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $group2monitoredhosts = $$this{group2monitoredhosts};

	my @content;
	foreach my $group ( sort keys %$group2monitoredhosts ){
		my $monitoredhosts = $$group2monitoredhosts{$group};
		my $monitoredhostlist = join ",", sort keys %$monitoredhosts;
		push @content,
			"define hostgroup {",
			"	hostgroup_name		$group",
			"	members			$monitoredhostlist",
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_hostgroups.cfg", @content );
}

sub writeMonitoredHostServiceGroups ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $group2monitoredhost2services = $$this{group2monitoredhost2services};

	my @content;
	foreach my $group ( sort keys %$group2monitoredhost2services ){
		my $monitoredhost2services = $$group2monitoredhost2services{$group};
		my @hostservices;
		foreach my $monitoredhost ( sort keys %$monitoredhost2services ){
			my $services = $$monitoredhost2services{$monitoredhost};
			foreach my $service ( sort keys %$services ){
				push @hostservices, "$monitoredhost,$service";
			}
		}
		my $hostservicelist = join ",", @hostservices;
		push @content,
			"define servicegroup {",
			"	servicegroup_name	$group",
			"	members			$hostservicelist",
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_hostservicegroups.cfg", @content );
}

sub writeUsers ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $users = $$this{users};

	my @content;
	foreach my $entry ( @$users ){
		my $user = $$entry{user};

		####
		push @content,
			"define contact {",
			"	contact_name		$user",
			"	host_notification_commands	ncrtmaster_do_nothing",
			"	service_notification_commands	ncrtmaster_do_nothing",
			"	host_notification_period	ncrt_notime",
			"	service_notification_period	ncrt_notime",
			"	host_notification_options	n",
			"	service_notification_options	n",
			"	host_notifications_enabled	0",
			"	service_notifications_enabled	0",
			"}";
	}
	$outputdir->writeToAllHosts( "ncrt_users.cfg", @content );
}

sub writeGroups ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $groups = $$this{groups};

	my @content;
#	foreach my $entry ( @$groups ){
#		my $group = $$entry{group};

		####
#		push @content,
#			"define contact {",
#			"	contact_name		$group",
#			"	host_notification_commands	ncrtmaster_do_nothing",
#			"	service_notification_commands	ncrtmaster_do_nothing",
#			"	host_notification_period	ncrt_notime",
#			"	service_notification_period	ncrt_notime",
#			"	host_notification_options	n",
#			"	service_notification_options	n",
#			"	host_notifications_enabled	0",
#			"	service_notifications_enabled	0",
#			"}";
#	}
	$outputdir->writeToAllHosts( "ncrt_groups.cfg", @content );
}

sub writeGenericHostTemplate ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};

	my @content;
	push @content,
		"# host settings for Nagios / Naemon",
		"define host {",
		"	name				ncrt-generic-host",
	
		"	check_command			ncrtmaster_do_nothing",
		"	check_interval			4",
		"	retry_interval			1",
		"	max_check_attempts		3",
		"	check_period			24x7",

		"	notifications_enabled		1",
		"	notification_interval		60",
		"	notification_options		d,u,r",
		"	notification_period		24x7",
		"	contact_groups			",

		"	process_perf_data		1",
		"	event_handler_enabled		1	; Host event handler is enabled",
		"	flap_detection_enabled		1	; Flap detection is enabled",
		"	retain_nonstatus_information	1       ; Retain non-status information across program restarts",
		"	retain_status_information	1       ; Retain status information across program restarts",
		"	register			0	; DONT REGISTER THIS DEFINITION - ITS NOT A REAL HOST, JUST A TEMPLATE!",
		"}";
	$outputdir->writeToAllHosts( "ncrt_generichosttemplate.cfg", @content );
}

sub writeGenericServiceTemplate ($) {
	my ($this) = @_;
	my $outputdir = $$this{outputdir};
	my $action_url = $$this{action_url};

	my @content;
	push @content,
		"# service settings for Nagios / Naemon",

		"define service {",
		"	name				ncrt-generic-service",

		"	active_checks_enabled		1",
		"	passive_checks_enabled		1",
		"	check_freshness			0       ; Default is to NOT check service 'freshness'",
		"	check_interval			4",
		"	retry_interval			1",
		"	max_check_attempts		3",
		"	check_period			24x7",

		"	notifications_enabled		1",
		"	notification_interval		60",
		"	notification_options		w,u,c,r",
		"	notification_period		24x7",
		"	contact_groups			",

		"	is_volatile			0       ; The service is not volatile",
		"	obsess_over_service		1       ; We should obsess over this service (if necessary)",
		"	process_perf_data		1",
		"	event_handler_enabled		1       ; Service event handler is enabled",
		"	flap_detection_enabled		1       ; Flap detection is enabled",
		"	retain_nonstatus_information	1       ; Retain non-status information across program restarts",
		"	retain_status_information	1       ; Retain status information across program restarts",

		"	action_url			$action_url",

		"	register			0	; DONT REGISTER THIS DEFINITION - ITS NOT A REAL SERVICE, JUST A TEMPLATE!",
		"}";
	$outputdir->writeToAllHosts( "ncrt_genericservicetemplate.cfg", @content );
}

####

1;

