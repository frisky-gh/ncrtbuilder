#!/usr/bin/perl

package NCRTBuild::PluginConfigDistributor::HostServiceForAgent;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'workdir'	=> undef,
		'generators'	=> [],
		'host_service_list'	=> undef,
	};
}

####

sub setOutputDir ($$) {
	my ($this, $workdir) = @_;
       	$$this{workdir} = $workdir;
}

sub setMonitoredHostServices($@) {
	my ($this, @host_service) = @_;
       	$$this{host_service_list} = \@host_service;
}

sub addGenerator ($$$$$) {
	my ($this, $plugintype, $pluginname, $filename, $generator) = @_;
       	my $generators = $$this{generators};
       	push @$generators, {
		'plugintype' => $plugintype,
		'pluginname' => $pluginname,
		'filename'   => $filename,
		'generator'  => $generator,
	};
}

sub run ($) {
	my ($this) = @_;
       	my $workdir = $$this{workdir};
       	my $host_service_list = $$this{host_service_list};
       	my $generator_list = $$this{generators};
	foreach my $e ( @$host_service_list ){
		my $host            = $$e{host};
		my $service         = $$e{service};
		my $agenttype       = $$e{agenttype};
		my $measurement     = $$e{measurement};
		my $measurementtype = $$e{measurementtype};
		my $backendhosts    = $$e{backendhosts};
		next if $agenttype eq "pseudo";
		foreach my $g ( @$generator_list ){
			my $plugintype = $$g{plugintype};
			my $pluginname = $$g{pluginname};
			my $filename   = $$g{filename};
			my $generator  = $$g{generator};
			next unless $plugintype eq $measurementtype && $pluginname eq $measurement;
			my @content  = $generator->generate( $host, $service );
			$workdir->write( $host, $measurementtype, "$filename.$host.$service", @content );
		}
	}
}


####

1;

