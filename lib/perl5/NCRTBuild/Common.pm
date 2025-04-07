#!/usr/bin/perl

package NCRTBuild::Common;

use Exporter import;
our @EXPORT = (
	'rm_r',
	'mkdir_or_die',
	'create_or_die',
	'system_or_die',
	'parse_addressentry',
	'parse_mapping',
	'parse_item_with_params',
	'parse_2items_with_params',
	'parse_3items_with_params',
	'parse_4items_with_params',
	'parse_host2item_mapping',
	'parse_host2service2item_mapping',
	'expand_importspec',
	'expand_params',
	'generate_naemondirectiveline',
	'generate_shortnamelist_or_nobody',
);

use strict;

####
sub rm_r ($) {
	my ($r) = @_;
	return unless -d $r;
	opendir my $d, $r or do {
		die "$r: cannot open, stopped";
	};
	my @e = readdir $d;
	foreach my $e ( @e ){
		next if $e eq '..' || $e eq '.';
		if( -d "$r/$e" ){
			rm_r( "$r/$e" );
		}else{
			unlink "$r/$e" or die "$r/$e, stopped";
		}
	}
	closedir $d;
	rmdir $r or die "$r: cannot remove, stopped";
}

sub mkdir_or_die ($) {
	my ($d) = @_;
	return if -d $d;
	mkdir $d or die "$d: cannot create, stopped";
}

sub create_or_die ($) {
	my ($f) = @_;
	open my $h, '>', $f or die "$f: cannot create, stopped";
	close $h;
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

sub _parse_params ($) {
	( $_ ) = @_;
	my %params;
	my %templateparams;
	return undef, \%params, \%templateparams if m"^\s*$";
	while( m{\G
		($|\s+
			(\@)?(\w+)=
			(?:
				"([^\\"]*(?:(?:\\\\|\\")+[^\\"]*)*)"|
				([\w\!\#-\&\(-\/\:-\@\[-\_\{-\~]*)
			)
		)
	}cgx ){
		return undef, \%params, \%templateparams if $1 eq '';

		my $template = $2;
		my $key = $3;
		my $value = $4 ne '' ? $4 : $5;

		if( $template ){ $templateparams{$key} = $value; }
		else           { $params{$key} = $value; }
	}
	
	my $failed = substr $_, pos;
	return "illegal format: starting with \"$failed\"";
}

sub parse_addressentry ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef if m"^\s*(#|$)";
	return undef, "illegal format" unless m"^(\S+\@[-.a-zA-Z0-9]+)"g;
	my $item = $1;
	my ($opt, $topt) = _parse_params $';
	return undef unless defined $opt;
	return $item, $opt, $topt;
}

sub parse_mapping ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef, undef if m"^\s*(#|$)";
	return undef, undef, "illegal format" unless m"^(\S+)\s+([\w,]+)"g;
	my $from = $1;
	my $to = $2;
	my ($opt, $topt) = _parse_params $';
	return undef unless defined $opt;
	return $from, $to, $opt, $topt;
}

sub parse_item_with_params ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef if m"^\s*(#|$)";
	return "illegal format: starting with \"$_\"", undef unless m"^(\S+)"g;
	my $item = $1;
	my ($err, $params, $special_params) = _parse_params $';
	return $err, undef if $err;
	return undef, $item, $params, $special_params;
}

sub parse_2items_with_params ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef if m"^\s*(#|$)";
	return "illegal format", undef unless m"^(\S+)\s+(\S+)";
	my $first  = $1;
	my $second = $2;
	my ($err, $params, $special_params) = _parse_params $';
	return $err, undef if $err;
	return undef, $first, $second, $params, $special_params;
}

sub parse_3items_with_params ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef, undef if m"^\s*(#|$)";
	return "illegal format", undef unless m"^(\S+)\s+(\S+)\s+(\S+)";
	my $first  = $1;
	my $second = $2;
	my $third  = $3;
	my ($err, $params, $special_params) = _parse_params $';
	return $err, undef if $err;
	return undef, $first, $second, $third, $params, $special_params;
}

sub parse_4items_with_params ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef, undef if m"^\s*(#|$)";
	return undef, undef, "illegal format" unless m"^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)";
	my $first  = $1;
	my $second = $2;
	my $third  = $3;
	my $fourth = $4;
	my ($err, $params, $special_params) = _parse_params $';
	return $err, undef if $err;
	return undef, $first, $second, $third, $fourth, $params, $special_params;
}

sub parse_host2item_mapping ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef, undef if m"^\s*(#|$)";
	return undef, undef, "illegal format" unless m"^(\S+)\s+(\S+)$";
	return $1, $2, undef;
}

sub parse_host2service2item_mapping ($) {
	( $_ ) = @_;
	chomp;
	return undef, undef, undef, undef if m"^\s*(#|$)";
	return undef, undef, undef, "illegal format" unless m"^(\S+)\s+([\w,]+)\s+(\S+)$";
	return $1, $2, $3, undef;
}

sub expand_importspec (@){
	my @importmacros;
	foreach my $i ( @_ ){
		my ($host, $service, $prefix) = @$i;

		# TODO: check host / service

		push @importmacros,
			"$host:$service:$prefix \$SERVICEPERFDATA:$host:$service\$";
	}
	my $importmacro = join " ", @importmacros;
	return $importmacro;
}

sub expand_params ($@) {
	my ($text, @params_list) = @_;
	$text =~ s{ <(\w+)> }{
		my $r;
		foreach( @params_list ){ $r = $$_{$1}; last if defined $r; }
		$r;
	}egx;
	return $text;
}

sub generate_naemondirectiveline ($@) {
	my ($naemondirective, @params_list) = @_;
	my @line;
	foreach my $k ( sort keys %$naemondirective ){
		my $v = $$naemondirective{$k};
		push @line, sprintf "\t%-23s\t%s",
			$k, expand_params $v, @params_list;
	}
	return @line;
}

sub generate_shortnamelist_or_nobody (@) {
	return 'nobody' unless @_;
	return 'nobody' if @_ == 1 && !defined $_[0];
	return join ',', @_;
}

