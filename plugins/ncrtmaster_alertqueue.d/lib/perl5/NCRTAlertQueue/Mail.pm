#!/usr/bin/perl

package NCRTAlertQueue::Mail;

use Exporter import;
our @EXPORT = (
	"send_mail",
);

use strict;
use NCRTAlertQueue;

use Carp::Always;
use Encode;
use MIME::EncWords ':all';


#### functions related to mail reporting

sub sendmail ($$$$) {
	my ($sendmailexe, $mail, $mailfrom, $mailto) = @_;

	open my $h, '|-', "$sendmailexe -f \Q$mailfrom\E \Q$mailto\E" or do {
		die "$sendmailexe: cannot execute, stopped";
	};
	chomp $mail;
	my @mail = split m"\n", $mail;
	while( 1 ){
		$_ = shift @mail;
		last if $_ eq '';

		my $text;
		while( m"\G(?:(\s+)|([-:<>.\@_a-zA-Z0-9\x7F-\xFF]+)|(\S+))"g ){
			if   ( $1 ne '' ){ $text .= $1; }
			elsif( $2 ne '' ){ $text .= $2; }
			else{ $text .= encode_mimeword $3, 'B', 'UTF-8'; }
		}
		print $h $text, "\n";
	}
	print $h "MIME-Version: 1.0\n";
	print $h "Content-Transfer-Encoding: 8bit\n";
	print $h "Content-Type: text/plain; charset=utf-8\n",
		"\n";
	while( 1 ){
		$_ = shift @mail;
		last unless defined $_;
		my $text = decode_utf8( $_ );
		print $h encode_utf8($text), "\n";
	}
	close $h;
}

sub send_mail ($$$$$$$$$$$) {
	my ($alertgroup, $uuid, $now, $action, $mailinfo,
	    $host_story, $service_story, $perf_story, $firing_host, $firing_service, $firing_perf) = @_;
	my $conf = load_conf;
	my $sessiondir     = $$conf{SESSIONDIR};
	my $sessionurlbase = $$conf{SESSIONURLBASE};
	my $sessionurl     = "$sessionurlbase/$uuid/";
	my $sendmailexe    = $$conf{SENDMAIL};

	my $addresses = $$mailinfo{addresses};
	my $param     = $$mailinfo{param};
	my $mailfrom = $$param{MAILFROM};

	foreach my $address ( @$addresses ){
		my $mailbody = generate_by_template "mail",
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

			"MAILFROM"       => $mailfrom,
			"MAILTO"         => $address,
			;
		sendmail $sendmailexe, $mailbody, $mailfrom, $address;
	}
}

####

1;

