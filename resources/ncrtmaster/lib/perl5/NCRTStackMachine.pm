package NCRTStackMachine;

use strict;
use Exporter 'import';

our @EXPORT = (
	'new_memory',
	'evaluate_expr',
	'evaluate_rightvalue',
);

####
sub func_mean ($$@) {
	my ($sec, $seriesname, @ts) = @_;

	# search offset
	my $now = time;
	my $older_boundary = $now - 2 * $sec;
	my $newer_boundary = $now - $sec;
	my $offset;
	for( my $i = 0; $i < @ts; $i++ ){
		my $t = $ts[$i]->{timestamp_unix};
		next if $t < $older_boundary;
		$offset = $i unless defined $offset;
		last if $t > $newer_boundary;
		$offset = $i;
	}
	return 0 unless defined $offset;
	return 0 unless $offset + 1 < @ts;

	#
	my $last_timestamp = $ts[$offset]->{timestamp_unix};
	my $last_value     = $ts[$offset]->{$seriesname};
	my $integrated_value;
	my $integrated_sec;
	for( my $i = $offset + 1; $i < @ts; $i++ ){
		my $curr_timestamp = $ts[$i]->{timestamp_unix};
		my $curr_value     = $ts[$i]->{$seriesname};
		my $dt = $curr_timestamp - $last_timestamp;
		$integrated_value += $dt * $curr_value;
		$integrated_sec   += $dt;
		$last_timestamp = $curr_timestamp;
		$last_value     = $curr_value;
	}
	return 0 if $integrated_sec == 0;
	return $integrated_value / $integrated_sec;
}

sub func_deltat ($$@) {
	my ($sec, $seriesname, @ts) = @_;

	# search offset
	my $now = time;
	my $older_boundary = $now - 2 * $sec;
	my $newer_boundary = $now - $sec;
	my $offset;
	for( my $i = 0; $i < @ts; $i++ ){
		my $t = $ts[$i]->{timestamp_unix};
		next if $t < $older_boundary;
		$offset = $i unless defined $offset;
		last if $t > $newer_boundary;
		$offset = $i;
	}
	return 0 unless defined $offset;
	return 0 unless $offset + 1 < @ts;

	#
	my $oldest_timestamp = $ts[$offset]->{timestamp_unix};
	my $oldest_value     = $ts[$offset]->{$seriesname};
	my $newest_timestamp = $ts[-1]->{timestamp_unix};
	my $newest_value     = $ts[-1]->{$seriesname};
	return ($newest_value - $oldest_value) / ($newest_timestamp - $oldest_timestamp);
}


####
our %PRIORITY = (
	'+n' => 5,
	'-n' => 5,
	'*' => 4,
	'/' => 4,
	'+' => 3,
	'-' => 3,
	'=' => 2,
	',' => 1,
	'bracket' => 0,
);

sub evaluate_rightvalue ($$) {
	my ($memory, $v) = @_;
	my $type = $v->{type};
	if    ( $type eq "num" ){
		return $v->{value};
	}elsif( $type eq "str" ){
		return $v->{value};
	}elsif( $type eq "var" ){
		return $memory->{VAR}->{ $v->{name} };
	}
	die;
}

sub evaluate_bracket ($\@) {
	my ($memory, $stack) = @_;
	my $stack_depth = @$stack;
	for( my $i = 1; $i <= $stack_depth; ++$i ){
		my $t = $stack->[-$i]->{type};
		next unless $t eq "bracket" || $t eq "func";

		my ($bracket, @args) = splice @$stack, $stack_depth - $i;
		if( $t eq "bracket" ){
			push @$stack, $args[0];
			return;
		}

		my $func_name = $bracket->{name};
		if    ( $func_name eq 'import' ){
			my $name = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"str", value=>$memory->{IMPORT}->{$name}};
			return;
		}elsif( $func_name eq 'export' ){
			my $name  = evaluate_rightvalue $memory, shift @args;
			my $value = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"num", value=>1};
			$memory->{EXPORT}->{$name} = $value;
			return;
		}elsif( $func_name eq 'get' ){
			my $name = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"str", value=>$memory->{VALUES}->{$name}};
			return;
		}elsif( $func_name eq 'set' ){
			my $name  = evaluate_rightvalue $memory, shift @args;
			my $value = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"num", value=>1};
			$memory->{VALUES}->{$name} = $value;
			return;
		}elsif( $func_name eq 'min' ){
			my $r;
			foreach my $arg ( @args ){
				my $t = evaluate_rightvalue $memory, $arg;
				$r = $t if !defined($r) || $t < $r;
			}
			push @$stack, {type=>"num", value=>$r};
			return;
		}elsif( $func_name eq 'max' ){
			my $r;
			foreach my $arg ( @args ){
				my $t = evaluate_rightvalue $memory, $arg;
				$r = $t if !defined($r) || $t > $r;
			}
			push @$stack, {type=>"num", value=>$r};
			return;
		}elsif( $func_name eq 'timeseries_deltat' ){
			my $name = evaluate_rightvalue $memory, shift @args;
			my $sec = evaluate_rightvalue $memory, shift @args;
			my $r = func_deltat $sec, $name, @{$memory->{TIMESERIES}};
			$memory->{TIMESERIES_LIFETIME} = $sec if $memory->{TIMESERIES_LIFETIME} < $sec;
			push @$stack, {type=>"num", value=>$r};
			return;
		}elsif( $func_name eq 'timeseries_mean' ){
			my $name = evaluate_rightvalue $memory, shift @args;
			my $sec = evaluate_rightvalue $memory, shift @args;
			my $r = func_mean $sec, $name, @{$memory->{TIMESERIES}};
			$memory->{TIMESERIES_LIFETIME} = $sec if $memory->{TIMESERIES_LIFETIME} < $sec;
			push @$stack, {type=>"num", value=>$r};
			return;
		}elsif( $func_name eq 'n' ){
			my $r = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"str", value=>sprintf("%.2f", $r)};
			return;
		}elsif( $func_name eq 'nP' ){
			my $r = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"str", value=>sprintf("%.2f%%", $r)};
			return;
		}elsif( $func_name eq 'nMB' ){
			my $r = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"str", value=>sprintf("%.2fMB", $r)};
			return;
		}else{
			die "$func_name: unknown function name, stopped";
		}
	}
	die;
}

sub evaluate_op ($\@$) {
	my ($memory, $stack, $op) = @_;
	if    ( $op eq "+n" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>$right };
	}elsif( $op eq "-n" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>-$right };
	}elsif( $op eq "+" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left  = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>($left + $right) };
	}elsif( $op eq "-" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left  = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>($left - $right) };
	}elsif( $op eq "*" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left  = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>($left * $right) };
	}elsif( $op eq "/" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left  = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>($left / $right) };
	}elsif( $op eq "_" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left  = evaluate_rightvalue $memory, pop @$stack;
		push @$stack, { type=>"num", value=>($left . $right) };
	}elsif( $op eq "=" ){
		my $right = evaluate_rightvalue $memory, pop @$stack;
		my $left = pop @$stack;
		unless( $left->{type} eq "var" ){
			die;
		}
		$memory->{VAR}->{ $left->{name} } = $right;
		push @$stack, $left;
	}elsif( $op eq "," ){
	}else{
		die "$op: unknown operator, stopped";
	}
}

sub evaluate_expr ($$) {
	my ($memory, $text) = @_;
	my $context;
	my @stack;
	my @opstack;
	while( $text =~ m"\G\s*(
			$|
			([-+])|
			([*/,=])|
			(\()|
			(\))|
			(\w+)\s*\(|
			(\d+(?:\.\d+)?)|
			(\"([^\"]*)\")|
			\$(\w+)
		)"cgx ){
		if( $1 eq '' ){
			last if $context eq 'binop';
			while( @opstack ){
				evaluate_op $memory, @stack, pop(@opstack);
			}
			return @stack;
		}

		# 先置単項演算子 or 二項演算子 
		if    ( $2 ){
			# 二項演算子
			if( $context eq 'value' ){
				while( @opstack ){
					last if $PRIORITY{$opstack[-1]} < $PRIORITY{$2};
					evaluate_op $memory, @stack, pop(@opstack);
				}
				push @opstack, $2;
				$context = 'binop';

			# 先置単項演算子
			}else{
				push @opstack, $2 . "n";
			}

		# 二項演算子
		}elsif( $3 ){
			last if $context eq 'binop';
			while( @opstack ){
				last if $PRIORITY{$opstack[-1]} < $PRIORITY{$3};
				evaluate_op $memory, @stack, pop(@opstack);
			}
			push @opstack, $3;
			$context = 'binop';

		# 括弧
		}elsif( $4 ){
			last if $context eq 'value';
			push @stack, { type=>'bracket', op=>'(' };
			push @opstack, 'bracket';
		}elsif( $5 ){
			last if $context eq 'binop';
			while( @opstack ){
				last if $opstack[-1] eq 'bracket';
				evaluate_op $memory, @stack, pop(@opstack);
			}
			pop @opstack;
			evaluate_bracket $memory, @stack;

		# 関数
		}elsif( $6 ){
			last if $context eq 'value';
			push @opstack, 'bracket';
			push @stack, { type=>'func', name=>$6 };

		# 数値/文字列/変数
		}elsif( $7 ){
			last if $context eq 'value';
			push @stack, { type=>'num', value=>$7 };
			$context = 'value';
		}elsif( $8 ){
			last if $context eq 'value';
			push @stack, { type=>'str', value=>$9 };
			$context = 'value';
		}elsif( $10 ){
			last if $context eq 'value';
			push @stack, { type=>'var', name=>$10 };
			$context = 'value';
		}
	}
	my $e = substr $text, pos $text;
	die "ERROR: parse error at \"$e\", context is $context, stopped";
}

sub new_memory () {
	my $memory = {
		'IMPORT' => {},
		'EXPORT' => {},
		'VALUES' => {},
		'VAR' => {},
		'TIMESERIES' => undef,
	};
	return $memory;
}

1;

