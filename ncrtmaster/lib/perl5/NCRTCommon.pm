####
package NCRTCommon;

use strict;
use Exporter 'import';
use IPC::Open2;
use NCRTStackMachine;
use NCRTTimeSeries;

our @EXPORT = (
	'generate_metrics_from_mastermeasure',
	'generate_metrics_from_agentmaesure',
	'generate_metrics_from_commandline_args',
	'pass_through_filters',
	'evaluate_values',
	'generate_thresholds',
	'generate_detection_results',
);

sub generate_metrics_from_mastermeasure ($$$) {
	my ($measure, $host, $service) = @_;

	my $f = "$main::PLUGINSDIR/ncrtmastermeasure_$measure";
	open my $h, '-|', "$f $main::CONFDIR $main::WORKDIR $measure $host $service" or do {
		print "UNKNOWN $f: not found.\n";
		exit 3;
	};

	my %metrics;
	my @output;
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		die "$_, stopped" unless m"^([-\w/\[\].:@\$%#\*]+)=(\S+)$";
		my $k = $1;
		my $v = $2;
		if( $k eq 'output' ){ push @output, $v; }
		else                { $metrics{$k} = $v; }
	}
	close $h;

	my $plugin_rc = $? >> 8;
	$main::PLUGIN_HAS_FAILED = 1 if $plugin_rc > 0;

	return %metrics;
}

sub generate_metrics_from_agentmeasure ($$$) {
	my ($measure, $host, $service) = @_;

	my $f = "$main::PLUGINSDIR/ncrtagentmeasure_$measure";
	open my $h, '-|', "$f $main::CONFDIR $main::WORKDIR $measure $host $service" or do {
		print "UNKNOWN $f: not found.\n";
		exit 3;
	};

	my %metrics;
	my @output;
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		die "$_, stopped" unless m"^([-\w/\[\].:@\$%#\*]+)=(\S+)$";
		my $k = $1;
		my $v = $2;
		if( $k eq 'output' ){ push @output, $v; }
		else                { $metrics{$k} = $v; }
	}
	close $h;

	my $plugin_rc = $? >> 8;
	$main::PLUGIN_HAS_FAILED = 1 if $plugin_rc > 0;

	return %metrics;
}

sub generate_metrics_from_commandline_args ($$$@) {
	my ($measure, $host, $service, @args) = @_;

	my $import_host;
	my $import_service;
	my $import_prefix;
	my %m1;
	foreach my $i ( @args ){
		foreach my $j ( split m"\s+", $i ){
			if    ( $j =~ m"^([^\s=:]+):([^\s=:]+):([^\s=:]*)$" ){
				$import_host = $1;
				$import_service = $2;
				$import_prefix = $3;
			}elsif( $j =~ m"^([^\s=]+)=([-+]?\d+(\.\d+)?)(\w{1,2}|%)?(;\S+)?$" ){
				my $key = $1;
				my $value = $2;
				$m1{"$import_prefix$key"} = $value;
			}else{
				print "parse error: \"$j\", stopped\n";
				exit 3;
			}
		}
	}
	return %m1;
}

sub pass_through_filters ($$$$%) {
	my ($measure, $host, $service, $filtertype, %metrics) = @_;

	my $f = "$main::CONFDIR/$filtertype/$filtertype.$host.$service";

	my @filters;
	if( open my $h, '<', $f ){
		while( <$h> ){
			chomp;
			push @filters, $_;
		}
		close $h;
	}
	if( @filters == 0 ){
		return %metrics;
	}
	
	foreach my $filter ( @filters ){
		my $f = "$main::FILTERSDIR/$filter";
		open2 my $out, my $in, "$f $main::CONFDIR $main::WORKDIR $measure $host $service" or do {
			print "UNKNOWN $f: not found.\n";
			exit 3;
		};

		while( my ($k, $v) = each %metrics ){
			print $in "$k=$v\n";
		}
		close $in;

		%metrics = ();
		my @output;
		while( <$out> ){
			chomp;
			next if m"^\s*(#|$)";
			die "$_, stopped" unless m"^([-\w/\[\].:@\$%#\*]+)=(\S+)$";
			my $k = $1;
			my $v = $2;
			if( $k eq 'output' ){ push @output, $v; }
			else                { $metrics{$k} = $v; }
		}
		close $out;

		my $plugin_rc = $? >> 8;
		$main::PLUGIN_HAS_FAILED = 1 if $plugin_rc > 0;

	}
	return %metrics;
}

sub evaluate_values ($$$%) {
	my ($measure, $host, $service, %values) = @_;

	my $memory = new_memory;
	$memory->{VALUES} = \%values;
	$memory->{TIMESERIES} = \%values;

	foreach my $k ( sort keys %values ){
		my $v = $values{$k};
		next if $v =~ m"^([-+]?\d+(?:\.\d+)?)([%a-zA-Z]*)$";
		eval {
			my @stack = evaluate_expr $memory, $v;
			$v = pop @stack;
			$values{$k} = $v;
		};
		if( $@ ){
			print "UNKNOWN: $@\n";
			exit 3;
		}
	}
	return %values;
}

sub generate_thresholds ($$$%) {
	my ($measure, $host, $service, %metrics) = @_;
	my @warn_rules;
	my @crit_rules;

	# load threshold rules
	my $f = "$main::CONFDIR/threshold/thresholds.$host.$service";
	if( open my $h, '<', $f ){
		while( <$h> ){
			chomp;
			next if m"^\s*(#|$)";
			die unless m"^(\S+)\s+(crit|warn)\s+\[\s*([-+]?\d+(?:\.\d+)?)\s*,\s*([-+]?\d+(?:\.\d+)?)\s*\]$";
			my $itempattern = qr"^$1$";
			my $severity = $2;
			my $lower = $3;
			my $upper = $4;
			if    ( $severity eq 'crit' ){
				push @crit_rules, [ $itempattern, $lower, $upper ];
			}elsif( $severity eq 'warn' ){
				push @warn_rules, [ $itempattern, $lower, $upper ];
			}
		}
		close $h;
	}

	# thresholds are generated from metrics
	my %thresholds;
	foreach my $k ( keys %metrics ){
		foreach my $r ( @warn_rules ){
			my ($re, $lower, $upper) = @$r;
			next unless $k =~ $re;
			$thresholds{"$k.warn_lower"} = $lower;
			$thresholds{"$k.warn_upper"} = $upper;
		}
		foreach my $r ( @crit_rules ){
			my ($re, $lower, $upper) = @$r;
			next unless $k =~ $re;
			$thresholds{"$k.crit_lower"} = $lower;
			$thresholds{"$k.crit_upper"} = $upper;
		}
	}

	return %metrics, %thresholds;
}

sub generate_detection_results ($$$%) {
	my ($measure, $host, $service, %thresholds) = @_;
	my %metrics;
	my %warn_thresholds;
	my %crit_thresholds;
	while( my ($k, $v) = each %thresholds ){
		if    ( $k =~ m"\.warn_lower$" ){
			$warn_thresholds{$k}->[0] = $v;
		}elsif( $k =~ m"\.warn_upper$" ){
			$warn_thresholds{$k}->[1] = $v;
		}elsif( $k =~ m"\.crit_lower$" ){
			$crit_thresholds{$k}->[0] = $v;
		}elsif( $k =~ m"\.crit_upper$" ){
			$crit_thresholds{$k}->[1] = $v;
		}else{
			$metrics{$k} = $v;
		}
	}

	my (@p, @c, @w);
	foreach my $k ( sort keys %metrics ){
		my $v = $metrics{$k};
		my ($min, $max);
	
		next unless $v =~ m"^([-+]?\d+(?:\.\d+)?)(.*)$";
		my $value = $1;
		my $unit = $2;
		if   ( $unit eq '%' ) { $min = '0.00'; $max = '100.00'; }
		elsif( $unit eq 'MB' ){ $min = '0.00'; }
		my $key_text = $unit ? "$k\[$unit\]" : "$k";

		my $c;
		if( $crit_thresholds{$k} ){
			my ($lower, $upper) = @{$crit_thresholds{$k}};
			$c = "$lower:$upper";
			if    ( $v < $lower ){
				push @c, "$key_text:${value}(lower-crit-thr:$lower)";
			}elsif( $v > $upper ){
				push @c, "$key_text:${value}(upper-crit-thr:$upper)";
			}
		}
		my $w;
		if( $warn_thresholds{$k} ){
			my ($lower, $upper) = @{$warn_thresholds{$k}};
			$w = "$lower:$upper";
			if    ( @c ){
				# ignore
			}elsif( $v < $lower ){
				push @w, "$key_text:${value}(lower-warn-thr:$lower)";
			}elsif( $v > $upper ){
				push @w, "$key_text:${value}(upper-warn-thr:$upper)";
			}
		}
		my $p = "$k=$v;$w;$c;$min;$max";
		push @p, $p;
	}

	my $status = 'OK';
	my $statuscode = 0;
	if( $main::PLUGIN_HAS_FAILED ){
		$status = 'CRIT';
		$statuscode = 2;
	}
	elsif( @c ){ $status = 'CRIT'; $statuscode = 2; }
	elsif( @w ){ $status = 'WARN'; $statuscode = 1; }

	my $output = join ' / ', $status, @main::OUTPUTS, @c, @w;
	my $perfdata = join ' ', @p;
	return $statuscode, $output, $perfdata;
}

1;

