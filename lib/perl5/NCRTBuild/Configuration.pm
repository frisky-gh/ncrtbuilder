#!/usr/bin/perl

package NCRTBuild::Configuration;

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
		'pluginsdir'	=> undef,

		'naemon2influx_deb'		=> undef,
		'grafana_dashboard_helper_deb'	=> undef,

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
		'agenttype_plugins'	=> [],
		'agenttypes'		=> [],
		'mastertype_plugins'	=> [],
		'mastertypes'		=> [],
		'agent_plugins' 	=> [],
		'agentless_plugins'	=> [],
		'indirect_plugins'	=> [],
		'contact_plugins'	=> [],
		'reporter_plugins'	=> [],
	};
}

#### load template conf.

sub load ($$$) {
	my ($this, $confdir, $pluginsdir) = @_;
	$$this{confdir} = $confdir;
	$$this{pluginsdir} = $pluginsdir;
	$this->load_conf;
	$this->load_plugins;
	$this->load_packages;
}

sub load_conf ($) {
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

sub load_plugins ($) {
	my ($this) = @_;
	my $pluginsdir = $$this{cpluginsdir};
	opendir my $d, $pluginsdir or do {
		die "$pluginsdir: cannot open, stopped";
	};
	while( my $e = readdir $d ){
		next unless $e =~ m"^ncrtbuild_(?:(agent)|(agentless)|(indirect)|(agenttype)|(mastertype)|(contact)|(reporter))_([-\w]+)$";
		push @{ $$this{agent_plugins} },      $e if $1;
		push @{ $$this{agentless_plugins} },  $e if $2;
		push @{ $$this{indirect_plugins} },   $e if $3;
		push @{ $$this{agenttype_plugins} },  $e if $4;
		push @{ $$this{agenttypes} },	 $8 if $4;
		push @{ $$this{mastertype_plugins} }, $e if $5;
		push @{ $$this{mastertypes} },	$8 if $5;
		push @{ $$this{contact_plugins} },    $e if $6;
		push @{ $$this{reporter_plugins} },   $e if $7;
	}
	closedir $d;
}

sub load_packages ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};

	opendir my $h, $confdir or do {
		die "$confdir: cannot open, stopped";
	};
	foreach my $e ( sort readdir $h ){
		if( $e =~ m"^naemon2influx-\d.*\.deb$" ){
			$$this{naemon2influx_deb} = $e;
		}
		if( $e =~ m"^grafana-dashboard-helper_.*\.deb$" ){
			$$this{grafana_dashboard_helper_deb} = $e;
		}
	}
	closedir $h;
}

sub build ($$) {
	my ($this, $srcdir) = @_;
	my $confdir = $$this{confdir};
	my $srcdir = "$confdir/../src";
	my $param = $$this{param};

	#### build naemon2influx package
	unless( defined $$this{naemon2influx_deb} ){
		unless( -d "$srcdir/naemon2influx" ){
			system_or_die "git clone --depth=1 https://github.com/frisky-gh/naemon2influx.git $srcdir/naemon2influx";
		}
		system_or_die "make deb -C $srcdir/naemon2influx";
		system_or_die "cp $srcdir/naemon2influx/*.deb $confdir";
		$this->load_packages;
		die "naemon2influx: cannot build package, stopped"
			unless defined $$this{naemon2influx_deb};
	}

	#### build grafana-dashboard-helper package
	unless( defined $$this{grafana_dashboard_helper_deb} ){
		unless( -d "$srcdir/grafana-dashboard-helper" ){
			system_or_die "git clone --depth=1 https://github.com/frisky-gh/grafana-dashboard-helper.git $srcdir/grafana-dashboard-helper";
		}
		system_or_die "cd $srcdir/grafana-dashboard-helper && dpkg-buildpackage -us -uc";
		system_or_die "cp $srcdir/*.deb $confdir";
		$this->load_packages;
		die "grafana-dashboard-helper: cannot build package, stopped"
			unless defined $$this{grafana_dashboard_helper_deb};
	}

	#### create server cert. if not exists
	unless( -f "$confdir/ncrt_key.pem" ){
		system_or_die "openssl req -verbose -subj '/C=JP/ST=Kanagawa-ken/O=Watao Family/CN=*' -x509 -newkey rsa:2048 -nodes -keyout $confdir/ncrt_key.pem -out $confdir/ncrt_cert.pem -days 36525";
	}
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

sub listMasterTypePlugins ($) {
	my ($this) = @_;
	return @{ $$this{mastertype_plugins} };
}

sub listAgentTypePlugins ($) {
	my ($this) = @_;
	return @{ $$this{agenttype_plugins} };
}

sub listAgentPlugins ($) {
	my ($this) = @_;
	return @{ $$this{agent_plugins} };
}

sub listAgentlessPlugins ($) {
	my ($this) = @_;
	return @{ $$this{agentless_plugins} };
}

sub listIndirectPlugins ($) {
	my ($this) = @_;
	return @{ $$this{indirect_plugins} };
}

sub listContactPlugins ($) {
	my ($this) = @_;
	return @{ $$this{contact_plugins} };
}

sub listReporterPlugins ($) {
	my ($this) = @_;
	return @{ $$this{reporter_plugins} };
}

sub listMeasurementPlugins ($) {
	my ($this) = @_;
	return
		@{ $$this{agent_plugins} },
		@{ $$this{agentless_plugins} },
		@{ $$this{indirect_plugins} };
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

sub loadThreholdFilterRules ($) {
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

