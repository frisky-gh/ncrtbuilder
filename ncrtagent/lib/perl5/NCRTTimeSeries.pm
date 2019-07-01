package NCRTTimeSeries;

use strict;

sub timestamp ($) {
	my ($sec, $min, $hour, $day, $mon, $year) = localtime shift;
	return sprintf "%04d-%02d-%02d_%02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
}

sub var2ltsv ( \% ){
	my ($var) = @_;
	my @ltsv;
	push @ltsv, "timestamp:".$var->{timestamp} if defined $var->{timestamp};
	push @ltsv, "timestamp_unix:".$var->{timestamp_unix} if defined $var->{timestamp_unix};
	foreach my $k ( sort {$a cmp $b} keys %$var ){
		next if $k eq 'timestamp';
		next if $k eq 'timestamp_unix';
		push @ltsv, "$k:".$var->{$k};
	}
	return join "\t", @ltsv;
}

sub ltsv2var ( $ ){
	my ($ltsv) = @_;
	my %var;
	foreach my $kv ( split m"\t", $ltsv ){
		$kv =~ m"^([-./\[\]\w]+):(.*)$" or do {
			next;
		};
		my $k = $1;
		my $v = $2;
		$var{$k} = $v;
	}
	return %var;
}

sub calc_delta ($$\%) {
	my ($f, $longterm_h, $curr) = @_;
	my @history;

	my $now = time;
	my $longterm_limit  = $now - $longterm_h * 60 * 60;
	my $shortterm_limit = $now - 59;

	# load history
	if( open my $h, '<', $f ){
		while( <$h> ){
			chomp;
			my %v = ltsv2var $_;
			push @history, \%v;
		}
		close $h;
	}

	# search origin
	my $shortterm_origin;
	foreach my $e ( @history ){
		last	if $e->{timestamp} > $shortterm_limit;
		$shortterm_origin = $e;
	}
	my $longterm_origin;
	foreach my $e ( @history ){
		last	if $e->{timestamp} > $shortterm_limit;
		last	if $e->{timestamp} > $longterm_limit and
			defined $longterm_origin;
		$longterm_origin = $e;
	}

	# store history
	open my $h, '>', "$f.$$" or do {
		die "$f.$$: cannot open, stopped";
	};
	push @history, { 'timestamp' => $now,  %$curr };
	foreach my $e ( @history ){
		next if $e->{timestamp} < $longterm_limit;
		print $h var2ltsv( %$e ), "\n";
	}
	close $h;
	unlink $f;
	rename "$f.$$", $f;

	# calc difference
	my %shortterm_delta;
	if( $shortterm_origin ){
		my $deltat = $now - $shortterm_origin->{timestamp};
		while( my ($k, $v) = each %$curr ){
			my $v2 = $shortterm_origin->{$k} // next;
			$shortterm_delta{$k} = ($v - $v2) / $deltat;
		}
	}
	my %longterm_delta;
	if( $longterm_origin ){
		my $deltat = $now - $longterm_origin->{timestamp};
		while( my ($k, $v) = each %$curr ){
			my $v2 = $longterm_origin->{$k} // next;
			$longterm_delta{$k} = ($v - $v2) / $deltat;
		}
	}

	return \%shortterm_delta, \%longterm_delta;
}

sub load_timeseries ($$$) {
	my ($ts, $name, $dir) = @_;
	# load history
#TODO
	my $f = "$dir/$name.timeseries";
	if( open my $h, '<', $f ){
		while( <$h> ){
			chomp;
			my %v = ltsv2var $_;
			push @$ts, \%v;
		}
		close $h;
	}
	return;
}

sub add_timeseries ($$) {
	my ($ts, $hash) = @_;
	my $timestamp_unix = time;
	my $timestamp = timestamp $timestamp_unix;
	push @$ts, {
		'timestamp_unix' => $timestamp_unix,
		'timestamp'      => $timestamp,
		%$hash
	};
}

sub store_timeseries ($$$$) {
	my ($ts, $name, $dir, $timespan) = @_;
	my $oldest = time - $timespan;
	my $f = "$dir/$name.timeseries";
	open my $h, '>', "$f.$$" or do {
		die "$f.$$: cannot open, stopped";
	};
	foreach my $e ( @$ts ){
		next if $e->{timestamp_unix} < $oldest;
		print $h var2ltsv( %$e ), "\n";
	}
	close $h;
	unlink $f;
	rename "$f.$$", $f;
}

sub new_timeseries () {
	return [];
}

####

#my $longterm = sprintf "%dH", $LONGTERM_H;
#my ($shortd, $longd) = calc_delta "$WORKDIR/osperf_cpu.history", $LONGTERM_H, %curr;
#my $shortterm_jiffies = $shortd->{user} + $shortd->{system} + $shortd->{iowait} + $shortd->{idle};
#my $longterm_jiffies  = $longd->{user} + $longd->{system} + $longd->{iowait} + $longd->{idle};
#foreach my $i ( 'user', 'system', 'iowait', 'idle' ){
#	$m{"cpu-${i}-pct"} = nP 100 * $shortd->{$i} / $shortterm_jiffies
#		if $shortterm_jiffies > 0;
#	$m{"cpu-${i}-longtermavg[$longterm]-pct"} = nP 100 * $longd->{$i} / $longterm_jiffies
#		if $longterm_jiffies > 0;
#}

*main::new_timeseries = \&new_timeseries;
*main::load_timeseries = \&load_timeseries;
*main::store_timeseries = \&store_timeseries;
*main::add_timeseries = \&add_timeseries;

1;

