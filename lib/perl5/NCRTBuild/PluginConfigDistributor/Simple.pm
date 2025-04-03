#!/usr/bin/perl

package NCRTBuild::PluginConfigDistributor::Simple;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'workdir4agents'	=> undef,
		'workdir4masters'	=> undef,
		'agenthosts'		=> undef,
		'masterhosts'		=> undef,
		'generators'		=> [],

		'plugin2type2conffile2format' => undef,
	};
}

####

sub setOutputDir ($$) {
	my ($this, $workdir) = @_;
       	$$this{workdir} = $workdir;
}

sub setMonitoredHostServices($@) {
	my ($this, @host_service) = @_;
	# do nothing
}

sub setHosts ($@) {
	my ($this, @hosts) = @_;
       	$$this{hosts} = \@hosts;
}

sub addGenerator ($@) {
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
       	my $generators = $$this{generators};

	foreach my $i ( @$generators ){
		my $plugintype = $$i{plugintype};
		my $pluginname = $$i{pluginname};
		my $filename   = $$i{filename};
		my $generator  = $$i{generator};
		my @content = $generator->generate( undef, undef );
		$workdir->writeToAllHosts( $plugintype, $filename, @content );
	}
}

####

1;

