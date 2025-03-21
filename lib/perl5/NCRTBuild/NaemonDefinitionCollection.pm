#!/usr/bin/perl

package NCRTBuild::PluginConfigValidator;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'conf'		=> undef,
		'workdir'	=> undef,

		'plugin2type2conffile2format' => undef,
	};
}

####

sub setAgentTypeTemplate ($@) {
	my ($this, @agenttypetemplate) = @_;
	$$this{agenttypetemplate} = \@agenttypetemplate;
}

sub setMeasurementTemplate ($@) {
	my ($this, @measurementtemplate) = @_;
}

sub setHostService ($@) {
	my ($this, @host_service) = @_;
}

sub setWorkDirectory ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub parse ($$$) {
	my ($his, $host_service, @rules) = @_;

}

sub write ($) {
	my ($his) = @_;
}


####

sub generate_shortnamelist ($) {
	return '' unless defined $_[0];
	return join ',', @{$_[0]};
}

sub generate_naemondefline ($\%) {
	my ($naemondef, $params) = @_;
	my @line;
	foreach my $k ( sort keys %$naemondef ){
		my $v = $$naemondef{$k};
		push @line, sprintf "\t%-23s\t%s\n",
			$k, expand_params $v, %$params;
	}
	return @line;
}

sub generate_options ($$$;%) {
	my ($rules, $host, $service, %orig_options) = @_;
	my %options = %orig_options;
	foreach my $rule ( @$rules ){
		my ($host_re, $service_re, %add_options) = @$rule;
		next unless $host =~ m"$host_re";
		next unless $service =~ m"$service_re";
		while( my ($k, $v) = each %add_options ){ $options{$k} = $v; }
	}
	return %options;
}

sub writeAgentTypeTemplate ($) {
	my ($his) = @_;
	my $workdir = $$this{workdir};
	my $agenttypetemplate = $$this{agenttypetemplate};

	my @content;
	foreach my $entry ( @$agenttypetemplate ){
		my $agenttype = $$entry{agenttype};
		my $naemondef = $$entry{naemondef};

		my %param = ( 'agenttype' => $agenttype );
		my @line = generate_naemondefline $naemondef, %param;
		push @content,
			"define host {\n",
			"	name			ncrt-agenttype-$agenttype\n",
			"	use			ncrt-generic-host\n",
			@line,
			"	register		0\n",
			"}\n";
	}
	$workdir->write( "ncrt_hosttemplates.cfg", @content );
}

sub writeMeasurementTemplate ($) {
	my ($his) = @_;
	my $workdir = $$this{workdir};
	my $measurementtemplate = $$this{measurementtemplate};

	my @content;
	foreach my $entry ( @$measurementtemplate ){
		my $measurement = $$entry{measurement};
		my $type        = $$entry{type};
		my $naemondef   = $$entry{naemondef};
		my $check_command;
		if   ( $type eq 'agent' )    { $check_command = "ncrtmaster_detect_by_targetagent"; }
		elsif( $type eq 'agentless' ){ $check_command = "ncrtmaster_detect"; }
		elsif( $type eq 'indirect' ) { $check_command = "ncrtmaster_detect_by_proxyagent"; }
		else{ die; }

		my %param = ( 'measurement' => $measurement );
		my @line = generate_naemondefline $naemondef, %param;
		push @content,
			"define service {\n",
			"	name		ncrtdetector-$measure\n",
			"	check_command	$check_command\n",
			"	_measure	$measure\n",
			"	use		ncrt-generic-service\n",
			@settings,
			"	register	0\n",
			"}\n";
	}
	$workdir->write( "ncrt_servicetemplates.cfg", @content );
}

sub writeHost ($) {
	#### write settings

	my $f = "$WORKDIR/ncrt_hosts.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $host ( sort keys %host2service2measure ){
		my $agenttype = $host2agenttype{$host} // 'virtual';
		my %var = ( 'hostname' => $host, 'agenttype' => $agenttype );
		my %options = generate_options $rules4option,
			$host, "-", %{$agenttype2opts{$agenttype}};
		my @settings = generate_naemoncfgline %options, %var;
		my $contacts = generate_shortnamelist $host2contact{$host};
		my $_urlencoded = uri_escape_utf8($host);
		$contacts = "nobody" if $contacts eq "";
		####
		print $h
		"define host {\n",
		"	host_name		$host\n",
		"	use			ncrt-agenttype-$agenttype\n",
		"	check_command		ncrtmaster_ping\n",
		"	contacts		$contacts\n",
		"	_urlencoded		$_urlencoded\n",
		"	_agenttype		$agenttype\n",
		@settings,
		"}\n";
	}
	close $h;

}

sub writeService ($) {
	my $f = "$WORKDIR/ncrt_services.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $host_service_measure_opts ( @host_service_measure_opts ){
		my ($host, $service, $measure, $hs_opts) = @$host_service_measure_opts;
		my $agenttype = $host2agenttype{$host};
		my $measuretype = $measure2measuretype{$measure};
		my %options = generate_options $rules4option,
			$host, $service,
			%{$measure2opts{$measure}}, %{$hs_opts};
		my %var = ( 'hostname' => $host, 'agenttype' => $agenttype );
		my @settings = generate_naemoncfgline %options, %var;
		my $contacts = generate_shortnamelist $host2service2contact{$host}->{$service};
		my $_urlencoded = uri_escape_utf8($service);
		$contacts = "nobody" if $contacts eq "";
		if    ( $measuretype eq "master" ){
			$agenttype = 'virtual';
		}elsif( $measuretype eq "indirect" ){
			$agenttype = 'virtual';
                }
		####
		print $h
			"define service {\n",
			"       host_name               $host\n",
			"       service_description     $service\n",
			"       use                     ncrtdetector-$measure\n",
			"       contacts                $contacts\n",
			"	_urlencoded		$_urlencoded\n",
			"	_agenttype		$agenttype\n",
			@settings,
			"}\n";
	}
	close $h;
}

sub writeHostGroup ($) {
	my $f = "$WORKDIR/ncrt_hostgroups.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $group ( sort keys %group2host ){
		my $hosts = generate_shortnamelist $group2host{$group};
		print $h
		"define hostgroup {\n",
		"	hostgroup_name		$group\n",
		"	members			$hosts\n",
		"}\n";
	}
	close $h;
}

sub writeServiceGroup ($) {
	my $f = "$WORKDIR/ncrt_servicegroups.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $group ( sort keys %group2host2service ){
		my @r;
		my $host2service_map = $group2host2service{$group};
		foreach my $host ( sort keys %{$host2service_map} ){
			my $service_map = $host2service_map->{$host};
			foreach my $service ( sort keys %{$service_map} ){
				push @r, "$host,$service";
			}
		}
		my $r = join ",", @r;
		print $h
			"define servicegroup {\n",
			"	servicegroup_name	$group\n",
			"	members			$r\n",
			"}\n";
	}
	close $h;
}

sub writeUsers ($) {
	my $f = "$WORKDIR/ncrt_users.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $user ( sort keys %users ){
		print $h
		"define contact {\n",
		"	contact_name		$user\n",
		"	host_notification_commands	ncrtmaster_do_nothing\n",
		"	service_notification_commands	ncrtmaster_do_nothing\n",
		"	host_notification_period	ncrt_notime\n",
		"	service_notification_period	ncrt_notime\n",
		"	host_notification_options	n\n",
		"	service_notification_options	n\n",
		"	host_notifications_enabled	0\n",
		"	service_notifications_enabled	0\n",
		"}\n";
	}
	close $h;
}

sub writeAddresses ($) {
	my $f = "$WORKDIR/ncrt_addresses.cfg";
	open my $h, '>>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach my $address ( sort keys %addresses ){
		print $h
		"define contact {\n",
		"	contact_name			$address\n",
		"	email				$address\n",
		"	host_notification_commands	ncrtmaster_do_nothing\n",
		"	service_notification_commands	ncrtmaster_do_nothing\n",
		"	host_notification_period	ncrt_anytime\n",
		"	service_notification_period	ncrt_anytime\n",
		"	host_notification_options	n\n",
		"	service_notification_options	w,u,c,r\n",
		"	host_notifications_enabled	0\n",
		"	service_notifications_enabled	1\n",
		"}\n";
	}
	close $h;
}

sub writeGenericHostTemplate ($) {
        #### write templates
        my %param = (
                hostname    => '$_HOSTURLENCODED$',
                servicedesc => '$_SERVICEURLENCODED$',
	);
	my $action_url = expand_params $helperurl, %param;

	my $f = "$workdir/ncrt_hosttemplates.cfg";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	print $h <<"EOF";
# host settings for Nagios / Naemon

define host {
	name				ncrt-generic-host
	
	check_command			ncrtmaster_do_nothing
	check_interval			4
	retry_interval			1
	max_check_attempts		3
	check_period			24x7

	notifications_enabled		1
	notification_interval		60
	notification_options		d,u,r
	notification_period		24x7
	contact_groups			

	process_perf_data		1
	event_handler_enabled		1	; Host event handler is enabled
	flap_detection_enabled		1	; Flap detection is enabled
	retain_nonstatus_information	1       ; Retain non-status information across program restarts
	retain_status_information	1       ; Retain status information across program restarts

	register			0	; DONT REGISTER THIS DEFINITION - ITS NOT A REAL HOST, JUST A TEMPLATE!

}

EOF
	close $h;
}

sub writeGenericServiceTemplate ($) {
	my $f = "$workdir/ncrt_servicetemplates.cfg";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	print $h <<"EOF";
# service settings for Nagios / Naemon

define service {
	name				ncrt-generic-service

	active_checks_enabled		1
	passive_checks_enabled		1
	check_freshness			0       ; Default is to NOT check service 'freshness'
	check_interval			4
	retry_interval			1
	max_check_attempts		3
	check_period			24x7

	notifications_enabled		1
	notification_interval		60
	notification_options		w,u,c,r
	notification_period		24x7
	contact_groups			

	is_volatile			0       ; The service is not volatile
	obsess_over_service		1       ; We should obsess over this service (if necessary)
	process_perf_data		1
	event_handler_enabled		1       ; Service event handler is enabled
	flap_detection_enabled		1       ; Flap detection is enabled
	retain_nonstatus_information	1       ; Retain non-status information across program restarts
	retain_status_information	1       ; Retain status information across program restarts

	action_url			$action_url

	register			0	; DONT REGISTER THIS DEFINITION - ITS NOT A REAL SERVICE, JUST A TEMPLATE!
}

EOF
	close $h;

}

