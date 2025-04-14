#!/usr/bin/perl

package ncrtmaster_alertqueue;

use Exporter import;
our @EXPORT = (
	"read_rules",
	"ns",
	"nB",
	"timestamp",
	"safesprintf",
	"openlog",
	"debuglog",
	"errorlog",
	"var2ltsv",
	"ltsv2var",
	"path_encode",
	"path_decode ",
	"expand_named_placeholders",
	"system_or_die",
	"mkdir_or_die",
	"list_eventqueue",
	"list_eventbasket",
	"write_eventbasket",
	"unlink_eventbasket",
	"read_alertid",
	"write_alertid",
	"remove_alertid",
	"sort_by_rules",
	"open_livestatus_socket",
	"get_and_sort_hoststate",
	"get_and_sort_servicestate",
	"new_sortedevents",
	"write_sortedevents",
	"cleanup_eventqueues",
);

use strict;
use Socket;
use Encode;
use JSON::XS;
use Time::Local;

our $DEBUG;
our $JSON = JSON::XS->new->utf8;
our $LIVESTATUS_SOCKET = "/var/cache/naemon/live";

#### load global conf.

sub read_rules () {
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

####
sub ns ($) {
	return sprintf "%.2fs", $_[0];
}

sub nB ($) {
	return sprintf "%dB", $_[0];
}

####
sub timestamp (;$) {
	my $t = shift // time;
	my ($sec, $min, $hour, $day, $mon, $year) = localtime $t;
	return sprintf "%04d-%02d-%02d_%02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
}

sub safesprintf ( @ ){
	my ($format, @args) = @_;
	my $text = sprintf $format, @args;
	$text =~ s{([\x00-\x1f\x7f])}{"\\x" . unpack('H2', $1);}eg;
	return $text;
}

our $LOG_HANDLE;
sub openlog () {
	open $LOG_HANDLE, '>>', "$main::WORKDIR/servicegroup.log" or return;
	my $old = select $LOG_HANDLE;
	$| = 1;
	select $old;
}

sub debuglog ( $;@ ){
	return unless $DEBUG;
	openlog unless defined $LOG_HANDLE;
	print $LOG_HANDLE timestamp(time), " ", safesprintf(@_), "\n";
}

sub errorlog ( $;@ ){
	openlog unless defined $LOG_HANDLE;
	print $LOG_HANDLE timestamp(time), " ", safesprintf(@_), "\n";
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

sub list_eventqueue () {
	my @r;
	my $f = "$main::WORKDIR/aq_event";
	opendir my $h, $f or die "$f: cannot open, stopped";
	while( my $e = readdir $h ){
		next unless $e =~ m"^([a-zA-Z][.-\w]*)$";
		push @r, $1;
	}
	close $h;
	return @r;
}

sub list_eventbasket ($) {
	my ($alertgroup) = @_;
	my @r;
	my $f = "$main::WORKDIR/aq_event/$alertgroup";
	opendir my $h, $f or die "$f: cannot open, stopped";
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
	mkdir_or_die $d unless -d $d;
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	my $json = $JSON->encode( $eventbasket );
	print $h encode_utf8($json);
	close $h;
}

sub unlink_eventbasket ($$) {
	my ($alertgroup, $timestamp) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup/$timestamp.json";
	unlink $f;
}

####

sub read_alertid ($) {
	my ($alertgroup) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup.json";
	return unless -f $f;
	open my $h, "<", $f or die "$f: cannot open, stopped";
	my $json = join "", <$h>;
	close $h;
	return eval { $JSON->decode( $json ); };
}

sub write_alertid ($$$$) {
	my ($alertgroup, $uuid, $creation_unixtime, $creation_timestamp) = @_;
	my $f = "$main::WORKDIR/aq_event/$alertgroup.json";
	open my $h, ">", $f or die "$f: cannot open, stopped";
	print $h $JSON->encode( {
		"uuid" => $uuid,
		"creation_unixtime"  => $creation_unixtime,
		"creation_timestamp" => $creation_timestamp,
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

sub get_and_sort_hoststate ($$) {
	my ($sortedevents, $sortrules_of_host) = @_;
	# TODO
}

sub get_and_sort_servicestate ($$$) {
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
		my @service_groups = split m"\s+", $service_groups;

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
			@sorted = ("Dropped") unless @sorted;
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
				@sorted = ("Dropped") unless @sorted;
				foreach my $alertqueue ( @sorted ){
					push @{ $$sortedevents{$alertqueue}->{perf_events} }, \%var;
				}
			}
		}
	}
	close $h;
}

sub new_sortedevents (@) {
	my (@alertgroup) = @_;
	push @alertgroup, "Dropped";
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

sub cleanup_eventqueues (@) {
	my (@alertgroups) = @_;
	my $now = time;

	foreach my $alertgroup ( @alertgroups ){

		my @expiration = ( 3600, 86400, 604800 );
		my @range      = (   60,  1800,  10800 );
		my @keep;
		my @drop;

		my @entry = list_eventbasket $alertgroup;
		foreach my $e ( @entry ){
			my $unixtime = $$e{unixtime};
			my $diff = $now - $unixtime;

			my $level = 0;
			while( $level < @expiration ){
				last if $diff < $expiration[$level];
				$level++;
			}

			unless( $level < @expiration ){
				push @drop, $e;
				next;
			}

			my $range = $range[$level];
			my $index = int($now / $range) - int($unixtime / $range);
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


1;

