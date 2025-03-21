#!/usr/bin/perl

package NCRTBuild::MeasurementNaemonDirectiveValidator;

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

		'agenttype2hosttemplatedirective'	=> undef,
		'agenttype2hostdirective'		=> undef,
		'measurement2servicetemplatedirective'	=> undef,
		'measurement2servicedirective'		=> undef,
		'host2service2directive'		=> undef,
		'host2service2overridedirective'	=> undef,
	};
}

####

sub _generate_from_rules ($$$) {
	my ($host, $service, @rules) = @_;
	die;
}

sub load ($$$) {
	my ($this, $conf, $workdir) = @_;
	$$this{conf}    = $conf;
	$$this{workdir} = $workdir;

	my %agenttype2directive        = $workdir->loadAgentTypes;
	my %agenttype2hosttemplatedirective;
	my %agenttype2hostdirective;
	while( my ($agenttype, $directive) = each %agenttype2directive ){
		while( my ($key, $value) = each %$directive ){
			if( $key =~ m"^@(.+)$" ){
				$agenttype2hosttemplatedirective{$agenttype}->{$1}   = $value;
			}else{
				$agenttype2hostdirective        {$agenttype}->{$key} = $value;
			}
		}
	}

	my %measurement2type2directive = $workdir->loadMeasures;
	my %measurement2type;
	my %measurement2servicetemplatedirective;
	my %measurement2servicedirective;
	while( my ($measurement, $type2directive) = each %measurement2type2directive ){
		my @type = keys %$type2directive;
		die unless @type == 1;
		$measurement2type{$measurement} = $type[0];
		my $directive = $$type2directive{ $type[0] };

		while( my ($key, $value) = each %$directive ){
			if( $key =~ m"^@(.+)$" ){
				$measurement2servicetemplatedirective{$measurement}->{$1}   = $value;
			}else{
				$measurement2servicedirective        {$measurement}->{$key} = $value;
			}
		}
	}

	my %host2service2info = $workdir->loadHost2Service2Measure;
	my %host2service2directive;
	while( my ($host, $service2info) = each %host2service2info ){
		while( my ($service, $info) = each %$service2info ){
			$host2service2directive{$host}->{$service} = $$info{directive};
		}
	}

	my @rules = $conf->loadNaemonDefRules;
	my %host2service2overridedirective;
	while( my ($host, $service2info) = each %host2service2info ){
		while( my ($service, $info) = each %$service2info ){
			$host2service2directive{$host}->{$service} = _generate_from_rule $host, $service, @rules;
		}
	}

	$$this{agenttype2hosttemplatedirective} 	= \%agenttype2hosttemplatedirective;
	$$this{agenttype2hostdirective} 		= \%agenttype2hostdirective;
	$$this{measurement2servicetemplatedirective}	= \%measurement2servicetemplatedirective;
	$$this{measurement2servicedirective}		= \%measurement2servicedirective;
	$$this{host2service2directive}			= \%host2service2directive;
	$$this{host2service2overridedirective}		= \%host2service2overridedirective;
}

####

sub listAgentTypeTemplate ($) {
	my ($this) = @_;
	my $host_service = $$this{host_service};

	return @{ $host_service };
}

sub listHostServiceUsingBackend ($$) {
	my ($this, $backend) = @_;
	my $host_service = $$this{host_service};

	my @r;
	foreach my $entry ( @{$host_service} ){
		push @r, $entry if $$entry{measurement} eq $backend;
	}
	
	return @r;
}

1;

