#
package NCRTBuild::BackendHostServiceDistributor;

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
	};
}

####

sub setOutputDir ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

#sub setGenerator ($$) {
#	my ($this, $generator) = @_;
#	$$this{generator} = $generator;
#}

sub setMonitoredHostServices ($@) {
	my ($this, @host_service) = @_;
	$$this{host_service} = \@host_service;
}

sub run ($) {
	my ($this) = @_;
	my $workdir = $$this{workdir};
	my $generator = $$this{generator};
	my $host_service = $$this{host_service};

	foreach( @$host_service ){
		my $host = $$_{host};
		my $service = $$_{service};
		my $measurement = $$_{measurement};
		my $measurementtype = $$_{measurementtype};
		my $agenttype       = $$_{agenttype};
		my $backendhosts    = $$_{backendhosts};
		next unless $agenttype       eq "pseudo";
		next unless $measurementtype eq "indirect";

		my @content = sort keys %$backendhosts;
		$workdir->writeToAllHosts( "backend", "backend.$measurement.$host.$service", @content );
	}
}

####

1;

