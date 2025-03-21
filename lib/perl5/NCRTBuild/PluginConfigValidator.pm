#!/usr/bin/perl

package NCRTBuild::PluginConfigValidator;

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

		'plugin2type2conffile2format' => undef,
	};
}

####

sub load ($$$) {
	my ($this, $conf, $workdir) = @_;
	$$this{conf}    = $conf;
	$$this{workdir} = $workdir;

	my %plugin2type2conffile2format = $workdir->loadPlugin2Type2ConfFile2Format;

	$$this{plugin2type2conffile2format} = \%plugin2type2conffile2format;
}

####

sub loadPluginConfigOf ($$$$) {
	my ($this, $type, $plugin, $target_format) = @_;
	my $conf = $$this{conf};
	my $host_service = $$this{host_service};
	my $plugin2type2conffile2format = $$this{plugin2type2conffile2format};

	my $conffile2format = $$plugin2type2conffile2format{$plugin}->{$type};
	return () unless defined $conffile2format;

	my %r;
	while( my ($conffile, $format) = each %$conffile2format ){
		next unless $format eq $target_format;

		my @content = $conf->loadPluginConfig( $type, $plugin, $conffile );
		$r{$conffile} = \@content;
	}
	
	return %r;
}


####

sub listNaemonDefinition ($) {
	my ($this) = @_;
	my $host_service = $$this{host_service};

	return @{ $host_service };
}


1;

