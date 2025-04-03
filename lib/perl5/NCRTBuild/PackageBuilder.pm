#!/usr/bin/perl

package NCRTBuild::PackageBuilder;

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
		'srcdir'	=> undef,

		'naemon2influx_deb'		=> undef,
		'grafana_dashboard_helper_deb'	=> undef,
	};
}

#### load template conf.


sub setToolDir ($$) {
	my ($this, $tooldir) = @_;
	$$this{tooldir} = $tooldir;
	my $confdir    = "$tooldir/conf";
	my $srcdir     = "$tooldir/src";
	$$this{confdir} = $confdir;
	$$this{srcdir} = $srcdir;
}

sub load ($) {
	my ($this) = @_;
	$this->load_packages;
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

sub buildSubModules ($) {
	my ($this) = @_;
	my $confdir = $$this{confdir};
	my $srcdir = $$this{srcdir};

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

1;

