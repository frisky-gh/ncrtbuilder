#!/usr/bin/perl

package NCRTBuild::PluginWorkDir;

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
	};
}

####

sub setPath ($$) {
	my ($this, $workdir) = @_;
	$$this{workdir} = $workdir;
}

sub create ($) {
	my ($this) = @_;
	my $workdir = $$this{workdir};

	#### initialize fixed work dirs and files
	rm_r $workdir if -d $workdir;
	mkdir_or_die $workdir;

	# agenttype list
	create_or_die "$workdir/agenttypes";

	# mastertype list
	create_or_die "$workdir/mastertypes";

	# measure list
	create_or_die "$workdir/measurements";

	# hostname -> agenttype mappings
	create_or_die "$workdir/agenthosts";

	# hostname -> mastertype mappings
	create_or_die "$workdir/masterhosts";

	# plugin -> configuration file multi-mappings
	create_or_die "$workdir/plugin2type2pluginconf2format";

	# hostname -> service multi-mapping
	create_or_die "$workdir/monitoredhost2service2measurement";

	# hostname -> contact multi-mapping
	create_or_die "$workdir/monitoredhost2user";

	# hostname -> service -> contact multi-mapping
	create_or_die "$workdir/monitoredhost2service2user";

	# hostname -> groupname multi-mapping
	create_or_die "$workdir/monitoredhost2group";

	# hostname -> service -> groupname multi-mapping
	create_or_die "$workdir/monitoredhost2service2group";

	# groupname list
	create_or_die "$workdir/groups";

	# username list
	create_or_die "$workdir/users";

	# reporter list
	create_or_die "$workdir/reporters";

	# pseudo host, service -> backend host (agent host) for indirect measurement
	create_or_die "$workdir/pseudohost2service2backendhost";
}


####
sub read ($$) {
	my ($this, $file) = @_;
	my $workdir =  $$this{workdir};

	my @content;
	my $f = "$workdir/$file";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		push @content, $_;
	}
	close $f;
	return @content;
}

sub write ($$@) {
	my ($this, $file, @content) = @_;
	my $workdir =  $$this{workdir};

	my $f = "$workdir/$file";
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

