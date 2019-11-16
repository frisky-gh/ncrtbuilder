package NCRTStackMachine;

use strict;
use Data::Dumper;

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
	';' => 1,
	'bracket' => 0,
	'squarebr' => 0,
	'curlybr' => 0,
);

sub add_bracket_into_tree ($$) {
	my ($type, $tree) = @_;
	my $newtree =  {type=>$type, values=>[], root=>$tree};
	push @{$tree->{values}}, $newtree;
	return $newtree;
}

sub close_bracket_in_tree ($$) {
	my ($typelist, $tree) = @_;
	my %avail_type = ('STR' => 1, 'NUM' => 1, 'VAR' => 1, 'UNIOP' => 1, 'BINOP' => 1);

	my $tree_type = $tree->{type};
	while( $avail_type{$tree_type} ){
		$tree = $tree->{root};
		$tree_type = $tree->{type};
	}

	foreach my $i ( @$typelist ){
		next unless $tree_type eq $i;
print "DEBUG: close_bracket: $tree_type\n";
		my $roottree = $tree->{root};
		my $roottree_type = $roottree->{type};
print "DEBUG: close_bracket: roottree=$roottree_type\n";
		return $tree->{root};
	}
	die;
}

sub next_statement_in_tree ($) {
	my ($tree) = @_;
	while( $tree ){
		my $tree_type = $tree->{type};
		if( $tree_type eq 'STATEMENT' ){
			return $tree;
		}
		$tree = $tree->{root};
	}
	die;
}

sub add_node ($$) {
	my ($node, $tree) = @_;
	$node->{root} = $tree;
	push @{$tree->{values}}, $node;
	return $node;
}

sub insert_node ($$) {
	my ($node, $tree) = @_;
	my $node_type = $node->{type};
	if( $node_type ne 'BINOP' ){
		# root -> node -> tree
		my $root = $tree->{root};
		$node->{root} = $root;
		$tree->{root} = $node; 
		$root->{values}->[-1] = $node;
		$node->{values}->[0] = $tree;
		return $node;
	}

	my $tree_type = $tree->{type};
	while( $tree_type eq 'STR' || $tree_type eq 'NUM' || $tree_type eq 'VAR' || $tree_type eq 'UNIOP' ){
		$tree = $tree->{root};
		$tree_type = $tree->{type};
	}

	my $node_pri = $PRIORITY{$tree->{name}};
	while( $tree_type eq 'BINOP' ){
		my $tree_pri = $PRIORITY{$tree->{name}};
		last unless $tree_pri > $node_pri;
		$tree = $tree->{root};
		$tree_type = $tree->{type};
	}
	# tree -> node -> child
	my $child = $tree->{values}->[-1];
	$node->{root} = $tree;
	$child->{root} = $node;
	$tree->{values}->[-1] = $node;
	$node->{values}->[0] = $child;
	return $node;
}

sub add_memberfunc_into_tree ($$) {
	die;
}

sub add_closebracket_into_tree ($$) {
	die;
}

sub parse_as_value_context ($\$\$) {
	my ($memory, $treeref, $exprref) = @_;
	unless( $$exprref =~ m"\G\s*(?<nextitem>
		$|
		(?<endofstatement> ;    	)|
		(?<uniop>         [-+]   	)|
		(?<openbracket>  \(     	)|
		(?<closebracket> \)     	)|
		(?<opensquarebr> \[     	)|
		(?<closesqureabr>\]     	)|
		(?<opencurlybr>  \{     	)|
		(?<closecurlybr> \}     	)|
		(?<func>	 \w+ )\s*\(	|
		\.(?<memberfunc> \w+ )\s*\(	|
		(?<num> 	 \d+(?:\.\d+)?	)|
		(?<str>		 \"(?<strinner> [^\"]*)\" )|
		\$(?<var>	 \w+		)
	)"cgx ){
		my $e = substr $$exprref, pos $$exprref;
		my $t = $$treeref->{type};
		die "ERROR: parse error at \"$e\", context is $t, stopped";
	}

	# unary operator
	if    ( $+{uniop} ){
		$$treeref = add_node {type=>'UNIOP', name=>$+{uniop}, values=>[]}, $$treeref;

	# bracket
	}elsif( $+{openbracket} ){
		$$treeref = add_bracket_into_tree 'BRACKET', $$treeref;

	# list
	}elsif( $+{opensquarebr} ){
		$$treeref = add_bracket_into_tree 'LIST', $$treeref;

	# map
	}elsif( $+{opencurlybr} ){
		$$treeref = add_bracket_into_tree 'MAP', $$treeref;

	# empty bracket
	}elsif( $+{closebracket} ){
		$$treeref = close_bracket_in_tree ['FUNC'], $$treeref;
	}elsif( $+{closesquarebr} ){
		$$treeref = close_bracket_in_tree ['LIST'], $$treeref;
	}elsif( $+{closecurlybr} ){
		$$treeref = close_bracket_in_tree ['MAP'], $$treeref;

	# function
	}elsif( $+{func} ){
		$$treeref = add_node {type=>'FUNC', name=>$+{func}, values=>[]}, $$treeref;

	# number/string/variable
	}elsif( $+{num} ){
		$$treeref = add_node {type=>'NUM', value=>$+{num}}, $$treeref;
	}elsif( $+{str} ){
		$$treeref = add_node {type=>'STR', value=>$+{strinner}}, $$treeref;
	}elsif( $+{var} ){
		$$treeref = add_node {type=>'VAR', value=>$+{var}}, $$treeref;

	# end of statement
	}elsif( $+{endofstatement} ){
		$$treeref = next_statement_in_tree $$treeref;

	#
	}else{
		die;
	}

	return undef;
}

sub parse_as_op_context ($\$\$) {
	my ($memory, $treeref, $exprref) = @_;
	unless( $$exprref =~ m"\G\s*(?<nextitem>
		(?<endofstatement> ;    	)|
		(?<binop>        [-+*/,=] 	)|
		(?<openbracket>  \(     	)|
		(?<opensquarebr> \[     	)|
		(?<opencurlybr>  \{     	)|
		(?<closebracket> \)     	)|
		(?<closesqureabr>\]     	)|
		(?<closecurlybr> \}     	)|
		\.(?<memberfunc> \w+ )\s*\(	
	)"cgx ){
		my $e = substr $$exprref, pos $$exprref;
		my $t = $$treeref->{type};
		die "ERROR: parse error at \"$e\", context is $t, stopped";
	}

	# binary operator
	if( $+{binop} ){
		$$treeref = insert_node {type=>'BINOP', name=>$+{binop}, values=>[]}, $$treeref;

	# list member access
	}elsif( $+{opensquarebr} ){
		$$treeref = insert_node {type=>'LISTACCESS', values=>[]}, $$treeref;

	# map member access
	}elsif( $+{opencurlybr} ){
		$$treeref = insert_node {type=>'MAPACCESS', values=>[]}, $$treeref;

	# member function access
	}elsif( $+{memberfunc} ){
		$$treeref = insert_node {type=>'MEMBERFUNC', values=>[]}, $$treeref;

	# close bracket
	}elsif( $+{closebracket} ){
		$$treeref = close_bracket_in_tree ['BRACKET', 'FUNC'], $$treeref;
	}elsif( $+{closesquarebr} ){
		$$treeref = close_bracket_in_tree ['LISTACCESS', 'LIST'], $$treeref;
	}elsif( $+{closecurlybr} ){
		$$treeref = close_bracket_in_tree ['MAPACCESS', 'MAP'], $$treeref;

	# end of statement
	}elsif( $+{endofstatement} ){
		die;

	#
	}else{
		die;
	}

	return undef;
}


sub parse_expr ($$) {
	my ($memory, $expr) = @_;
	my $tree = {type=>'STATEMENT', root=>undef, values=>[]};
	my $root = {type=>'ROOT', root=>undef, values=>[]};
	$tree->{root} = $root;
	push @{$root->{values}}, $tree;
	eval {
		while( 1 ){
print "DEBUG: ", Dumper($root), "\n";
			my $t = $tree->{type};
			my $r;
print "DEBUG:     type: $t\n";
			if    ( $t eq 'STATEMENT' ){
				$r = parse_as_value_context $memory, $tree, $expr;
			}elsif( $t eq 'UNIOP' ){
				$r = parse_as_value_context $memory, $tree, $expr;
			}elsif( $t eq 'BINOP' ){
				$r = parse_as_value_context $memory, $tree, $expr;
			}elsif( $t eq 'FUNC' ){
				$r = parse_as_value_context $memory, $tree, $expr;
			}elsif( $t eq 'NUM' ){
				$r = parse_as_op_context $memory, $tree, $expr;
			}elsif( $t eq 'STR' ){
				$r = parse_as_op_context $memory, $tree, $expr;
			}elsif( $t eq 'VAR' ){
				$r = parse_as_op_context $memory, $tree, $expr;
			}else{
				die "type=$t, stopped";
			}
			return if $r;
		}
	};
	if( $@ ){
		my $e = substr $expr, pos $expr;
		die "$@\nERROR: parse error at \"$e\", stopped";
	}
}

####
sub substitute_leftvalue ($$) {
	my ($memory, $left, $right) = @_;
	my $v = evaluate_rightvalue($memory, $right);

	my $type = $left->{type};
	if    ( $type eq "var" ){
		return $memory->{VAR}->{ $left->{name} } = $v;
	}elsif( $type eq "listitemref" ){
		my $list  = $left->{list};
		my $index = $left->{index};
		return $list->[$index] = $v;
	}elsif( $type eq "mapitemref" ){
		my $map   = $v->{map};
		my $index = $v->{index};
		return $map->{$index} = $v;
	}
	die;
}

sub evaluate_rightvalue ($$) {
	my ($memory, $v) = @_;
	my $type = $v->{type};
	if    ( $type eq "num" ){
		return $v->{value};
	}elsif( $type eq "str" ){
		return $v->{value};
	}elsif( $type eq "var" ){
		return $memory->{VAR}->{ $v->{name} };
	}elsif( $type eq "listitemref" ){
		my $list  = $v->{list};
		my $index = $v->{index};
		return $list->[$index];
	}elsif( $type eq "mapitemref" ){
		my $map   = $v->{map};
		my $index = $v->{index};
		return $map->{$index};
	}
	die "$type: unknown type, stopped";
}

sub evaluate_list ($$) {
	my ($memory, $v) = @_;
	# TODO
	my $type = $v->{type};
	if    ( $type eq "list" ){
		return $v->{value};
	}
	die;
}

sub evaluate_map ($$) {
	my ($memory, $v) = @_;
	my $type = $v->{type};
	if    ( $type eq "map" ){
		return $v->{value};
	}
	die;
}

sub evaluate_squarebr ($\@) {
	my ($memory, $stack) = @_;
	for( my $i = $#$stack; $i >= 0; --$i ){
		my $t = $stack->[$i]->{type};
		next unless $t eq "list" || $t eq "listaccess";

		my ($bracket, @args) = splice @$stack, $i;
		if( $t eq "list" ){
			push @$stack, {type=>"list", value=>[@args]};
			return;
		}else{
			my $num = evaluate_rightvalue $memory, $args[0];
			my $list = evaluate_list $memory, pop @$stack;
			push @$stack, {
				type  => "listitemref",
				list  => $list,
				index => $num,
			};
		}
	}
	die;
}

sub evaluate_curlybr ($\@) {
	my ($memory, $stack) = @_;
	for( my $i = $#$stack; $i >= 0; --$i ){
		my $t = $stack->[$i]->{type};
		next unless $t eq "map" || $t eq "mapaccess";

		my ($bracket, @args) = splice @$stack, $i;
		if( $t eq "list" ){
			push @$stack, {type=>"map", value=>{@args}};
			return;
		}else{
			my $text = evaluate_rightvalue $memory, $args[0];
			my $map = evaluate_map $memory, pop @$stack;
			push @$stack, {
				type  => "mapitemref",
				map   => $map,
				index => $text,
			};
		}
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
		}elsif( $func_name eq 'import_names' ){
			my $name = evaluate_rightvalue $memory, shift @args;
			push @$stack, {  type=>"list", value=>[ sort keys %{$memory->{IMPORT}} ]  };
			return;
		}elsif( $func_name eq 'export' ){
			my $name  = evaluate_rightvalue $memory, shift @args;
			my $value = evaluate_rightvalue $memory, shift @args;
			push @$stack, {type=>"num", value=>1};
			$memory->{EXPORT}->{$name} = $value;
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

sub evaluate_op ($$$) {
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

sub evaluate_opstack ($$$$) {
	my ($memory, $stack, $opstack, $newop) = @_;
	while( @$opstack ){
		last if $PRIORITY{$opstack->[-1]} < $PRIORITY{$3};
		last if $opstack->[-1] eq $newop;
		evaluate_op $memory, $stack, pop(@$opstack);
	}
}

sub evaluate_expr ($$) {
}

####
sub new_memory () {
	my $memory = {
		'IMPORT' => {},
		'EXPORT' => {},
		'VAR' => {},
		'TIMESERIES' => {},
	};
	return $memory;
}

*main::new_memory = \&new_memory;
*main::parse_expr = \&parse_expr;
*main::evaluate_expr = \&evaluate_expr;
1;

