#!/usr/bin/perl

package NCRTAlertQueue::Slack;

use Exporter import;
our @EXPORT = (
	"write_to_slack",
);

use strict;
use NCRTAlertQueue;

use Carp::Always;
use LWP::UserAgent;

use JSON::XS;
our $JSON = JSON::XS->new->utf8;

#### functions for Slack

sub post_http_to_url ($$$) {
	my ($url, $message, $param) = @_;

	my $timeout = $$param{SLACK_TIMEOUT} // 60;
	my $proxy   = $$param{SLACK_PROXY};

	my $ua = LWP::UserAgent->new;
	$ua->agent("NCRTSessionGroupPlugin/1.0");
	$ua->timeout($timeout);
	$ua->proxy(['http', 'https'], $proxy) if $proxy;

	my $header = [
		'Content-type' => 'application/json',
	];

	my $req = HTTP::Request->new('POST', $url, $header, $message);
	my $res = $ua->request($req);
	return undef unless $res->is_success;
	my $res_content = $res->content;
	debuglog "post_http_to_url: response body=%s", $res_content;
	return undef unless $res_content eq 'ok';
	return 1;
}

sub write_to_slack ($$$$$$$$$$$) {
	my ($alertgroup, $uuid, $now, $action, $slackinfo,
	    $host_story, $service_story, $perf_story, $firing_host, $firing_service, $firing_perf) = @_;
	my $conf = load_conf;
	my $sessiondir     = $$conf{SESSIONDIR};
	my $sessionurlbase = $$conf{SESSIONURLBASE};
	my $sessionurl     = "$sessionurlbase/$uuid/";

	my $urls = $$slackinfo{urls};
	my $param = $$slackinfo{param};

	foreach my $url ( @$urls ){
		my $message = generate_by_template "slack",
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
			;
		post_http_to_url $url, $message, $param;
	}

}


####

1;


