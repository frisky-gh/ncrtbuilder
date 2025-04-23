#!/usr/bin/perl

package NCRTAlertQueue::Web;

use Exporter import;
our @EXPORT = (
	"list_panels",
	"write_webpage",
	"write_png",
	"get_gdhurl_and_grafanatoken",
	"download_panel_png_from_grafana",
	"new_panelbasket",
	"update_panelbasket",
	"add_to_downloadqueue",
	"execute_downloadqueue",

	"generate_download_queue",
	"execute_download_queue",
);

use strict;
use NCRTAlertQueue;

use Carp::Always;
use Encode;
use URI::Escape;
use JSON::XS;
use LWP::UserAgent;

our $JSON = JSON::XS->new->utf8;

####

sub list_panels ($$) {
	my ($conf, $uuid) = @_;
	my $sessiondir     = $$conf{SESSIONDIR};
	my $sessionurlbase = $$conf{SESSIONURLBASE};
	my $sessionurl     = "$sessionurlbase/$uuid/";

	my @r;
	my $d = "$sessiondir/$uuid";
	opendir my $h, $d or die "$d: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^(\S+),(\S+),(\S+),(\d+)\.png$";

		my $f = "$d/$1,$2,$3,$4.json";
		open my $i, "<", $f or next;
		my $json = join "", <$i>;
		close $h;
		my $obj = eval { $JSON->decode($json); };

		push @r, {
			"host" => $1,
			"service" => $2,
			"perf" => $3,
			"index" => $4,
			"file" => $e,
			"title" => $$obj{panel_title},
		};
	}
	return @r;
}

sub write_webpage ($$$$$$$$$$$$) {
	my ($conf, $alertgroup, $uuid, $now, $action,
	    $host_story, $service_story, $perf_story, $firing_host, $firing_service, $firing_perf,
    	    $panels) = @_;
	my $sessiondir = $$conf{SESSIONDIR};
	my $sessionurlbase = $$conf{SESSIONURLBASE};
	my $sessionurl     = "$sessionurlbase/$uuid/";

	my $html = generate_by_template "web",
		"ALERTGROUP"     => $alertgroup,
		"UUID"           => $uuid,
		"NOW"            => mktimestamp $now,
		"ACTION"         => $action,
		"SESSIONURL"     => $sessionurl,
		"HOST_STORY"     => $host_story,
		"SERVICE_STORY"  => $service_story,
		"PERF_STRORY"    => $perf_story,
		"FIRING_HOST"    => $firing_host,
		"FIRING_SERVICE" => $firing_service,
		"FIRING_PERF"    => $firing_perf,
		"PANELS"         => $panels,
		;

	my $d = "$sessiondir/$uuid";
	my $f = "$d/index.html";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $html;
	close $h;
}

sub download_panel_png_from_grafana ($$$) {
	my ($url, $token, $param) = @_;
	my $timespan = $$param{GRAPH_TIMESPAN}+0 || 180;
	my $timeout  = $$param{GRAPH_TIMEOUT}+0  || 10;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new('GET' => "${url}&timeout=${timeout}&from=now-${timespan}m&to=now");
	$req->header( Authorization => "Bearer $token" );
	debuglog "grafana: url=%s, requesting...", $url;
	my $res = $ua->request($req);
	debuglog "grafana: status=%s", $res->status_line;
	return undef unless $res->code eq '200';
	return $res->content;
}

sub write_png ($$$$$) {
	my ($conf, $png, $alertgroup, $uuid, $panelid) = @_;
	my ($host, $service, $perf, $idx) = split " ", $panelid;
	my $sessiondir = $$conf{SESSIONDIR};
	my $d = "$sessiondir/$uuid";
	my $f = "$d/$host,$service,$perf,$idx.png";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $png;
	close $h;
}

sub write_paneljson ($$$$$) {
	my ($conf, $obj, $alertgroup, $uuid, $panelid) = @_;
	my ($host, $service, $perf, $idx) = split " ", $panelid;
	my $sessiondir = $$conf{SESSIONDIR};
	my $d = "$sessiondir/$uuid";
	my $f = "$d/$host,$service,$perf,$idx.json";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h eval{ $JSON->encode($obj); }, "\n";
	close $h;
}

sub get_mtime_of_png ($$$$) {
	my ($conf, $alertgroup, $uuid, $panelid) = @_;
	my ($host, $service, $perf, $idx) = split " ", $panelid;
	my $sessiondir = $$conf{SESSIONDIR};
	my $d = "$sessiondir/$uuid";
	my $f = "$d/$host,$service,$perf,$idx.png";
	my @r = stat $f;
	return $r[9];
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

sub get_panels_of_perf ($$$$) {
	my ($gdhurl, $host, $service, $perf) = @_;
	my $panels = query_panels_to_grafana_dashboard_helper
		$gdhurl, $host, $service, $perf;
}

sub new_panelbasket () {
	return {
		"panels_of_perf" => {},
		"panels" => [],
	};
}

sub update_panelbasket ($$$) {
	my ($panelbasket, $gdhurl, $fired_perfs) = @_;
	my $panels_of_perf = $$panelbasket{panels_of_perf};
	my $panels         = $$panelbasket{panels};

	while( my ($host_service_perf, undef) = each %$fired_perfs ){
		next if defined $$panels_of_perf{$host_service_perf};

		my ($host, $service, $perf) = split " ", $host_service_perf;
		my $r = get_panels_of_perf $gdhurl, $host, $service, $perf;
		my $index = 1;
		foreach my $i ( @$r ){
			$$i{panelid} = sprintf "%s %03d", $host_service_perf , $index++;
			push @$panels, $i;
		}
		$$panels_of_perf{$host_service_perf} = $r;
	}
}

sub execute_downloadqueue (\@$$$) {
	my ($downloadqueue, $conf, $download_status, $grafanatoken) = @_;

	my $now = time;
	@$downloadqueue = sort {$$a{unixtime} <=> $$b{unixtime}} @$downloadqueue;
	foreach my $i ( @$downloadqueue ){
		my $alertgroup = $$i{alertgroup};
		my $uuid = $$i{uuid};
		my $last_download_unixtime = $$i{unixtime};
		my $param = $$i{param};
		my $timeout = $$param{GRAPH_TIMEOUT};
		my $timespan = $$param{GRAPH_TIMESPAN};

		next unless $last_download_unixtime + $timespan*60 < $now;

		my $panelid = $$i{panelid};
		my $url = $$i{url};
		my $png = download_panel_png_from_grafana $url, $grafanatoken, $param;
		write_png       $conf, $png, $alertgroup, $uuid, $panelid;
		write_paneljson $conf, $i,   $alertgroup, $uuid, $panelid;

		++$$download_status{count};
		return if $$download_status{count} >= $$download_status{max};
	}
}

sub add_to_downloadqueue (\@$$$$$) {
	my ($downloadqueue, $conf, $alertgroup, $uuid, $panelbasket, $downloadparam) = @_;
	my $panels = $$panelbasket{panels};

	foreach my $i ( @$panels ){
		my $panelid = $$i{panelid};
		my $url = $$i{url};
		my $mtime = get_mtime_of_png $conf, $alertgroup, $uuid, $panelid;
		push @$downloadqueue, {
			"alertgroup" => $alertgroup,
			"uuid"       => $uuid,

			"panelid"  => $panelid,
			"url" => $url,
			"unixtime" => $mtime,
			"panel_name"  => $$i{panel_name},
			"panel_title" => $$i{panel_title},

			"param" => $downloadparam,
		};
	}
}



####

1;

