#!/usr/bin/perl

package NCRTAlertQueue::Web;

use Exporter import;
our @EXPORT = (
	"get_gdhurl_and_grafanatoken",

	"there_is_webpage",
	"remove_webpage",
	"rename_webpage",
	"write_webpage",
	"write_png",

	"new_panelbasket",
	"download_panels_in_panelbasket",
	"create_imgreqs_of_panelbasket_if_not_exists",
	"wakeup_imgreqs_of_panelbasket",
	"rename_imgreqs_of_panelbasket",

	"list_sleeping_imgreqs",
	"read_sleeping_imgreq",
	"pickup_imgreq",
	"wakeup_imgreq",
	"put_imgreq_to_sleep",
	"remove_imgreq",
	"rename_imgreq",
	"download_img",
);

use strict;
use NCRTAlertQueue;

use Carp::Always;
use Encode;
use URI::Escape;
use JSON::XS;
use LWP::UserAgent;

our $JSON = JSON::XS->new->utf8;

#### Internal Functions

sub download_panel_png_from_grafana ($$$) {
	my ($url, $token, $param) = @_;
	my $timespan = $$param{PANEL_RENEWAL_TIMESPAN}+0 || 180;
	my $timeout  = $$param{PANEL_RENDERING_TIMEOUT}+0  || 10;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new('GET' => "${url}&timeout=${timeout}&from=now-${timespan}m&to=now");
	$req->header( Authorization => "Bearer $token" );
	debuglog "grafana: url=%s, requesting...", $url;
	my $res = $ua->request($req);
	debuglog "grafana: status=%s", $res->status_line;
	return undef unless $res->code eq '200';
	return $res->content;
}

sub query_panels_to_grafana_dashboard_helper ($$$$) {
	my ($gdhurl, $host, $service, $perf) = @_;
	my $query = uri_escape "ncrt_$service,host=$host $perf";

	my $ua = LWP::UserAgent->new;
	my $server_endpoint = "$gdhurl/search_panels_by_fieldkey_name.json?q=$query";
	my $req = HTTP::Request->new('GET' => $server_endpoint);
	debuglog "grafana-dashboard-helper: url=%s, requesting...", $server_endpoint;
	my $res = $ua->request($req);
	return undef unless $res->code eq '200';
	my $obj = eval { $JSON->decode($res->content); };
	return undef if $@;
	return $obj;
}

####

sub get_gdhurl_and_grafanatoken () {
	my $conf = load_conf;
	unless( $$conf{USE_LOCAL_GDH} ){
		return $$conf{GDHURL}, $$conf{GRAFANATOKEN};
	}
	
	my $gdhconf = load_gdh_conf;
	my $gdhlistenport = $$gdhconf{GDHLISTENPORT};
	my $grafanatoken = $$gdhconf{GRAFANATOKEN};
	return "http://localhost:$gdhlistenport", $grafanatoken;
}

####

sub there_is_webpage ($$) {
	my ($conf, $uuid) = @_;
	my $sessiondir = $$conf{SESSIONDIR};

	my $d = "$sessiondir/$uuid";
	return -d $d;
}

sub remove_webpage ($$) {
	my ($conf, $uuid) = @_;
	my $sessiondir = $$conf{SESSIONDIR};

	my $d = "$sessiondir/$uuid";
	rmdir_or_die $d;
}

sub rename_webpage ($$$) {
	my ($conf, $last_uuid, $next_uuid) = @_;
	my $sessiondir = $$conf{SESSIONDIR};

	my $lastd = "$sessiondir/$last_uuid";
	my $nextd = "$sessiondir/$next_uuid";
	rename $lastd, $nextd or do {
		die "rename: $lastd -> $nextd: cannot rename, stopped";
	};
}

sub write_webpage ($$$$$\%$;$) {
	my ($conf, $alertgroup, $uuid, $now, $action, $stats_summary, $panels, $next_uuid) = @_;
	my $sessiondir = $$conf{SESSIONDIR};
	my $sessionurlbase = $$conf{SESSIONURLBASE};
	my $sessionurl     = "$sessionurlbase/$uuid/";

	my $html = generate_by_template "web",
		"ALERTGROUP"     => $alertgroup,
		"UUID"           => $uuid,
		"NEXT_UUID"      => $next_uuid,
		"NOW"            => mktimestamp $now,
		"ACTION"         => $action,
		"SESSIONURL"     => $sessionurl,
		"PANELS"         => $panels,
		%$stats_summary,
		;

	my $d = "$sessiondir/$uuid";
	mkdir_or_die $d;
	my $f = "$d/index.html";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $html;
	close $h;
}

sub write_png ($$$$) {
	my ($conf, $uuid, $panelid, $png) = @_;
	my $sessiondir = $$conf{SESSIONDIR};
	my $d = "$sessiondir/$uuid";
	my $f = "$d/panel_$panelid.png";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $png;
	close $h;
}

sub download_panels_of_perf ($$$$) {
	my ($gdhurl, $host, $service, $perf) = @_;
	my $panels = query_panels_to_grafana_dashboard_helper
		$gdhurl, $host, $service, $perf;
}

#### PanelBasket Functions

sub new_panelbasket ($) {
	my ($uuid) = @_;
	return {
		"uuid" => $uuid,
		"panels_of_perf" => {},
		"panels" => [],
	};
}

sub download_panels_in_panelbasket ($$$) {
	my ($panelbasket, $gdhurl, $moid_list_of_fired_perfs) = @_;
	my $panels_of_perf = $$panelbasket{panels_of_perf};
	my $panels         = $$panelbasket{panels};

	foreach my $moid_of_fired_perf ( @$moid_list_of_fired_perfs ){
		next if defined $$panels_of_perf{$moid_of_fired_perf};

		my ($host, $service, $perf) = split " ", $moid_of_fired_perf;
		my $panels_of_fired_perf = download_panels_of_perf $gdhurl, $host, $service, $perf;
		$$panels_of_perf{$moid_of_fired_perf} = $panels_of_fired_perf;
		foreach my $panel_of_fired_perf ( @$panels_of_fired_perf ){
			my $panelid = sprintf "%03d", int( @$panels + 1 );
			$$panel_of_fired_perf{panelid} = $panelid;
			$$panel_of_fired_perf{host}    = $host;
			$$panel_of_fired_perf{service} = $service;
			$$panel_of_fired_perf{perf}    = $perf;
			push @$panels, $panel_of_fired_perf;
		}
	}
}

sub create_imgreqs_of_panelbasket_if_not_exists ($$$) {
	my ($panelbasket, $uuid, $downloadparam) = @_;
	my $panels = $$panelbasket{panels};
	foreach my $panel ( @$panels ){
		my $panelid = $$panel{panelid};
		my $imgid   = "$uuid+$panelid";
		my $f = "$main::WORKDIR/aq_img/$imgid.json";
		my $g = "$main::WORKDIR/aq_imgdl/$imgid.json";
		next if -f $f;
		next if -f $g;

		$$panel{uuid}    = $uuid;
		$$panel{imgid}   = $imgid;
		while( my ($k, $v) = each %$downloadparam ){
			$$panel{$k} = $v;
		}
		open my $h, ">", $g or die "$g: cannot open, stopped";
		print $h eval{ $JSON->encode($panel); }, "\n";
		close $h;
	}
}

sub wakeup_imgreqs_of_panelbasket ($) {
	my ($panelbasket) = @_;
	my $panels = $$panelbasket{panels};
	foreach my $panel ( @$panels ){
		my $imgid = $$panel{imgid};
		my $f = "$main::WORKDIR/aq_img/$imgid.json";
		my $g = "$main::WORKDIR/aq_imgdl/$imgid.json";
		next if -f $g;
		if( -f $f ){
			rename $f, $g;
			next;
		}
	}
}

sub rename_imgreqs_of_panelbasket ($$) {
	my ($panelbasket, $uuid) = @_;
	$$panelbasket{uuid} = $uuid;
	my $panels = $$panelbasket{panels};
	foreach my $panel ( @$panels ){
		my $panelid    = $$panel{panelid};
		my $prev_imgid = $$panel{imgid};
		my $imgid      = "$uuid+$panelid";
		$$panel{uuid}  = $uuid;
		$$panel{imgid} = $imgid;
		rename_imgreq($prev_imgid, $imgid, $uuid);
	}
	my $panels_of_perf = $$panelbasket{panels_of_perf};
	foreach my $panel ( values %$panels_of_perf ){
		my $panelid    = $$panel{panelid};
		my $prev_imgid = $$panel{imgid};
		my $imgid      = "$uuid+$panelid";
		$$panel{uuid}  = $uuid;
		$$panel{imgid} = $imgid;
	}
}

### ImgReq Functions

sub list_sleeping_imgreqs () {
	my @r;
	my $f = "$main::WORKDIR/aq_img";
	opendir my $h, $f or die "$f: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^([-+0-9a-fA-F]+)\.json$";
		push @r, $1;
	}
	close $h;
	return @r;
}

sub pickup_imgreq () {
	my @r;
	my $f = "$main::WORKDIR/aq_imgdl";
	my $imgid;
	my $imgreq;
	my $unixtime;
	opendir my $h, $f or die "$f: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^([-+0-9a-fA-F]+)\.json$";

		$imgid = $1;
		my $g = "$main::WORKDIR/aq_imgdl/$imgid.json";
		open my $i, '<', $g or do die "$f: cannot open, stopped";
		my $json = join "", <$i>;
		close $i;
		$imgreq = eval { $JSON->decode($json); };
		my ( $dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		     $atime,$mtime,$ctime,$blksize,$blocks ) = stat $g;
		$unixtime = $mtime;
		last;
	}
	close $h;
	return $imgid, $imgreq, $unixtime;
}

sub read_sleeping_imgreq ($) {
	my ($imgid) = @_;
	my $f = "$main::WORKDIR/aq_img/$imgid.json";
	open my $h, '<', $f or do die "$f: cannot open, stopped";
	my $json = join "", <$h>;
	close $h;
	my $r = eval { $JSON->decode($json); };
	my ( $dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	     $atime,$mtime,$ctime,$blksize,$blocks ) = stat $f;
	return $r, $mtime;
}

sub put_imgreq_to_sleep ($) {
	my ($imgid) = @_;
	my $f = "$main::WORKDIR/aq_imgdl/$imgid.json";
	my $g = "$main::WORKDIR/aq_img/$imgid.json";
	rename $f, $g or die "$f: cannot rename, stopped";
	open my $h, ">>", $g or die "$g: cannot open, stopped";
	close $h;
}

sub wakeup_imgreq ($) {
	my ($imgid) = @_;
	my $f = "$main::WORKDIR/aq_img/$imgid.json";
	my $g = "$main::WORKDIR/aq_imgdl/$imgid.json";
	rename $f, $g or die "$f: cannot rename, stopped";
}

sub remove_imgreq ($) {
	my ($imgid) = @_;
	my $f = "$main::WORKDIR/aq_img/$imgid.json";
	my $g = "$main::WORKDIR/aq_imgdl/$imgid.json";
	unlink $f if -f $f;
	unlink $g if -f $g;
}

sub rename_imgreq ($$$) {
	my ($imgid, $next_imgid, $uuid) = @_;
	foreach my $qname ("aq_img", "aq_imgdl"){
		my $f = "$main::WORKDIR/$qname/$imgid.json";
		next unless -f $f;

		open my $h, '<', $f or do die "$f: cannot open, stopped";
		my $json = join "", <$h>;
		close $h;
		my $imgreq = eval { $JSON->decode($json); };

		$$imgreq{uuid} = $uuid;
		$$imgreq{imgid} = $next_imgid;

		my $g = "$main::WORKDIR/$qname/$next_imgid.json";
		open my $h, ">", $g or die "$g: cannot open, stopped";
		print $h eval{ $JSON->encode($imgreq); }, "\n";
		close $h;

		unlink $f;
	}
}

sub download_img ($$$) {
	my ($conf, $grafanatoken, $imgreq) = @_;
	my $imgid   = $$imgreq{imgid};
	my $uuid    = $$imgreq{uuid};
	my $panelid = $$imgreq{panelid};
	my $url     = $$imgreq{url};
	my $param   = $$imgreq{param};
	my $png = download_panel_png_from_grafana $url, $grafanatoken, $param;
	write_png $conf, $uuid, $panelid, $png;
}

####

1;

