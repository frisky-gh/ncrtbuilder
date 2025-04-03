#!/usr/bin/perl

package NCRTBuild::NCRTConfigDir;

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

		'param' => {
			'ANSIBLEOPTIONS'	=> undef,
			'NCRTAGENTHOME' 	=> undef,
			'NCRTMASTERHOME'	=> undef,
			'HELPERURL' =>
				'http://example.com/grafana-dashboard-helper',
			'HELPERURL_JUMP_TO_DASHBOARD' =>
				'http://example.com/grafana-dashboard-helper/jump_to_dashboard.html?dashboard=<hostname>,<servicedesc>',
			'HELPERURL_SEARCH_PANELS' =>
				 'http://example.com/grafana-dashboard-helper/search_panels.json?retention_policy=one_year&measurement=<hostname>,<servicedesc>&field_key=<performancename>',
		},
	};
}

#### load template conf.

sub setPath ($$) {
	my ($this, $confdir) = @_;
	$$this{confdir} = $confdir;
}

sub load ($) {
	my ($this) = @_;
	$this->loadConfig;
}

sub loadConfig ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};

	my $param = $$this{param};
	my $f = "$confdir/ncrtbuild.conf";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		m"^(\w+)=(.*)$" or die "$f:$.: illegal format, stopped";
		$$param{$1} = $2;
	}
	close $h;
}

####

sub getANSIBLEOPTIONS ($) {
	my ($this) = @_;
	return $$this{param}->{ANSIBLEOPTIONS};
}

sub getNCRTAGENTHOME ($) {
	my ($this) = @_;
	return $$this{param}->{NCRTAGENTHOME};
}

sub getNCRTMASTERHOME ($) {
	my ($this) = @_;
	return $$this{param}->{NCRTMASTERHOME};
}

sub getHELPERURL ($) {
	my ($this) = @_;
	return $$this{param}->{HELPERURL};
}

sub getHELPERURL_JUMP_TO_DASHBOARD ($) {
	my ($this) = @_;
	return $$this{param}->{HELPERURL_JUMP_TO_DASHBOARD};
}

sub getHELPERURL_SEARCH_PANELS ($) {
	my ($this) = @_;
	return $$this{param}->{HELPERURL_SEARCH_PANELS};
}


####

sub loadNaemonDirectiveRules ($) {
	my ($this) = @_;
	return $this->load_dir( "naemondirective", ".directiverules" );
}

sub loadMetricFilterRules ($) {
	my ($this) = @_;
	return $this->load_dir( "metricfilter", ".filterrules" );
}

sub loadThresholdFilterRules ($) {
	my ($this) = @_;
	return $this->load_dir( "thresholdfilter", ".filterrules" );
}

sub loadThresholdRules ($) {
	my ($this) = @_;
	return $this->load_dir( "threshold", ".thresholds" );
}

sub load_dir ($$$) {
	my ($this, $dir, $ext) = @_;
	my $confdir = $$this{confdir};

	my @r;
	my $d = "$confdir/$dir";
	opendir my $h, $d or die "$d: cannot open, stopped";
	foreach my $e ( sort readdir $h ){
		next unless $e =~ m"^\w.*(\.\w+)$";
		next unless $1 eq $ext;

		my $f = "$d/$e";
		open my $i, "<", $f or do {
			die "$f: cannot open, stopped";
		};
		while( <$i> ){
			chomp;
			push @r, $_;
		}
		close $i;
	}
	return @r;
}


1;

