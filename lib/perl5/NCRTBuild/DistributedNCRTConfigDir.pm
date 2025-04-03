#!/usr/bin/perl

package NCRTBuild::DistributedNCRTConfigDir;

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
		'hosts'		=> undef,
		'category'	=> undef,
	};
}

####

sub setBasePath ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub setHosts ($@) {
	my ($this, @hosts) = @_;
	$$this{hosts} = \@hosts;
}

sub create ($) {
	my ($this) = @_;
	my $workdir = $$this{workdir};
	my $hosts   = $$this{hosts};
	mkdir_or_die $workdir;
	foreach my $e ( @$hosts ){
		my $host = $$e{agenthost} // $$e{masterhost};
		mkdir_or_die "$workdir/$host";
		mkdir_or_die "$workdir/$host/ncrtconf";
		foreach my $category ( "backend", "threshold", "thresholdfilter", "metricfilter" ){
			mkdir_or_die "$workdir/$host/ncrtconf/$category";
		}
	}
}

####

sub writeToAllHosts ($$$@) {
	my ($this, $category, $file, @content) = @_;
	my $workdir =  $$this{workdir};
	my $hosts   = $$this{hosts};

	foreach my $e ( @$hosts ){
		my $host = $$e{agenthost} // $$e{masterhost};
		my $f = "$workdir/$host/ncrtconf/$category/$file";
		open my $h, '>', $f or do {
			die "$f: cannot open, stopped";
		};
		foreach( @content ){
			print $h $_, "\n";
		}
		close $h;
	}
}

####

1;


