#!/usr/bin/perl

package NCRTBuild::PluginConfigValidator;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($) {
	my ($class) = @_;
	return bless {
		'confdir'	=> undef,
		'validator'	=> undef,

		'pluginconffiles' => undef,
	};
}

####

sub setPluginWorkFileValidator ($$) {
	my ($this, $validator) = @_;
	$$this{validator} = $validator;
}

sub setInputDir ($$) {
	my ($this, $confdir) = @_;
	$$this{confdir} = $confdir;
}

sub load ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $validator = $$this{validator};

	my @pluginconffiles = $validator->listPluginConfigFiles;

	$$this{pluginconffiles} = \@pluginconffiles;
}

####

sub loadPluginConfigFileOf ($$$) {
	my ($this, $target_type, $target_plugin) = @_;
	my $confdir = $$this{confdir};
	my $host_service = $$this{host_service};
	my $pluginconffiles = $$this{pluginconffiles};

	my @r;
	foreach( @$pluginconffiles ){
		my $plugin     = $$_{plugin};
		my $type       = $$_{type};
		my $pluginconf = $$_{pluginconf};
		my $format     = $$_{format};
		next unless $plugin eq $target_plugin;
		next unless $type   eq $target_type;
		my @content = $confdir->read( "$type/$pluginconf" );
		push @r, {
			"pluginconf"    => $pluginconf,
			"format"  => $format,
			"content" => \@content,
		};
	}
	
	return @r;
}


####

1;

