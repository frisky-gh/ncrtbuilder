#!/usr/bin/perl

package NCRTBuild::WorkDirectory;

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

sub create ($$) {
	my ($this, $workdir) = @_;

	#### initialize fixed work dirs and files
	rm_r $workdir if -d $workdir;
	mkdir_or_die $workdir;
	mkdir_or_die "$workdir/ncrtagent";
	mkdir_or_die "$workdir/ncrtmaster";

	# agenttype list
	create_or_die "$workdir/agenttypes";

	# mastertype list
	create_or_die "$workdir/mastertypes";

	# measure list
	create_or_die "$workdir/measures";

	# hostname -> agenttype mappings
	create_or_die "$workdir/agenthosts";

	# hostname -> mastertype mappings
	create_or_die "$workdir/masterhosts";

	# agenttype -> configuration file multi-mappings
	create_or_die "$workdir/agenttype2conf";

	# mastertype -> configuration file multi-mappings
	create_or_die "$workdir/mastertype2conf";

	# measure -> configuration file multi-mappings
	create_or_die "$workdir/measure2conf";

	# hostname -> service multi-mapping
	create_or_die "$workdir/agenthost2service2measure";

	# hostname -> contact multi-mapping
	create_or_die "$workdir/agenthost2contact";

	# hostname -> service -> contact multi-mapping
	create_or_die "$workdir/agenthost2service2contact";

	# hostname -> groupname multi-mapping
	create_or_die "$workdir/agenthost2group";

	# hostname -> service -> groupname multi-mapping
	create_or_die "$workdir/agenthost2service2group";

	# username list
	create_or_die "$workdir/users";

	# email address list
	create_or_die "$workdir/addresses";

}

sub load ($) {
	my ($this) = @_;
	$this->loadAgentHosts;
}


#### read agent type related work files
sub loadAgentHosts ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %host2agenttype;
	my %agenttype2agenthosts;
	my $agenttype_has_collision;
	my @ncrtagents;

	my $f = "$workdir/agenthosts";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		my ($host, $agenttype) = split m"\s+";
		if( not defined $host2agenttype{$host} ){
			$host2agenttype{$host} = $agenttype;
			push @{$agenttype2agenthosts{$agenttype}}, $host;
		}elsif( $host2agenttype{$host} ne $agenttype ){
			print "ERROR: host $host has multiple agenttypes.\n";
			$agenttype_has_collision = 1;
		}
	}
	close $h;
	while( my ($h, $t) = each %host2agenttype ){
		push @ncrtagents, $h;
	}

	die "Some agenttype have collisions, stopped" if $agenttype_has_collision;
}

sub loadAgentTypes ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %agenttype2opts = (
		'virtual' => {
			'display_name' => 'Virtual:<hostname>',
			'address' => '127.0.0.1',
			'check_command' => 'ncrtmaster_do_nothing',
		},
	);
	my %agenttype2templateopts = (
		'virtual' => {},
	);

	my $f = "$workdir/agenttypes";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($agenttype, $opts, $templateopts) = parse_itementry $_;
		print "$f:$.:$opts\n" if !defined $agenttype && defined $opts;
		next unless $agenttype;
		$agenttype2opts{$agenttype} = $opts;
		$agenttype2templateopts{$agenttype} = $templateopts;
	}
	close $h;
}

#### read master type related work files
sub loadMasterHosts ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %host2mastertype;
	my %mastertype2masterhosts;
	my $mastertype_has_collision;
	my @ncrtmasters;
	my @ncrtmasteraddrs;

	my $f = "$workdir/masterhosts";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		my ($host, $mastertype) = split m"\s+";
		if( not defined $host2mastertype{$host} ){
			$host2mastertype{$host} = $mastertype;
			push @{$mastertype2masterhosts{$mastertype}}, $host;
		}elsif( $host2mastertype{$host} ne $mastertype ){
			print "ERROR: host $host has multiple mastertypes.\n";
			$mastertype_has_collision = 1;
		}
	}
	close $h;

	while( my ($h, $t) = each %host2mastertype ){
		push @ncrtmasters, $h;
		my ( $name, $aliases, $addrtype, $length, @addrs ) = gethostbyname $_;
		foreach my $addr ( @addrs ){
			my $a = inet_ntoa $addr;
			push @ncrtmasteraddrs, $a;
		}
	}
	die "Some mastertype have collisions, stopped" if $mastertype_has_collision;
}

sub loadMasterTypes ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %mastertype2opts         = ();
	my %mastertype2templateopts = ();

	my $f = "$workdir/mastertypes";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($mastertype, $opts, $templateopts) = parse_itementry $_;
		print "$f:$.:$opts\n" if !defined $mastertype && defined $opts;
		next unless $mastertype;
		$mastertype2opts{$mastertype} = $opts;
		$mastertype2templateopts{$mastertype} = $templateopts;
	}
	close $h;
}

#### read measurement / service / host related work files
sub loadMeasures ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %measure2measuretype;
	my %measure2opts;
	my %measure2templateopts;
	my $f = "$workdir/measures";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($measure, $measuretype, $opts, $templateopts) = parse_mapping $_;
		print "$f:$.:$opts\n" if !defined $measure && defined $opts;
		next unless $measure;
		$measure2measuretype{$measure} = $measuretype;
		$measure2opts{$measure} = $opts;
		$measure2templateopts{$measure} = $templateopts;
	}
	close $h;

}

sub loadAgentHost2Service2Measure ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %host2service2info;
	my $f = "$workdir/agenthost2service2measure";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($host, $service, $measurement, $naemondefs) = parse_3items_with_params $_;
		print "$f:$.:$naemondefs\n" if !defined $host && defined $naemondefs;
		next unless $host;
		$host2service2info{$host}->{$service} = {
			'measurement' => $measurement,
			'naemondefs'  => $naemondefs,
		};
	}
	close $h;

	return %host2service2info;
}

sub loadHost2Contact ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %host2contact;
	my $f = "$workdir/agenthost2contact";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($host, $contact, $opts) = parse_host2item_mapping $_;
		print "$f:$.:$opts\n" if !defined $host && defined $opts;
		next unless $host;
		push @{$host2contact{$host}}, $contact;
	}
	close $h;
}

sub loadAgentHost2Service2Contact ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %host2service2contact;
	my $f = "$workdir/agenthost2service2contact";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($host, $service, $contact, $opts) = parse_host2service2item_mapping $_;
		print "$f:$.:$opts\n" if !defined $host && defined $opts;
		next unless $host;
		push @{$host2service2contact{$host}->{$service}}, $contact;
	}
	close $h;
}

sub loadHost2Group ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %group2host;
	my $f = "$workdir/host2group";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($host, $group, $opts) = parse_host2item_mapping $_;
		print "$f:$.:$opts\n" if !defined $host && defined $opts;
		next unless $host;
		push @{$group2host{$group}}, $host;
	}
	close $h;
}

sub loadAgentHost2Service2Group ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %group2host2service;
	my $f = "$workdir/agenthost2service2group";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($host, $service, $group, $opts) = parse_host2service2item_mapping $_;
		print "$f:$.:$opts\n" if !defined $host && defined $opts;
		next unless $host;
		$group2host2service{$group}->{$host}->{$service} = 1;
	}
	close $h;
}

sub loadUsers ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %users = ( nobody => "" );
	my $f = "$workdir/users";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($user, $opts) = parse_itementry $_;
		print "$f:$.:$opts\n" if !defined $user && defined $opts;
		next unless $user;
		$users{$user} = $opts;
	}
	close $h;
}

sub loadAddresses ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %addresses;
	my $f = "$workdir/addresses";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		my ($address, $opts) = parse_addressentry $_;
		print "$f:$.:$opts\n" if !defined $address && defined $opts;
		next unless $address;
		$addresses{$address} = $opts;
	}
	close $h;
}

sub loadAgentType2Conf ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	####
	my %agenttype2conf;
	my $f = "$workdir/agenttype2conf";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		my ($agenttype, $conf) = split m"\s+";
		push @{$agenttype2conf{$agenttype}}, $conf;
	}
	close $h;
}

sub loadMasterType2Conf ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %mastertype2conf;
	my $f = "$workdir/mastertype2conf";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		my ($mastertype, $conf) = split m"\s+";
		push @{$mastertype2conf{$mastertype}}, $conf;
	}
	close $h;
}

sub loadPlugin2Type2ConfFile2Format ($) {
	my ($this) = @_;
	my $workdir =  $$this{workdir};

	my %plugin2type2conffile2format;
	my $f = "$workdir/plugin2type2conffile2format";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		my ($plugin, $type, $conffile, $format) = split m"\s+";
		$plugin2type2conffile2format{$plugin}->{$type}->{$conffile} = $format;
	}
	close $h;

	return %plugin2type2conffile2format;
}


1;

