#!/usr/bin/perl

package NCRTAlertQueue::Stats;

use Exporter import;
our @EXPORT = (
	'create_new_stats',
	'compute_stats_in_range',
	'output_stats_summary',
	'list_perf_moids_of_stats',
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

sub analyze_host_events ($$) {
	my ($events, $stats) = @_;

	foreach my $e ( @$events ){
		my $host = $$e{host};
		my $state = $$e{state};
		next if $state eq "";

		# update most severe state
		my $last_state = $$stats{$host}->{most_severe_state};
		if    ( $last_state eq "" ){
			$$stats{$host}->{most_severe_state} = $state;
		}elsif( $last_state eq "Warning" ){
			if( $state eq "Critical" ){
				$$stats{$host}->{most_severe_state} = $state;
			}
		}elsif( $last_state eq "Critical" ){
		}else{
			$$stats{$host}->{most_severe_state} = $state;
		}
	}
}

sub analyze_service_events ($$) {
	my ($events, $stats) = @_;

	foreach my $e ( @$events ){
		my $host    = $$e{host};
		my $service = $$e{service};
		my $state = $$e{state};
		next if $state eq "";

		# update most severe state
		my $last_state = $$stats{$host}->{$service}->{most_severe_state};
		if    ( $last_state eq "" ){
			$$stats{$host}->{$service}->{most_severe_state} = $state;
		}elsif( $last_state eq "Warning" ){
			if( $state eq "Critical" ){
				$$stats{$host}->{$service}->{most_severe_state} = $state;
			}
		}elsif( $last_state eq "Critical" ){
		}else{
			$$stats{$host}->{$service}->{most_severe_state} = $state;
		}
	}
}

sub analyze_perf_events ($$) {
	my ($events, $stats) = @_;

	foreach my $e ( @$events ){
		my $host    = $$e{host};
		my $service = $$e{service};
		my $perf    = $$e{perf};
		my $value   = $$e{value};
		my $state     = $$e{state};
		my $perfstate = $$e{perfstate};

		# update most severe state
		if( $state ne "" ){
			my $last_state = $$stats{$host}->{$service}->{$perf}->{most_severe_state};
			if    ( $last_state eq "" ){
				$$stats{$host}->{$service}->{$perf}->{most_severe_state} = $state;
			}elsif( $last_state eq "Warning" ){
				if( $state eq "Critical" ){
					$$stats{$host}->{$service}->{$perf}->{most_severe_state} = $state;
				}
			}elsif( $last_state eq "Critical" ){
			}else{
				$$stats{$host}->{$service}->{$perf}->{most_severe_state} = $state;
			}
		}

		# update max / min values
		if    ( $perfstate eq "under_warn" || $perfstate eq "under_crit" ){
			my $last_min = $$stats{$host}->{$service}->{$perf}->{min};
			if    ( $last_min eq "" ){
				$$stats{$host}->{$service}->{$perf}->{min} = $value;
			}elsif( $last_min < $value ){
				$$stats{$host}->{$service}->{$perf}->{min} = $value;
			}
		}elsif( $perfstate eq "over_warn"  || $perfstate eq "over_crit" ){
			my $last_max = $$stats{$host}->{$service}->{$perf}->{max};
			if    ( $last_max eq "" ){
				$$stats{$host}->{$service}->{$perf}->{max} = $value;
			}elsif( $last_max > $value ){
				$$stats{$host}->{$service}->{$perf}->{max} = $value;
			}
		}
	}
}

sub convert_eventbasket_to_moid2event ($$$) {
	my ($alertgroup, $unixtime, $eventbasket) = @_;
	my %r;
	foreach my $eventlist ( values %$eventbasket ){
		foreach my $event ( @$eventlist ){
			my $host    = $$event{host};
			my $service = $$event{service};
			my $perf    = $$event{perf};
			my $monitoring_object_id;
			my $monitoring_object_type;
			if( defined $perf ){
				$monitoring_object_id = "$host $service $perf";
				$monitoring_object_type = "perf";
			}elsif( defined $service ){
				$monitoring_object_id = "$host $service";
				$monitoring_object_type = "service";
			}else{
				$monitoring_object_id = $host;
				$monitoring_object_type = "host";
			}
			$$event{moid}   = $monitoring_object_id;
			$$event{motype} = $monitoring_object_type;
			$$event{alertgroup} = $alertgroup;
			$$event{unixtime} = $unixtime;
			$r{$monitoring_object_id} = $event;
		}
	}
	return %r;
}

sub add_changelogs (\@\%$\%) {
	my ($changelogs_of_all_mos, $moid2lastevent, $unixtime, $moid2event) = @_;
	my @added;
	my @removed;
	while( my ($moid, $lastevent) = each %$moid2lastevent ){
		push @removed, $moid unless exists $$moid2event{$moid};
	}
	while( my ($moid, $event) = each %$moid2event ){
		push @added, $moid unless exists $$moid2lastevent{$moid};
	}

	foreach my $moid ( @added ){
		my $e = $$moid2event{$moid};
		push @$changelogs_of_all_mos, {
			%$e,
			'unixtime' => $unixtime,
			'old_state' => 'Ok',
			'state' => $$e{state},
		};
	}
	foreach my $moid ( @removed ){
		my $e = $$moid2lastevent{$moid};
		push @$changelogs_of_all_mos, {
			%$e,
			'unixtime' => $unixtime,
			'old_state' => $$e{state},
			'state' => 'Ok',
		};

	}

	while( my ($moid, $event) = each %$moid2event ){
		next unless exists $$moid2lastevent{$moid};
		my $lastevent = $$moid2lastevent{$moid};
		my $curr_state = $$event{state};
		my $last_state = $$lastevent{state};
		next if $curr_state eq $last_state;

		push @$changelogs_of_all_mos, {
			%$event,
			'unixtime' => $unixtime,
			'old_state' => $last_state,
			'state' => $curr_state,
		};
	}
}

sub update_summary_stats (\%\%) {
	my ($moid2stats, $moid2event) = @_;

	while( my ($moid, $event) = each %$moid2event ){
		my $stats = $$moid2stats{$moid};
		unless( defined $stats ){
			$stats = {
				'moid'   => $moid,
				'motype' => $$event{motype},
				'alertgroup' => $$event{alertgroup},
				'highest_severity' => 'Ok',
			};
			$$stats{host}    = $$event{host}    if defined $$event{host};
			$$stats{service} = $$event{service} if defined $$event{service};
			$$stats{perf}    = $$event{perf}    if defined $$event{perf};

			$$moid2stats{$moid} = $stats;
		}

		my $highest_severity  = $$stats{max_severity};
		my $curr_severity = $$event{state};
		if    ( $highest_severity eq 'Ok' ){
			$$stats{highest_severity} = $curr_severity;
		}elsif( $highest_severity eq 'Warning' ){
			if( $curr_severity eq 'Critical' ){
				$$stats{highest_severity} = $curr_severity;
			}
		}elsif( $highest_severity eq 'Critical' ){
		}else{
			$$stats{highest_severity} = $curr_severity;
		}
		
		my $highest_value = $$stats{highest_value};
		my $lowest_value = $$stats{lowest_value};
		my $curr_value = $$event{value};
		if( defined $curr_value ){
			if    ( ! defined $highest_value ){
				$$stats{highest_value} = $curr_value;
			}elsif( $highest_value < $curr_value ){
				$$stats{highest_value} = $curr_value;
			}

			if    ( ! defined $lowest_value ){
				$$stats{lowest_value} = $curr_value;
			}elsif( $lowest_value > $curr_value ){
				$$stats{lowest_value} = $curr_value;
			}
		}
	}
}

sub select_only_hosts_from_list        (\@) {
	my ($list) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "host" } @$list;
}

sub select_only_services_from_list     (\@) {
	my ($list) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "service" } @$list;
}

sub select_only_perfs_from_list        (\@) {
	my ($list) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "perf" } @$list;
}

sub select_from_list_group_by_hosts    (\@) {
	my ($list) = @_;
	my %r;
	foreach my $i ( @$list ){
		next unless $$i{motype} eq "host";
		my $host = $$i{host};
		push @{ $r{$host} }, $i;
	}
	return %r;
}

sub select_from_list_group_by_services (\@) {
	my ($list) = @_;
	my %r;
	foreach my $i ( @$list ){
		next unless $$i{motype} eq "service";
		my $host = $$i{host};
		my $service = $$i{service};
		push @{ $r{$host}->{$service} }, $i;
	}
	return %r;
}

sub select_from_list_group_by_perfs    (\@) {
	my ($list) = @_;
	my %r;
	foreach my $i ( @$list ){
		next unless $$i{motype} eq "perf";
		my $host = $$i{host};
		my $service = $$i{service};
		my $perf = $$i{perf};
		push @{ $r{$host}->{$service}->{$perf} }, $i;
	}
	return %r;
}

sub select_from_hash_group_by_hosts    (\%) {
	my ($hash) = @_;
	my %r;
	foreach my $i ( values %$hash ){
		next unless $$i{motype} eq "host";
		my $host = $$i{host};
		$r{$host} = $i;
	}
	return %r;
}

sub select_from_hash_group_by_services (\%) {
	my ($hash) = @_;
	my %r;
	foreach my $i ( values %$hash ){
		next unless $$i{motype} eq "service";
		my $host = $$i{host};
		my $service = $$i{service};
		$r{$host}->{$service} = $i;
	}
	return %r;
}

sub select_from_hash_group_by_perfs    (\%) {
	my ($hash) = @_;
	my %r;
	foreach my $i ( values %$hash ){
		next unless $$i{motype} eq "perf";
		my $host = $$i{host};
		my $service = $$i{service};
		my $perf = $$i{perf};
		$r{$host}->{$service}->{$perf} = $i;
	}
	return %r;
}

sub select_only_hosts_from_hash    (\%) {
	my ($hash) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "host" }    values %$hash;
}

sub select_only_services_from_hash (\%) {
	my ($hash) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "service" } values %$hash;
}

sub select_only_perfs_from_hash    (\%) {
	my ($hash) = @_;
	return sort { $$a{moid} cmp $$b{moid} } grep { $$_{motype} eq "perf" }    values %$hash;
}

####

sub create_new_stats ($) {
	my ($alertgroup) = @_;

	return {
		'alertgroup' => $alertgroup,

		'changelogs_of_all_mos' => [],
		'moid2stats'            => {},
		'moid2lastevent'        => {},
	};
}

sub compute_stats_in_range ($$$) {
	my ($stats, $start_unixtime, $end_unixtime) = @_;
	my $alertgroup = $$stats{alertgroup};

	my @names = list_eventbasket $alertgroup;
	my @sorted_names = sort { $$a{unixtime} <=> $$b{unixtime} } @names;

	my %moid2stats;
	my %moid2lastevent;
	my @changelogs_of_all_mos;
	foreach my $i ( @sorted_names ){
		my $unixtime  = $$i{unixtime};
		my $timestamp = $$i{timestamp};
		next unless $start_unixtime <= $unixtime && $unixtime <= $end_unixtime;

		my $eventbasket = read_eventbasket $alertgroup, $timestamp;
		my %moid2event = convert_eventbasket_to_moid2event $alertgroup, $unixtime, $eventbasket;
		add_changelogs @changelogs_of_all_mos, %moid2lastevent, $unixtime, %moid2event;
		update_summary_stats %moid2stats, %moid2event;
		%moid2lastevent = %moid2event;
	}

	$$stats{changelogs_of_all_mos} = \@changelogs_of_all_mos;
	$$stats{moid2stats}            = \%moid2stats;
	$$stats{moid2lastevent}        = \%moid2lastevent;
}

sub output_stats_summary ($) {
	my ($stats) = @_;
	my $changelogs_of_all_mos = $$stats{changelogs_of_all_mos};
	my $moid2stats            = $$stats{moid2stats};
	my $moid2lastevent        = $$stats{moid2lastevent};

	my %r;
	$r{STORY_OF_ALL_HOSTS}      = [select_only_hosts_from_list        @$changelogs_of_all_mos];
	$r{STORY_OF_ALL_SERVICES}   = [select_only_services_from_list     @$changelogs_of_all_mos];
	$r{STORY_OF_ALL_PERFS}      = [select_only_perfs_from_list        @$changelogs_of_all_mos];
	$r{STATS_OF_HOST_EVENTS}    = {select_from_list_group_by_hosts    @$changelogs_of_all_mos};
	$r{STATS_OF_SERVICE_EVENTS} = {select_from_list_group_by_services @$changelogs_of_all_mos};
	$r{STATS_OF_PERF_EVENTS}    = {select_from_list_group_by_perfs    @$changelogs_of_all_mos};

	$r{FIRED_HOSTS_IN_HASH_FORM}     = {select_from_hash_group_by_hosts    %$moid2stats};
	$r{FIRED_SERVICES_IN_HASH_FORM}  = {select_from_hash_group_by_services %$moid2stats};
	$r{FIRED_PERFS_IN_HASH_FORM}     = {select_from_hash_group_by_perfs    %$moid2stats};
	$r{FIRED_HOSTS_IN_LIST_FORM}     = [select_only_hosts_from_hash        %$moid2stats];
	$r{FIRED_SERVICES_IN_LIST_FORM}  = [select_only_services_from_hash     %$moid2stats];
	$r{FIRED_PERFS_IN_LIST_FORM}     = [select_only_perfs_from_hash        %$moid2stats];

	$r{FIRING_HOSTS_IN_HASH_FORM}    = {select_from_hash_group_by_hosts    %$moid2lastevent};
	$r{FIRING_SERVICES_IN_HASH_FORM} = {select_from_hash_group_by_services %$moid2lastevent};
	$r{FIRING_PERFS_IN_HASH_FORM}    = {select_from_hash_group_by_perfs    %$moid2lastevent};
	$r{FIRING_HOSTS_IN_LIST_FORM}    = [select_only_hosts_from_hash        %$moid2lastevent];
	$r{FIRING_SERVICES_IN_LIST_FORM} = [select_only_services_from_hash     %$moid2lastevent];
	$r{FIRING_PERFS_IN_LIST_FORM}    = [select_only_perfs_from_hash        %$moid2lastevent];

	return %r;
}

sub list_perf_moids_of_stats ($) {
	my ($stats) = @_;
	my $moid2stats = $$stats{moid2stats};
	my @perfs = select_only_perfs_from_hash %$moid2stats;
	my @moids = map { $$_{moid} } @perfs;
	return sort @moids;
}


####

1;


