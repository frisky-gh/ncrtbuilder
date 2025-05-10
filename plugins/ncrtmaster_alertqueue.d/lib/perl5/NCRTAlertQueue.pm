#!/usr/bin/perl

package NCRTAlertQueue;

use Exporter import;
our @EXPORT = (
	"mktimestamp",
	"mkuuid",

	"safesprintf",
	"var2ltsv",
	"ltsv2var",
	"path_encode",
	"path_decode ",
	"expand_named_placeholders",

	"openlog",
	"debuglog",
	"errorlog",

	"system_or_die",
	"run_as_background",
	"mkdir_or_die",
	"rmdir_or_die",

	"load_conf",
	"load_gdh_conf",
	"load_alertrules",
	"load_reportrules",
	"get_slack_urls",
	"get_mail_addresses",
	"get_report_param",

	"list_eventqueue",
	"remove_eventqueue",

	"output_course_of_events",
	"list_eventbasket",
	"write_eventbasket",
	"unlink_eventbasket",
	"get_size_of_eventbasket",
	"read_latest_eventbasket",

	"read_alertid",
	"write_alertid",
	"remove_alertid",

	"sort_by_rules",
	"open_livestatus_socket",
	"load_and_sort_events",
	"load_and_sort_hoststate",
	"load_and_sort_servicestate",

	"new_sortedevents",
	"write_sortedevents",
	"downsample_eventqueues",

	"list_reportstatus",
	"read_reportstatus",
	"write_reportstatus",
	"remove_reportstatus",
	"reportstatus_exists",

	"generate_by_template",
);

use strict;
use Carp::Always;
use Socket;
use Encode;
use JSON::XS;
use URI::Escape;
use Time::Local;
use Template;
use OSSP::uuid;

our $DEBUG;
our $JSON = JSON::XS->new->utf8;
our $LIVESTATUS_SOCKET = "/var/cache/naemon/live";

#### load conf.

sub load_conf () {
	my %conf = (
		"DEBUG" => 1,
		"SESSIONDIR"     => "/var/www/ncrtmaster",
		"SESSIONURLBASE" => "https://www.example.com/ncrtmaster",
		"MAILFROM"       => "ncrtmaster\@example.com",
		"SENDMAIL"       => "/usr/lib/sendmail",
		"USE_LOCAL_GDH"  => 1,
		"LOCALGDHCONF"   => "/etc/grafana-dashboard-helper/grafana-dashboard-helper.conf",
		"GDHURL"         => "https://www.example.com/grafana-dashboard-helper",
		"GRAFANATOKEN"   => "glsa_***",
	);

	my $f = "$main::CONFDIR/reporter/alertqueue.conf";
	open my $h, '<', $f or do die "$f: cannot open, stopped";
	while( <$h> ){
		chomp;
		next if m"^\s*($|#)";
		die "$f:$.: invalid format, stopped" unless m"^(\w+)=(.*)";
		$conf{$1} = $2;
	}
	$DEBUG = $conf{DEBUG};
	return \%conf;
}

sub load_gdh_conf () {
	my $conf = load_conf;
	my $gdhconf_path = $$conf{LOCALGDHCONF};
	my %gdhconf = (
		"GRAFANATOKEN"  => "glsa_***",
		"GDHLISTENPORT" => 0,
	);

	open my $h, '<', $gdhconf_path or do die "$gdhconf_path: cannot open, stopped";
	while( <$h> ){
		chomp;
		next if m"^\s*($|#)";
		die "$gdhconf_path:$.: invalid format, stopped" unless m"^(\w+)=(.*)";
		next unless defined $gdhconf{$1};
		$gdhconf{$1} = $2;
	}
	return \%gdhconf;
}

sub load_alertrules () {
	my @rules_of_host;
	my @rules_of_service;
	my @rules_of_perf;
	my %fixed_alertgroup;
	my $curr_entry;
	my $f = "$main::CONFDIR/reporter/alertqueue.alertrules";
	open my $h, '<', $f or do die "$f: cannot open, stopped";
	while( <$h> ){
		chomp;
		next if m"^\s*($|#)";

		if    ( m"^alert_of_(host|service|perf):\s+(\S.*)" ){
			my $type = $1;
			my $alertgroup = $2;
			unless( $alertgroup =~ m"<\w+>" ){ $fixed_alertgroup{$alertgroup} = 1; }
			$curr_entry = {
				"alertgroup" => $alertgroup,
				"conditions" => [],
			};
			if   ( $type eq "host" )   { push @rules_of_host, $curr_entry; }
			elsif( $type eq "service" ){ push @rules_of_service, $curr_entry; }
			elsif( $type eq "perf" )   { push @rules_of_perf, $curr_entry; }
			else		       { die "$f:$.: invalid word, stopped"; }
		}elsif( m"^\s*(\w+)(~|!~)\s+(\S.*)" ){
			my $op;
			if   ( $2 eq "~" ) { $op = "match"; }
			elsif( $2 eq "!~" ){ $op = "unmatch"; }
			else	       { die "$f:$.: invalid operator, stopped"; }
			push @{$$curr_entry{conditions}}, {
				"op" => $op,
				"name" => $1,
				"regexp" => qr"$3",
			};
		}else{
			die "$f:$.: illegal format, stopped";
		}
	}
	close $h;

	return \@rules_of_host, \@rules_of_service, \@rules_of_perf, [keys %fixed_alertgroup];
}

sub load_reportrules () {
	my @rules;
	my $curr_entry;
	my $f = "$main::CONFDIR/reporter/alertqueue.reportrules";
	open my $h, '<', $f or do die "$f: cannot open, stopped";
	while( <$h> ){
		chomp;
		next if m"^\s*($|#)";

		if    ( m"^alert:\s+(\S.*)" ){
			my $alertgroup = $1;
			$curr_entry = {
				"alertgroup" => $alertgroup,
				"alertgroup_regexp" => qr"^$alertgroup$",
				"param" => {},
				"mail"  => [],
				"slack" => [],
			};
			push @rules, $curr_entry;

		}elsif( m"^\s*(mail|slack)\s+(\S.*)" ){
			push@{ $$curr_entry{$1} }, $2;

		}elsif( m"^\s*(\w+)=(.*)" ){
			$$curr_entry{param}->{$1} = $2;

		}else{
			die "$f:$.: illegal format, stopped";
		}
	}
	close $h;

	return \@rules;
}

our %DEFAULT_REPORT_PARAM = (
	"MAILFROM"         => 'ncrt-alertqueue@example.com',
	"UPDATE_TIMESPAN"  => 10,
	"RESEND_TIMESPAN"  => 30,
	"CLOSE_TIMESPAN"   => 30,
	"EXPIRE_TIMESPAN"  => 10080,
	"RENAME_TIMESPAN"  => 8640,
	"GRAPH_TIMEOUT"    => 30,
	"GRAPH_TIMESPAN"   => 480,
	"CLEANUP_TIMESPAN" => 7200,
);

sub get_slack_urls ($$) {
	my ($reportrules, $alertgroup) = @_;
	my @url;
	my %param = %DEFAULT_REPORT_PARAM;
	foreach my $entry ( @$reportrules ){
		my $regexp = $$entry{alertgroup_regexp};
		next unless $alertgroup =~ $regexp;
		my $slack_list = $$entry{slack};
		my $param = $$entry{param};
		push @url, @$slack_list;
		%param = (%param, %$param);
	}
	return {
		"urls" => \@url,
		"param" => \%param,
	};
}

sub get_mail_addresses ($$) {
	my ($reportrules, $alertgroup) = @_;
	my @address;
	my %param = %DEFAULT_REPORT_PARAM;
	foreach my $entry ( @$reportrules ){
		my $regexp = $$entry{alertgroup_regexp};
		next unless $alertgroup =~ $regexp;
		my $mail_list = $$entry{mail};
		my $param = $$entry{param};
		push @address, @$mail_list;
		%param = (%param, %$param);
	}
	return {
		"addresses" => \@address,
		"param" => \%param,
	};
}

sub get_report_param ($$) {
	my ($reportrules, $alertgroup) = @_;
	my %param = %DEFAULT_REPORT_PARAM;
	foreach my $entry ( @$reportrules ){
		my $regexp = $$entry{alertgroup_regexp};
		next unless $alertgroup =~ $regexp;
		my $param = $$entry{param};
		%param = (%param, %$param);
	}
	return \%param;
}

####
sub mktimestamp (;$) {
	my $t = shift // time;
	my ($sec, $min, $hour, $day, $mon, $year) = localtime $t;
	return sprintf "%04d-%02d-%02d_%02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
}

sub mkuuid () {
	my $uuid_gen = new OSSP::uuid;
	$uuid_gen->make("v4", undef, undef);
	return $uuid_gen->export("str");
}

sub safesprintf ( @ ){
	my ($format, @args) = @_;
	my $text = sprintf $format, @args;
	$text =~ s{([\x00-\x1f\x7f])}{"\\x" . unpack('H2', $1);}eg;
	return $text;
}

sub ltsv2var ( $ ){
	my ($ltsv) = @_;
	my %var;
	foreach my $kv ( split m"\t", $ltsv ){
		$kv =~ m"^([-.\w]+):(.*)$" or do {
			next;
		};
		my $k = $1;
		my $v = $2;
		$var{$k} = $v;
	}
	return %var;
}

sub path_encode ($) {
	my ($text) = @_;
	$text =~ s{([\x00-\x1f/\x7f])}{"\%" . unpack('H2', $1);}eg;
	return $text;
}

sub path_decode ($) {
	my ($text) = @_;
	$text =~ s{%([0-9a-fA-F]{2})}{pack('H2', $1);}eg;
	return $text;
}

sub expand_named_placeholders ($%) {
	my ($text, @params_list) = @_;
	$text =~ s{ <(\w+)> }{
		my $r;
		foreach( @params_list ){ $r = $$_{$1}; last if defined $r; }
		$r;
	}egx;
	return $text;
}

####
our $LOG_HANDLE;
sub openlog () {
	open $LOG_HANDLE, '>>', "$main::WORKDIR/alertqueue.log" or return;
	my $old = select $LOG_HANDLE;
	$| = 1;
	select $old;
}

sub debuglog ( $;@ ){
	return unless $DEBUG;
	openlog unless defined $LOG_HANDLE;
	print $LOG_HANDLE mktimestamp(time), " ", safesprintf(@_), "\n";
}

sub errorlog ( $;@ ){
	openlog unless defined $LOG_HANDLE;
	print $LOG_HANDLE mktimestamp(time), " ", safesprintf(@_), "\n";
}

sub var2ltsv ( \% ){
	my ($var) = @_;
	my @ltsv;
	push @ltsv, "timestamp:".$var->{timestamp} if defined $var->{timestamp};
	foreach my $k ( sort {$a cmp $b} keys %$var ){
		next if $k eq 'timestamp';
		push @ltsv, "$k:".$var->{$k};
	}
	return join "\t", @ltsv;
}

#### I/O functions

sub mkdir_or_die ($) {
	my ($d) = @_;
	return if -d $d;
	mkdir $d or die "$d: cannot create, stopped";
}

sub system_or_die ($) {
	my ($cmd) = @_;
	my $r = system $cmd;
	if   ($? == -1){
		die sprintf "%s: failed to execute: %d, stopped",
			$cmd, $!;
	}elsif($? & 127){
		die sprintf
			"%s: child died with signal %d, %s coredump, stopped",
			$cmd, ($? & 127), ($? & 128) ? 'with' : 'without';
	}elsif( ($?>>8) != 0){
		 die sprintf "%s: child exited with value %d, stopped",
			$cmd, $? >> 8;
	}
}

sub rmdir_or_die ($) {
	my ($d) = @_;
	return unless -d $d;
	opendir my $h, $d or die "$d: cannot open, stopped";
	my @e = readdir $h;
	close $h;
	foreach( @e ){
		next if m"^(\.|\.\.)$";
		unlink "$d/$_" or die "$d/$_: cannot remove, stopped";;
	}
	rmdir $d or die "$d: cannot remove. stopped";
}

sub run_as_background ($) {
	my ($cmd) = @_;
	my $pid = fork;
	return if $pid;

	print "DEBUG: background: $cmd\n";
	exec $cmd or die "Failed to execute: $!";
	exit 126;
}

sub list_eventqueue () {
	my @r;
	my $f = "$main::WORKDIR/aq_event";
	opendir my $h, $f or die "$f: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^([a-zA-Z][.-\w]*)$";
		next unless -d "$f/$e";
		push @r, $1;
	}
	close $h;
	return @r;
}

sub remove_eventqueue ($) {
	my ($alertgroup) = @_;
	my $d = "$main::WORKDIR/aq_event/$alertgroup";
	rmdir_or_die $d;
}

sub list_eventbasket ($) {
	my ($alertgroup) = @_;
	my @r;
	my $f = "$main::WORKDIR/aq_event/$alertgroup";
	opendir my $h, $f or do {
		debuglog "$f: not found.";
		return ();
	};
	while( my $e = readdir $h ){
		next unless $e =~ m"^((\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2}):(\d{2}))\.json$";
		my $timestamp = $1;
		my $year = $2;
		my $mon = $3;
		my $day = $4;
		my $hour = $5;
		my $min = $6;
		my $sec = $7;
		my $unixtime = eval { timelocal $sec, $min, $hour, $day, $mon-1, $year; };
		push @r, {
			"timestamp" => $timestamp,
			"unixtime" => $unixtime,
		};
	}
	close $h;
	return @r;
}

sub write_eventbasket ($$$) {
	my ($alertgroup, $timestamp, $eventbasket) = @_;
	my $d = "$main::WORKDIR/aq_event/$alertgroup";
	unless( -d $d ){
		return unless %$eventbasket;
		mkdir_or_die $d;
	}
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	my $json = $JSON->encode( $eventbasket );
	print $h encode_utf8($json);
	close $h;
}

sub read_eventbasket ($$) {
	my ($alertgroup, $timestamp) = @_;
	my $d = "$main::WORKDIR/aq_event/$alertgroup";
	return undef unless -d $d;
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	my $json = join "", <$h>;
	close $h;
	my $eventbasket = eval { $JSON->decode($json); };
	return $eventbasket;
}

sub unlink_eventbasket ($$) {
	my ($alertgroup, $timestamp) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	unlink $f;
}

sub get_size_of_eventbasket ($$) {
	my ($alertgroup, $timestamp) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	my ( $dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
             $atime,$mtime,$ctime,$blksize,$blocks ) = stat $f;
	return $size;
}

####

sub read_alertid ($) {
	my ($alertgroup) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup.json";
	return unless -f $f;
	open my $h, "<", $f or die "$f: cannot open, stopped";
	my $json = join "", <$h>;
	close $h;
	my $obj = eval { $JSON->decode( $json ); };
	return $$obj{uuid}, $$obj{creation_unixtime}, $$obj{prev_uuid};
}

sub write_alertid ($$$;$) {
	my ($alertgroup, $uuid, $creation_unixtime, $prev_uuid) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup.json";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $JSON->encode( {
		"uuid"      => $uuid,
		"prev_uuid" => $prev_uuid,
		"creation_unixtime"  => $creation_unixtime,
		"creation_timestamp" => mktimestamp($creation_unixtime),
	} );
	close $h;
}

sub remove_alertid ($) {
	my ($alertgroup) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup.json";
	return 1 unless -f $f;
	return unlink $f;
}

####

sub list_reportstatus ($) {
	my ($category) = @_;
	my @r;
	my $f = "$main::WORKDIR/aq_$category";
	opendir my $h, $f or die "$f: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^([-0-9a-fA-F]+)\.json$";
		push @r, $1;
	}
	close $h;
	return @r;
}

sub read_reportstatus ($$) {
	my ($category, $uuid) = @_;
	my $f = "$main::WORKDIR/aq_$category/$uuid.json";
	open my $h, "<", $f or return;
	my $json = join "", <$h>;
	close $h;
	my $obj = eval { $JSON->decode($json); };
	return $$obj{alertgroup}, $$obj{unixtime}, $$obj{status};
}

sub write_reportstatus ($$$$$) {
	my ($category, $uuid, $alertgroup, $unixtime, $status) = @_;
	my $obj = {
		"category" => $category,
		"alertgroup" => $alertgroup,
		"uuid" => $uuid,
		"unixtime" => $unixtime,
		"timestamp" => mktimestamp($unixtime),
		"status" => $status,
	};
	my $json = eval { $JSON->encode($obj); };
	my $f = "$main::WORKDIR/aq_$category/$uuid.json";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $json, "\n";
	close $h;
}

sub remove_reportstatus ($$) {
	my ($category, $uuid) = @_;
	my $f = "$main::WORKDIR/aq_$category/$uuid.json";
	unlink $f;
}

sub reportstatus_exists ($$) {
	my ($category, $uuid) = @_;
	my $f = "$main::WORKDIR/aq_$category/$uuid.json";
	return -f $f;
}

sub add_host_story ($$$$$) {
	my ($alertgroup, $unixtime, $events, $fired_hosts, $hosts_story) = @_;
	my $timestamp = mktimestamp $unixtime;

	my %curr_states;
	foreach my $i ( @$events ){
		my $host = $$i{host};
		my $id = "$host";
		$curr_states{$id} = $i;
	}

	while( my ($id, $latest_states) = each %$fired_hosts ){
		my $curr_states = $curr_states{$id};
		my $curr_state  = $$curr_states{state} // "Ok";
		my $latest_state = $$latest_states{state} // "Ok";

		next if $curr_state && $latest_state;

		push @$hosts_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => $latest_state,
			"state" => $curr_state,
		};
		$$fired_hosts{$id} = $curr_states;
	}
	while( my ($id, $curr_states) = each %curr_states ){
		next if defined $$fired_hosts{$id};
		my $curr_state = $$curr_states{state} // "Ok";
		push @$hosts_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => "Ok",
			"state" => $curr_state,
		};
		$$fired_hosts{$id} = $curr_states;
	}
}

sub add_service_story ($$$$$) {
	my ($alertgroup, $unixtime, $events, $fired_services, $services_story) = @_;
	my $timestamp = mktimestamp $unixtime;

	my %curr_states;
	foreach my $i ( @$events ){
		my $host = $$i{host};
		my $service = $$i{service};
		my $id = "$host $service";
		$curr_states{$id} = $i;
	}

	while( my ($id, $latest_states) = each %$fired_services ){
		my $curr_states = $curr_states{$id};
		my $curr_state  = $$curr_states{state} // "Ok";
		my $latest_state = $$latest_states{state} // "Ok";

		next if $curr_state && $latest_state;

		push @$services_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => $latest_state,
			"state" => $curr_state,
		};
		$$fired_services{$id} = $curr_states;
	}
	while( my ($id, $curr_states) = each %curr_states ){
		next if defined $$fired_services{$id};
		my $curr_state = $$curr_states{state} // "Ok";
		push @$services_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => "Ok",
			"state" => $curr_state,
		};
		$$fired_services{$id} = $curr_states;
	}
}

sub add_perf_story ($$$$$) {
	my ($alertgroup, $unixtime, $events, $fired_perfs, $perfs_story) = @_;
	my $timestamp = mktimestamp $unixtime;

	my %curr_states;
	foreach my $i ( @$events ){
		my $host = $$i{host};
		my $service = $$i{service};
		my $perf = $$i{perf};
		my $id = "$host $service $perf";
		$curr_states{$id} = $i;
	}

	while( my ($id, $latest_states) = each %$fired_perfs ){
		my $curr_states = $curr_states{$id};
		my $curr_state  = $$curr_states{state} // "Ok";
		my $latest_state = $$latest_states{state} // "Ok";

		next if $curr_state && $latest_state;

		push @$perfs_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => $latest_state,
			"state" => $curr_state,
		};
		$$fired_perfs{$id} = $curr_states;
	}
	while( my ($id, $curr_states) = each %curr_states ){
		next if defined $$fired_perfs{$id};
		my $curr_state = $$curr_states{state} // "Ok";
		push @$perfs_story, {
			"alertgroup" => $alertgroup,
			"unixtime" => $unixtime,
			"timestamp" => $timestamp,
			"id" => $id,
			"old_state" => "Ok",
			"state" => $curr_state,
		};
		$$fired_perfs{$id} = $curr_states;
	}
}

sub output_course_of_events ($$$$$$) {
	my ($alertgroup, $start_unixtime, $end_unixtime,
	    $fired_hosts, $fired_services, $fired_perfs) = @_;

	my @names = list_eventbasket $alertgroup;
	my @sorted_names = sort { $$a{unixtime} <=> $$b{unixtime} } @names;
	my @hosts_story;
	my @services_story;
	my @perfs_story;
	foreach my $i ( @sorted_names ){
		my $unixtime  = $$i{unixtime};
		my $timestamp = $$i{timestamp};
		next unless $start_unixtime <= $unixtime && $unixtime <= $end_unixtime;

		my $eventbasket = read_eventbasket $alertgroup, $timestamp;
		while( my ($k, $v) = each %$eventbasket ){
			if    ( $k eq "host_events" ){
				add_host_story    $alertgroup, $unixtime, $v,
					$fired_hosts, \@hosts_story;
			}elsif( $k eq "service_events" ){
				add_service_story $alertgroup, $unixtime, $v,
					$fired_services, \@services_story;
			}elsif( $k eq "perf_events" ){
				add_perf_story    $alertgroup, $unixtime, $v,
					$fired_perfs, \@perfs_story;
			}
		}
	}
	return \@hosts_story, \@services_story, \@perfs_story;
}

sub read_latest_eventbasket ($) {
	my ($alertgroup) = @_;
	my @names = list_eventbasket $alertgroup;
	my $latest_name = $names[-1];
	my $latest_eventbaskets = read_eventbasket $alertgroup, $$latest_name{timestamp};
	return $latest_eventbaskets, $$latest_name{unixtime}, $$latest_name{timestamp};
}


####

sub sort_by_rules (\%$) {
	my ($var, $rules) = @_;
	my @r;
	foreach my $rule ( @$rules ){
		my $alertgroup = $$rule{alertgroup};
		my $conditions = $$rule{conditions};
		my $hit = 1;
		my %captured;
		foreach my $condition ( @$conditions ){
			my $op     = $$condition{op};
			my $name   = $$condition{name};
			my $regexp = $$condition{regexp};
			my $value = $$var{$name};
			if( ref($value) eq 'ARRAY' ){
				if    ( $op eq "match" ){
					my $h;
					foreach my $v ( @$value ){
						next unless $v =~ $regexp;
						$h = 1;
						while( my ($k, $v) = each %+ ){
							$captured{$k} = $v;
						}
						last;
					}
					unless( $h ){
						$hit = undef;
						last;
					}
				
				}elsif( $op eq "unmatch" ){
					my $h;
					foreach my $v ( @$value ){
						next unless $v =~ $regexp;
						$h = 1;
						last;
					}
					if( $h ){
						$hit = undef;
						last;
					}
				}
			}else{
				if    ( $op eq "match" ){
					unless( $value =~ $regexp ){
						$hit = undef;
						last;
					}
					while( my ($k, $v) = each %+ ){
						$captured{$k} = $v;
					}
				}elsif( $op eq "unmatch" ){
					unless( $value !~ $regexp ){
						$hit = undef;
						last;
					}
				}
			}
		}
		next unless $hit;

		my $expaneded_alertgroup = expand_named_placeholders $alertgroup, \%captured, $var;
		push @r, $expaneded_alertgroup;
	}		
	return @r;
}

sub open_livestatus_socket ($$) {
	my ($req, $columns) = @_;

	socket my $h, PF_UNIX, SOCK_STREAM, 0 or die;
	connect $h, sockaddr_un($LIVESTATUS_SOCKET) or die;
	$h->autoflush(1);
	print $h "$req\n";
	print $h "Columns: $columns\n";
	print $h "\n";
	shutdown $h, 1;
	return $h;
}

our @text_of_state = (
	'OK',
	'Warning',
	'Critical',
	'Unknown',
);

sub load_and_sort_hoststate ($$$) {
	my ($sortedevents, $sortrules_of_host, $sortrules_of_perf) = @_;

	my $h = open_livestatus_socket
		"GET hosts", 
		"host_groups host_name custom_variables state state_type last_hard_state perf_data";

	while( my $i = <$h> ){
       		$_ = decode_utf8( $i );
		chomp;
		unless( m"^([^;]*);([^;]+);([^;]*);(\d*);(\d*);(\d*);(.*)$" ){
			die "$_: invalid livestatus date, stopped";
		}

		my $host_groups      = $1;
		my $host	     = $2;
		my $custom_variables = $3;
		my $state            = $4;
		my $state_type       = $5;
		my $last_hard_state  = $6;
		my $perf_data        = $7;

		my $hard_state = $state_type == 1 ? $state : $last_hard_state;
		
		#
		my @host_groups;
		@host_groups = split m"\s+", $host_groups unless $host_groups eq '';

		#
		my %custom_variables;
		if( $custom_variables ne '' ){
			foreach my $kv ( split m",", $custom_variables ){
				$kv =~ m"^(\w+)\|(.*)$" or die;
				$custom_variables{$1} = $2;
			}
		}

		if( $hard_state ){
			my $text_of_state = $text_of_state[$hard_state];
			my %var = (
				%custom_variables,
				"host_groups" => \@host_groups,
				"host"    => $host,
				"state"   => $text_of_state,
			);
			my @sorted = sort_by_rules %var, $sortrules_of_host;
			@sorted = ("__Dropped__") unless @sorted;
			foreach my $alertqueue ( @sorted ){
				push @{ $$sortedevents{$alertqueue}->{host_events} }, \%var;
			}
		}
		
		foreach my $p ( split m"\s+", $perf_data ){
			die "$p, stopped" unless $p =~ m"^
				([^=]+)=(-?\d[^;]*)(?:s|ms|us|%|B|KB|MB|GB|TB|c)?
				;(?:([^;:]*)(?::([^;:]*))?)
				;(?:([^;:]*)(?::([^;:]*))?)
			"x;
			my $k = $1;
			my $v = $2;
			my $warn_min = $3;
			my $warn_max = $4;
			my $warn = $3 ne '' ? "[$3,$4]" : undef;
			my $crit_min = $5;
			my $crit_max = $6;
			my $crit = $6 ne '' ? "[$5,$6]" : undef;
			my $perf_state = 0;
			my $perf_statetext;
			if    ( $crit_min ne '' && $v < $crit_min ){
				$perf_state = 2; $perf_statetext = 'under_crit';
			}elsif( $crit_max ne '' && $v > $crit_max ){
				$perf_state = 2; $perf_statetext = 'over_crit';
			}elsif( $warn_min ne '' && $v < $warn_min ){
				$perf_state = 1; $perf_statetext = 'under_warn';
			}elsif( $warn_max ne '' && $v > $warn_max ){
				$perf_state = 1; $perf_statetext = 'over_warn';
			}

			if( $perf_state ){
				my $text_of_state = $text_of_state[$perf_state];
				my %var = (
					%custom_variables,
					"host_groups" => \@host_groups,
					"host"      => $host,
					"state"     => $text_of_state,
					"perf"      => $k,
					"value"     => $v,
					"perfstate" => $perf_statetext,
					"warn_min"  => $warn_min,
					"warn_max"  => $warn_max,
					"warn"      => $warn,
					"crit_min"  => $crit_min,
					"crit_max"  => $crit_max,
					"crit"      => $crit,
				);
				my @sorted = sort_by_rules %var, $sortrules_of_perf;
				@sorted = ("__Dropped__") unless @sorted;
				foreach my $alertqueue ( @sorted ){
					push @{ $$sortedevents{$alertqueue}->{perf_events} }, \%var;
				}
			}
		}
	}
	close $h;
}

sub load_and_sort_servicestate ($$$) {
	my ($sortedevents, $sortrules_of_service, $sortrules_of_perf) = @_;

	my $h = open_livestatus_socket
		"GET services", 
		"service_groups host_name description custom_variables state state_type last_hard_state perf_data";

	while( my $i = <$h> ){
       		$_ = decode_utf8( $i );
		chomp;
		unless( m"^([^;]*);([^;]+);([^;]+);([^;]*);(\d*);(\d*);(\d*);(.*)$" ){
			die "$_: invalid livestatus date, stopped";
		}

		my $service_groups   = $1;
		my $host	     = $2;
		my $service          = $3;
		my $custom_variables = $4;
		my $state            = $5;
		my $state_type       = $6;
		my $last_hard_state  = $7;
		my $perf_data        = $8;

		my $hard_state = $state_type == 1 ? $state : $last_hard_state;
		next if $service_groups eq '';
		
		#
		my @service_groups;
		@service_groups = split m"\s+", $service_groups unless $service_groups eq '';

		#
		my %custom_variables;
		if( $custom_variables ne '' ){
			foreach my $kv ( split m",", $custom_variables ){
				$kv =~ m"^(\w+)\|(.*)$" or die;
				$custom_variables{$1} = $2;
			}
		}

		if( $hard_state ){
			my $text_of_state = $text_of_state[$hard_state];
			my %var = (
				%custom_variables,
				"service_groups" => \@service_groups,
				"host"    => $host,
				"service" => $service,
				"state"   => $text_of_state,
			);
			my @sorted = sort_by_rules %var, $sortrules_of_service;
			@sorted = ("__Dropped__") unless @sorted;
			foreach my $alertqueue ( @sorted ){
				push @{ $$sortedevents{$alertqueue}->{service_events} }, \%var;
			}
		}
		
		foreach my $p ( split m"\s+", $perf_data ){
			die "$p, stopped" unless $p =~ m"^
				([^=]+)=(-?\d[^;]*)(?:s|ms|us|%|B|KB|MB|GB|TB|c)?
				;(?:([^;:]*)(?::([^;:]*))?)
				;(?:([^;:]*)(?::([^;:]*))?)
			"x;
			my $k = $1;
			my $v = $2;
			my $warn_min = $3;
			my $warn_max = $4;
			my $warn = $3 ne '' ? "[$3,$4]" : undef;
			my $crit_min = $5;
			my $crit_max = $6;
			my $crit = $6 ne '' ? "[$5,$6]" : undef;
			my $perf_state = 0;
			my $perf_statetext;
			if    ( $crit_min ne '' && $v < $crit_min ){
				$perf_state = 2; $perf_statetext = 'under_crit';
			}elsif( $crit_max ne '' && $v > $crit_max ){
				$perf_state = 2; $perf_statetext = 'over_crit';
			}elsif( $warn_min ne '' && $v < $warn_min ){
				$perf_state = 1; $perf_statetext = 'under_warn';
			}elsif( $warn_max ne '' && $v > $warn_max ){
				$perf_state = 1; $perf_statetext = 'over_warn';
			}

			if( $perf_state ){
				my $text_of_state = $text_of_state[$perf_state];
				my %var = (
					%custom_variables,
					"service_groups" => \@service_groups,
					"host"    => $host,
					"service" => $service,
					"state"   => $text_of_state,
					"perf"      => $k,
					"value"     => $v,
					"perfstate" => $perf_statetext,
					"warn_min"  => $warn_min,
					"warn_max"  => $warn_max,
					"warn"      => $warn,
					"crit_min"  => $crit_min,
					"crit_max"  => $crit_max,
					"crit"      => $crit,
				);
				my @sorted = sort_by_rules %var, $sortrules_of_perf;
				@sorted = ("__Dropped__") unless @sorted;
				foreach my $alertqueue ( @sorted ){
					push @{ $$sortedevents{$alertqueue}->{perf_events} }, \%var;
				}
			}
		}
	}
	close $h;
}

sub load_and_sort_events ($$$$) {
	my ($sortedevents, $sortrules_of_host, $sortrules_of_service, $sortrules_of_perf) = @_;
	eval {
		load_and_sort_hoststate    $sortedevents, $sortrules_of_host, $sortrules_of_perf;
		load_and_sort_servicestate $sortedevents, $sortrules_of_service, $sortrules_of_perf;
	};
	if( $@ ){
		push @{ $$sortedevents{__NaemonLiveStatus__}->{host_events} }, {
			"host_groups" => [],
			"host" => "__localhost__",
			"state" => "Critical",
			"message" => $@,
		};
	}
}

sub new_sortedevents (@) {
	my (@alertgroup) = @_;
	push @alertgroup, "__Dropped__", "__NaemonLiveStatus__";
	my %sortedevents;
	foreach my $alertgroup ( @alertgroup ){
		next if defined $sortedevents{$alertgroup};
		$sortedevents{$alertgroup} = {};
	}
	return \%sortedevents;
}

sub write_sortedevents ($$) {
	my ($sortedevents, $timestamp) = @_;
	while( my ($alertgroup, $eventbasket) = each %$sortedevents ){
		write_eventbasket $alertgroup, $timestamp, $eventbasket;
	}
}

sub parse_downsampling_rule($\@\@) {
	my ($rule, $list_of_time_range, $list_of_time_unit) = @_;
	return unless $rule =~ m"^(\d+:\d+)(,\d+:\d+)*$";
	@$list_of_time_range = ();
	@$list_of_time_unit = ();
	foreach my $entry ( split m",", $rule ){
		my ($time_range_min, $time_unit_min) = split m":", $entry;
		push @$list_of_time_range, $time_range_min*60;
		push @$list_of_time_unit,  $time_unit_min*60;
	}
}

sub downsample_eventqueues ($@) {
	my ($rules, @alertgroups) = @_;
	my $now = time;

	foreach my $alertgroup ( @alertgroups ){

		my $reportparam = get_report_param $rules, $alertgroup;
		my @time_range = ( 1800, 21600, 172800, 604800 );
		my @time_unit  = (   60,   300,   1800,  10800 );
		parse_downsampling_rule $$reportparam{DOWNSAMPLING_RULE}, @time_range, @time_unit;
		my @keep;
		my @drop;

		my @entry = list_eventbasket $alertgroup;
		foreach my $e ( @entry ){
			my $unixtime = $$e{unixtime};
			my $diff = $now - $unixtime;

			my $level = 0;
			while( $level < @time_range ){
				last if $diff < $time_range[$level];
				$level++;
			}

			unless( $level < @time_range ){
				push @drop, $e;
				next;
			}

			my $time_unit = $time_unit[$level];
			my $index = int($now / $time_unit) - int($unixtime / $time_unit);
			next if $index < 0;
			unless( defined $keep[$level]->[$index] ){
				$keep[$level]->[$index] = $e;
				next;
			}

			if( $keep[$level]->[$index]->{unixtime} < $unixtime ){
				push @drop, $e;
			}else{
				push @drop, $keep[$level]->[$index];
				$keep[$level]->[$index] = $e;
			}
		}

		foreach my $e ( @drop ){
			unlink_eventbasket $alertgroup, $$e{timestamp};
		}
	}
}

#### template functions

sub tmplfunc_match {
	my ($text, $re) = @_;
	my @r = $text =~ m"$re";
	if   ( @r == 0 ){ return undef; }
	elsif( @+ == 1 ){ return [$&]; }
	else            { return [$&, @r]; }
}

sub tmplfunc_sub {
	my ($text, $re, $replace) = @_;
	$text =~ s/$re/$replace/;
	return $text;
}

sub tmplfunc_gsub {
	my ($text, $re, $replace) = @_;
	$text =~ s/$re/$replace/g;
	return $text;
}

sub tmplfunc_split {
	my ($text, $re) = @_;
	return split m"$re", $text;
}

sub tmplfunc_safesprintf {
	my ($format, @args) = @_;
	return safesprintf $format, @args;
}

sub tmplfunc_urlencode {
	my ($text) = @_;
	return uri_escape $text;
}

sub tmplfunc_localtime {
	my ($unixtime) = @_;
	return mktimestamp $unixtime;
}

sub tmplfunc_obj2json {
	#my ($obj) = @_;
	#my $json = $JSON->encode( $obj );
	#return $json;
}

sub generate_by_template ($%) {
	my ($templatename, %vars) = @_;
	my $tt = Template->new({}) or return undef;
	$vars{match}  //= \&tmplfunc_match;
	$vars{sub}    //= \&tmplfunc_sub;
	$vars{gsub}   //= \&tmplfunc_gsub;
	$vars{split}  //= \&tmplfunc_split;
	$vars{safesprintf} //= \&tmplfunc_safesprintf;
	$vars{urlencode} //= \&tmplfunc_urlencode;
	$vars{localtime} //= \&tmplfunc_localtime;
	$vars{obj2json} //= \&tmplfunc_obj2json;

	my $f = "$main::CONFDIR/reporter/alertqueue_$templatename.tt";
	open my $h, "<", $f or die "$f: cannot open, stopped";
	my $template = join "", <$h>;
	close $h;

	my $output;
	$tt->process( \$template, \%vars, \$output ) or do {
		print STDERR "$f: ", $tt->error(), "\n";
		return $template;
	};
	return $output;
}


####

1;


