#!/usr/bin/perl

package NCRTBuild::DistributedNaemonDefinitionDir;

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
		mkdir_or_die "$workdir/$host/naemondef";
	}
}

####

sub writeToAllHosts ($$@) {
	my ($this, $file, @content) = @_;
	my $workdir =  $$this{workdir};
	my $hosts   = $$this{hosts};

	foreach my $e ( @$hosts ){
		my $host = $$e{agenthost} // $$e{masterhost};
		my $f = "$workdir/$host/naemondef/$file";
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


