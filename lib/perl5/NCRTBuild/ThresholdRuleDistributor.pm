#
package NCRTBuild::ThresholdRuleDistributor;

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

sub setGenerator ($$) {
	my ($this, $generator) = @_;
	$$this{generator} = $generator;
}

sub setMonitoredHostServices ($@) {
	my ($this, @host_service) = @_;
	$$this{host_service} = \@host_service;
}

sub setMasterHosts ($@) {
	my ($this, @masterhosts) = @_;
	$$this{masterhosts} = \@masterhosts;
}

sub setOutputDir ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub run ($) {
	my ($this) = @_;
	my $workdir = $$this{workdir};
	my $generator = $$this{generator};
	my $host_service = $$this{host_service};
	my $masterhosts = $$this{masterhosts};

	foreach my $entry ( @$host_service ){
		my $host = $$entry{host};
		my $service = $$entry{service};
		my $measure = $$entry{measurement};
		my $naemondirective = $$entry{naemondirective};

		my @content = $generator->generate( $host, $service );
		my @c;
		foreach my $c ( @content ){
			my $namepattern = $$c{namepattern};
			my $severity    = $$c{severity};
			my $upper       = $$c{upper};
			my $lower       = $$c{lower};
			push @content, "$namepattern $severity [$upper,$lower]";
		}
		$workdir->writeToAllHosts( "threshold", "thresholds.$host.$service", @c );
	}
}

1;

