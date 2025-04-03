#!/usr/bin/perl

package NCRTBuild::DistributedPluginConfigDir;

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
		mkdir_or_die "$workdir/$host/pluginsconf";
		foreach my $i ( "agent", "agentless", "indirect", "reporter" ){
			mkdir_or_die "$workdir/$host/pluginsconf/$i";
		}
	}
}

####

sub write ($$$$@) {
	my ($this, $host, $plugintype, $file, @content) = @_;
	my $workdir =  $$this{workdir};
	my $hosts   = $$this{hosts};

	my $f = "$workdir/$host/pluginsconf/$plugintype/$file";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach( @content ){
		print $h $_, "\n";
	}
	close $h;
}

sub writeToAllHosts ($$$@) {
	my ($this, $plugintype, $file, @content) = @_;
	my $workdir =  $$this{workdir};
	my $hosts   = $$this{hosts};

	foreach my $e ( @$hosts ){
		my $host = $$e{agenthost} // $$e{masterhost};
		my $f = "$workdir/$host/pluginsconf/$plugintype/$file";
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


