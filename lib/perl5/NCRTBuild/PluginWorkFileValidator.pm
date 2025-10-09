#!/usr/bin/perl

package NCRTBuild::PluginWorkFileValidator;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'inputdir'	=> undef,

		'agenttype2hosttemplatedirective'	=> undef,
		'agenttype2hostdirective'		=> undef,
		'measurement2servicetemplatedirective'	=> undef,
		'measurement2servicedirective'		=> undef,
		'agenthost2service2directive'		=> undef,
		'agenthost2service2overridedirective'	=> undef,
	};
}

####

sub setInputDir ($$) {
	my ($this, $inputdir) = @_;
	$$this{inputdir} = $inputdir;
}

sub load ($) {
	my ($this) = @_;

	$this->loadMasterTypes;
	$this->loadAgentTypes;
	$this->loadMasterHosts;
	$this->loadAgentHosts;
	$this->loadMeasurements;
	$this->loadMonitoredHost2Service2Measurement;
	$this->loadPlugin2Type2PluginConf2Format;
	$this->loadReporters;
	$this->loadGroups;
	$this->loadUsers;
	$this->loadMonitoredHostGroups;
	$this->loadMonitoredHostUsers;
	$this->loadMonitoredHostServiceGroups;
	$this->loadMonitoredHostServiceUsers;
	$this->loadPseudoHost2Service2BackendHost;

	$this->calculatePseudoHosts;
}

####

sub loadMasterTypes ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %mastertype;

	my @content = $inputdir->read( "mastertypes" );
	foreach( @content ){
		my ($err, $mastertype) = parse_item_with_params $_;
		print "mastertypes: $err\n" if $err;
		next unless defined $mastertype;
		$mastertype                            {$mastertype} = 1;
	}
	$$this{mastertype}                             = \%mastertype;
}

sub loadAgentTypes ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %agenttype;
	my %agenttype2naemondirective;
	my %agenttype2naemondirective_of_instance;

	my @content = $inputdir->read( "agenttypes" );
	foreach( @content ){
		my ($err, $agenttype, $naemondirective_of_instance, $naemondirective) = parse_item_with_params $_;
		print "agenttypes: $err\n" if $err;
		next unless defined $agenttype;
		$agenttype                            {$agenttype} = 1;
		$agenttype2naemondirective            {$agenttype} = $naemondirective;
		$agenttype2naemondirective_of_instance{$agenttype} = $naemondirective_of_instance;
	}
	$$this{agenttype}                             = \%agenttype;
	$$this{agenttype2naemondirective}             = \%agenttype2naemondirective;
	$$this{agenttype2naemondirective_of_instance} = \%agenttype2naemondirective_of_instance;
}

sub loadMasterHosts ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %masterhost;
	my %masterhost2mastertype;
	my %masterhost2ansibleparam;

	my @content = $inputdir->read( "masterhosts" );
	foreach( @content ){
		my ($err, $masterhost, $mastertype, $ansibleparam) = parse_2items_with_params $_;
		print "masterhosts: $err\n" if $err;
		next unless defined $masterhost;
		$masterhost             {$masterhost} = 1;
		$masterhost2mastertype  {$masterhost} = $mastertype;
		$masterhost2ansibleparam{$masterhost} = $ansibleparam;
	}
	$$this{masterhost}              = \%masterhost;
	$$this{masterhost2type}         = \%masterhost2mastertype;
	$$this{masterhost2ansibleparam} = \%masterhost2ansibleparam;
}

sub loadAgentHosts ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %agenthost;
	my %agenthost2agenttype;
	my %agenthost2ansibleparam;

	my @content = $inputdir->read( "agenthosts" );
	foreach( @content ){
		my ($err, $agenthost, $agenttype, $ansibleparam) = parse_2items_with_params $_;
		print "agenthosts: $err\n" if $err;
		next unless defined $agenthost;
		$agenthost             {$agenthost} = 1;
		$agenthost2agenttype   {$agenthost} = $agenttype;
		$agenthost2ansibleparam{$agenthost} = $ansibleparam;
	}
	$$this{agenthost}              = \%agenthost;
	$$this{agenthost2agenttype}    = \%agenthost2agenttype;
	$$this{agenthost2ansibleparam} = \%agenthost2ansibleparam;
}

sub loadMeasurements ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %measurement;
	my %measurement2type;
	my %measurement2naemondirective;
	my %measurement2naemondirective_of_instance;

	my @content = $inputdir->read( "measurements" );
	foreach( @content ){
		my ($err, $measurement, $type, $naemondirective_of_instance, $naemondirective) = parse_2items_with_params $_;
		print "measurements: $err\n" if $err;
		next unless defined $measurement;
		$measurement                            {$measurement} = 1;
		$measurement2type                       {$measurement} = $type;
		$measurement2naemondirective            {$measurement} = $naemondirective;
		$measurement2naemondirective_of_instance{$measurement} = $naemondirective_of_instance;
	}
	$$this{measurement}                             = \%measurement;
	$$this{measurement2type}                        = \%measurement2type;
	$$this{measurement2naemondirective}             = \%measurement2naemondirective;
	$$this{measurement2naemondirective_of_instance} = \%measurement2naemondirective_of_instance;
}

sub loadMonitoredHost2Service2Measurement ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %monitoredhost2service;
	my %monitoredhost2service2measurement;

	my @content = $inputdir->read( "monitoredhost2service2measurement" );
	foreach( @content ){
		my ($err, $monitoredhost, $service, $measurement) = parse_3items_with_params $_;
		print "monitoredhost2service2measurement: $err\n" if $err;
		next unless defined $monitoredhost;
		$monitoredhost2service            {$monitoredhost}             = $service;
		$monitoredhost2service2measurement{$monitoredhost}->{$service} = $measurement;
	}
	$$this{monitoredhost2service}             = \%monitoredhost2service;
	$$this{monitoredhost2service2measurement} = \%monitoredhost2service2measurement;
}

sub loadPlugin2Type2PluginConf2Format ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %type2plugin2pluginconfs;
	my %type2pluginconf2format;

	my @content = $inputdir->read( "plugin2type2pluginconf2format" );
	foreach( @content ){
		my ($err, $plugin, $type, $pluginconf, $format) = parse_4items_with_params $_;
		print "plugin2type2pluginconf2format: $err\n" if $err;
		next unless defined $plugin;
		$type2plugin2pluginconfs{$type}->{$plugin}->{$pluginconf} = 1;
		$type2pluginconf2format{$type}->{$pluginconf} = $format;
	}
	$$this{type2plugin2pluginconfs} = \%type2plugin2pluginconfs;
	$$this{type2pluginconf2format} = \%type2pluginconf2format;
}

sub loadReporters ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %reporters;

	my @content = $inputdir->read( "reporters" );
	foreach( @content ){
		my ($err, $reporter, $params) = parse_item_with_params $_;
		print "reporters: $err\n" if $err;
		next unless defined $reporter;
		$reporters{$reporter} = $params;
	}
	$$this{reporters} = \%reporters;
}

sub loadGroups ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %groups;

	my @content = $inputdir->read( "groups" );
	foreach( @content ){
		my ($err, $group, $profile) = parse_item_with_params $_;
		print "groups: $err\n" if $err;
		next unless defined $group;
		$groups{$group} = $profile;
	}
	$$this{groups} = \%groups;
}

sub loadUsers ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %users;

	my @content = $inputdir->read( "users" );
	foreach( @content ){
		my ($err, $user, $profile) = parse_item_with_params $_;
		print "users: $err\n" if $err;
		next unless defined $user;
		$users{$user} = $profile;
	}
	$$this{users} = \%users;
}

sub loadMonitoredHostGroups ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %monitoredhost2groups;

	my @content = $inputdir->read( "monitoredhost2group" );
	foreach( @content ){
		my ($err, $monitoredhost, $grouplist) = parse_2items_with_params $_;
		print "monitoredhost2group: $err\n" if $err;
		next unless defined $monitoredhost;
		my @group = split m",", $grouplist;
		foreach my $group ( @group ){
			$monitoredhost2groups{$monitoredhost}->{$group} = 1;
		}
	}
	$$this{monitoredhost2groups} = \%monitoredhost2groups;
}

sub loadMonitoredHostUsers ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %monitoredhost2users;

	my @content = $inputdir->read( "monitoredhost2user" );
	foreach( @content ){
		my ($err, $monitoredhost, $userlist) = parse_2items_with_params $_;
		print "monitoredhost2user: $err\n" if $err;
		next unless defined $monitoredhost;
		my @user = split m",", $userlist;
		foreach my $user ( @user ){
			$monitoredhost2users{$monitoredhost}->{$user} = 1;
		}
	}
	$$this{monitoredhost2users} = \%monitoredhost2users;
}

sub loadMonitoredHostServiceGroups ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %monitoredhost2service2groups;

	my @content = $inputdir->read( "monitoredhost2service2group" );
	foreach( @content ){
		my ($err, $monitoredhost, $service, $grouplist) = parse_3items_with_params $_;
		print "monitoredhost2service2group: $err\n" if $err;
		next unless defined $monitoredhost;
		my @group = split m",", $grouplist;
		foreach my $group ( @group ){
			$monitoredhost2service2groups{$monitoredhost}->{$service}->{$group} = 1;
		}
	}
	$$this{monitoredhost2service2groups} = \%monitoredhost2service2groups;
}

sub loadMonitoredHostServiceUsers ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %monitoredhost2service2users;

	my @content = $inputdir->read( "monitoredhost2service2user" );
	foreach( @content ){
		my ($err, $monitoredhost, $service, $userlist) = parse_3items_with_params $_;
		print "monitoredhost2service2user: $err\n" if $err;
		next unless defined $monitoredhost;
		my @user = split m",", $userlist;
		foreach my $user ( @user ){
			$monitoredhost2service2users{$monitoredhost}->{$service}->{$user} = 1;
		}
	}
	$$this{monitoredhost2service2users} = \%monitoredhost2service2users;
}

sub loadPseudoHost2Service2BackendHost ($) {
	my ($this) = @_;
	my $inputdir =  $$this{inputdir};

	my %pseudohost2service2backendhosts;
	my %backendhost2pseudohost2services;

	my @content = $inputdir->read( "pseudohost2service2backendhost" );
	foreach( @content ){
		my ($err, $pseudohost, $service, $backendhost_list) = parse_3items_with_params $_;
		print "pseudohost2service2backendhost: $err\n" if $err;
		next unless defined $pseudohost;
		my @backendhost = split m",", $backendhost_list;
		foreach my $backendhost ( @backendhost ){
			$pseudohost2service2backendhosts{$pseudohost}->{$service}->{$backendhost} = 1;
			$backendhost2pseudohost2services{$backendhost}->{$pseudohost}->{$service} = 1;
		}
	}
	$$this{pseudohost2service2backendhosts} = \%pseudohost2service2backendhosts;
	$$this{backendhost2pseudohost2services} = \%backendhost2pseudohost2services;
}

sub calculatePseudoHosts ($) {
	my ($this) = @_;
	my $monitoredhost2service2measurement = $$this{monitoredhost2service2measurement};
	my $measurement2type = $$this{measurement2type};

	my %pseudohost;
	while( my ($host, $service2measurement) = each %$monitoredhost2service2measurement ){
		my $host_has_agent_measurement;
		my $host_has_agentless_or_indirect_measurement;
		while( my ($service, $measurement) = each %$service2measurement ){
			my $type = $$measurement2type{$measurement};
			if    ( $type eq "agent" ){
				$host_has_agent_measurement = 1;
			}elsif( $type eq "agentless" || $type eq "indirect" ){
				$host_has_agentless_or_indirect_measurement = 1;
			}
		}
		if    ( $host_has_agent_measurement and not $host_has_agentless_or_indirect_measurement ){
			# agent host
		}elsif( not $host_has_agent_measurement and $host_has_agentless_or_indirect_measurement ){
			$pseudohost{$host} = 1;
		}else{
			die "$host: cannot determine whether the host is pseudo or agent, stoped";
		}
	}
	$$this{pseudohost} = \%pseudohost;
}

####

sub listMasterTypes ($) {
	my ($this) = @_;
	my @r;
	my $mastertype = $$this{mastertype};
	foreach my $mastertypename ( sort keys %$mastertype ){
		push @r, {
			"mastertype"                   => $mastertypename,
		};
	}
	return @r;
}

sub listAgentTypes ($) {
	my ($this) = @_;
	my @r;
	my $agenttype = $$this{agenttype};
	my $agenttype2naemondirective = $$this{agenttype2naemondirective};
	my $agenttype2naemondirective_of_instance = $$this{agenttype2naemondirective_of_instance};
	foreach my $agenttypename ( sort keys %$agenttype ){
		my $naemondirective             = $$agenttype2naemondirective{$agenttypename};
		my $naemondirective_of_instance = $$agenttype2naemondirective_of_instance{$agenttypename};
		push @r, {
			"agenttype"                   => $agenttypename,
			"naemondirective"             => $naemondirective,
			"naemondirective_of_instance" => $naemondirective_of_instance,
		};
	}
	return @r;
}

sub listMasterHosts ($) {
	my ($this) = @_;
	my @r;
	my $masterhost = $$this{masterhost};
	my $masterhost2mastertype   = $$this{masterhost2type};
	my $masterhost2ansibleparam = $$this{masterhost2ansibleparam};
	foreach my $masterhostname ( sort keys %$masterhost ){
		my $mastertype   = $$masterhost2mastertype{$masterhostname};
		my $ansibleparam = $$masterhost2ansibleparam{$masterhostname};
		push @r, {
			"hostname"     => $masterhostname,
			"masterhost"   => $masterhostname,
			"mastertype"   => $mastertype,
			"ansibleparam" => $ansibleparam,
		};
	}
	return @r;
}

sub listAgentHosts ($) {
	my ($this) = @_;
	my @r;
	my $agenthost = $$this{agenthost};
	my $agenthost2agenttype = $$this{agenthost2agenttype};
	my $agenthost2ansibleparam = $$this{agenthost2ansibleparam};
	foreach my $agenthostname ( sort keys %$agenthost ){
		my $agenttype = $$agenthost2agenttype{$agenthostname};
		my $ansibleparam = $$agenthost2ansibleparam{$agenthostname};
		push @r, {
			"hostname"  => $agenthostname,
			"agenthost" => $agenthostname,
			"agenttype" => $agenttype,
			"ansibleparam" => $ansibleparam,
		};
	}
	return @r;
}

sub listPseudoHosts ($) {
	my ($this) = @_;
	my @r;
	my $pseudohost = $$this{pseudohost};
	foreach my $pseudohostname ( sort keys %$pseudohost ){
		push @r, {
			"hostname"   => $pseudohostname,
			"pseudohost" => $pseudohostname,
		};
	}
	return @r;
}

sub listMeasurements ($) {
	my ($this) = @_;
	my @r;
	my $measurement = $$this{measurement};
	my $measurement2type = $$this{measurement2type};
	my $measurement2naemondirective = $$this{measurement2naemondirective};
	my $measurement2naemondirective_of_instance = $$this{measurement2naemondirective_of_instance};
	foreach my $measurementname ( sort keys %$measurement ){
		my $type                        = $$measurement2type{$measurementname};
		my $naemondirective             = $$measurement2naemondirective{$measurementname};
		my $naemondirective_of_instance = $$measurement2naemondirective_of_instance{$measurementname};
		push @r, {
			"measurement"                 => $measurementname,
			"type"                        => $type,
			"naemondirective"             => $naemondirective,
			"naemondirective_of_instance" => $naemondirective_of_instance,
		};
	}
	return @r;
}

sub listMonitoredHostServices ($) {
	my ($this) = @_;
	my @r;
	my $monitoredhost2service2measurement = $$this{monitoredhost2service2measurement};
	my $measurement2naemondirective_of_instance = $$this{measurement2naemondirective_of_instance};
	my $agenthost2agenttype = $$this{agenthost2agenttype};
	my $measurement2type = $$this{measurement2type};
	my $pseudohost2service2backendhosts = $$this{pseudohost2service2backendhosts};
	foreach my $monitoredhostname ( sort keys %$monitoredhost2service2measurement ){
		my $service2measurement = $$monitoredhost2service2measurement{$monitoredhostname};
		my $agenttype = $$agenthost2agenttype{$monitoredhostname} // "pseudo";
		foreach my $servicename ( sort keys %$service2measurement ){
			my $measurement = $$service2measurement{$servicename};
			my $measurementtype = $$measurement2type{$measurement};
			my $naemondirective = $$measurement2naemondirective_of_instance{$measurement};
			my $backendhosts = $$pseudohost2service2backendhosts{$monitoredhostname}->{$servicename};
			push @r, {
				"host"        => $monitoredhostname,
				"agenttype"   => $agenttype,
				"service"     => $servicename,
				"measurement" => $measurement,
				"measurementtype" => $measurementtype,
				"naemondirective" => $naemondirective,
				"backendhosts" => $backendhosts,
			};
		}
	}
	return @r;
}

sub listPluginConfigFiles ($) {
	my ($this) = @_;
	my $type2plugin2pluginconfs = $$this{type2plugin2pluginconfs};
	my $type2pluginconf2format = $$this{type2pluginconf2format};
	my @r;
	foreach my $type ( sort keys %$type2plugin2pluginconfs ){
		my $plugin2pluginconfs = $$type2plugin2pluginconfs{$type};
		foreach my $plugin ( sort keys %$plugin2pluginconfs ){
			my $pluginconfs = $$plugin2pluginconfs{$plugin};
			foreach my $pluginconf ( sort keys %$pluginconfs ){
				my $format = $$type2pluginconf2format{$type}->{$pluginconf};
				push @r, {
					"type" => $type,
					"plugin" => $plugin,
					"pluginconf" => $pluginconf,
					"format" => $format,
				};
			}
		}
	}
	return @r;
}

sub listMonitoredHostGroups ($) {
	my ($this) = @_;
	my @r;
	my $monitoredhost2groups = $$this{monitoredhost2groups};
	foreach my $monitoredhost ( sort keys %$monitoredhost2groups ){
		my $groups = $$monitoredhost2groups{$monitoredhost};
		my @groups = sort keys %$groups;
		push @r, {
			"host"        => $monitoredhost,
			"groups"      => \@groups,
		};
	}
	return @r;
}

sub listMonitoredHostUsers ($) {
	my ($this) = @_;
	my @r;
	my $monitoredhost2users = $$this{monitoredhost2users};
	foreach my $monitoredhost ( sort keys %$monitoredhost2users ){
		my $users = $$monitoredhost2users{$monitoredhost};
		my @users = sort keys %$users;
		push @r, {
			"host"        => $monitoredhost,
			"users"      => \@users,
		};
	}
	return @r;
}

sub listMonitoredHostServiceGroups ($) {
	my ($this) = @_;
	my @r;
	my $monitoredhost2service2groups = $$this{monitoredhost2service2groups};
	foreach my $monitoredhost ( sort keys %$monitoredhost2service2groups ){
		my $service2groups = $$monitoredhost2service2groups{$monitoredhost};
		foreach my $service ( sort keys %$service2groups ){
			my $groups = $$service2groups{$service};
			my @groups = sort keys %$groups;
			push @r, {
				"host"        => $monitoredhost,
				"service"     => $service,
				"groups"      => \@groups,
			};
		}
	}
	return @r;
}

sub listMonitoredHostServiceUsers ($) {
	my ($this) = @_;
	my @r;
	my $monitoredhost2service2users = $$this{monitoredhost2service2users};
	foreach my $monitoredhost ( sort keys %$monitoredhost2service2users ){
		my $service2users = $$monitoredhost2service2users{$monitoredhost};
		foreach my $service ( sort keys %$service2users ){
			my $users = $$service2users{$service};
			my @users = sort keys %$users;
			push @r, {
				"host"        => $monitoredhost,
				"service"     => $service,
				"users"       => \@users,
			};
		}
	}
	return @r;
}

sub listPseudoHostServiceBackendHosts ($) {
	my ($this) = @_;
	my @r;
	my $pseudohost2service2backendhosts = $$this{pseudohost2service2backendhosts};
	foreach my $pseudohost ( sort keys %$pseudohost2service2backendhosts ){
		my $service2backendhosts = $$pseudohost2service2backendhosts{$pseudohost};
		foreach my $service ( sort keys %$service2backendhosts ){
			my $backendhosts = $$service2backendhosts{$service};
			my @backendhosts = sort keys %$backendhosts;
			push @r, {
				"host"         => $pseudohost,
				"service"      => $service,
				"backendhosts" => \@backendhosts,
			};
		}
	}
	return @r;
}

sub listReporters ($) {
	my ($this) = @_;
	my $reporters = $$this{reporters};
	return sort keys %$reporters;
}

sub listGroups ($) {
	my ($this) = @_;
	my $groups = $$this{groups};
	my @r;
	foreach my $groupname ( sort keys %$groups ){
		my $profile = $$groups{$groupname};
		push @r, {
			"name" => $groupname,
			"profile" => $profile,
		};
	}
	return @r;
}

sub listUsers ($) {
	my ($this) = @_;
	my $users = $$this{users};
	my @r;
	foreach my $username ( sort keys %$users ){
		my $profile = $$users{$username};
		push @r, {
			"name" => $username,
			"profile" => $profile,
		};
	}
	return @r;
}


####

1;

