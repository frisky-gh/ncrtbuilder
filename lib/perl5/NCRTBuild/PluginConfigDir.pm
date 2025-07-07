#!/usr/bin/perl

package NCRTBuild::PluginConfigDir;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'confdir'	=> undef,
	};
}

####

sub setPath ($$) {
	my ($this, $confdir) = @_;
	$$this{confdir} = $confdir;
}

sub load ($) {
	my ($this) = @_;
}

####
sub read ($$) {
	my ($this, $file) = @_;
	my $confdir =  $$this{confdir};

	my @content;
	my $f = "$confdir/$file";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		push @content, $_;
	}
	close $f;
	return @content;
}

sub write ($$@) {
	my ($this, $file, @content) = @_;
	my $confdir =  $$this{confdir};

	my $f = "$confdir/$file";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	foreach( @content ){
		print $h $_, "\n";
	}
	close $h;
}

####

1;

