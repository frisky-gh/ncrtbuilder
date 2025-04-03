#!/usr/bin/perl

package NCRTBuild::ContactValidator;

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

		'host_service'  => [],
	};
}

####

sub load ($$$) {
	my ($this, $conf, $workdir) = @_;
	$$this{conf}    = $conf;
	$$this{workdir} = $workdir;

	my @agenthost = $workdir->loadHosts;


	my @host_service;
	my %host2service2info = $workdir->loadHost2Service2Measure;

	foreach my $host ( sort keys %host2service2info ){
		my $service2info = $host2service2info{$host};
		foreach my $service ( sort keys %$service2info ){
			my $info = $$service2info{$service};
			$$info{host}    = $host;
			$$info{service} = $service;
			push @host_service, $info;
		}
	}

	$$this{host_service} = \@host_service;
}

####

sub listHostService ($) {
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

