package NCRTBuild::Generic::FilterRuleDistributor;

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
		'hosts'  => undef,
	};
}

####

sub setGenerator ($$$) {
	my ($this, $category, $filename, $generator) = @_;
	$$this{category}  = $category;
	$$this{filename}  = $filename;
	$$this{generator} = $generator;
}

sub setMonitoredHostServices ($@) {
	my ($this, @host_service) = @_;
	$$this{host_service} = \@host_service;
}

sub setOutputDir ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub run ($) {
	my ($this) = @_;
	my $workdir   = $$this{workdir};
	my $filename  = $$this{filename};
	my $category  = $$this{category};
	my $generator = $$this{generator};
	my $host_service = $$this{host_service};

	foreach my $entry ( @$host_service ){
		my $host = $$entry{host};
		my $service = $$entry{service};
		my $measure = $$entry{measurement};
		my $naemondirective = $$entry{naemondirective};

		my $filter = $generator->generate( $host, $service );
		next if $filter eq "";
		$workdir->writeToAllHosts( $category, "$filename.$host.$service", $filter );
	}
}

####

1;

