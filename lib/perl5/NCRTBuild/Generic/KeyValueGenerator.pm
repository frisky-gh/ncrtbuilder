#

package NCRTBuild::Generic::KeyValueGenerator;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'rules' => undef,
		'valuename' => undef,
		'category' => undef,
	};
}

####

sub setValueName ($$) {
	my ($this, $valuename) = @_;
	$$this{valuename} = $valuename;
}

sub setRules ($@) {
	my ($this, @src) = @_;
	$$this{src} = \@src;
}

sub prepare ($) {
	my ($this) = @_;
	my $src = $$this{src};
	my $valuename = $$this{valuename};

	my @rules;
	my $curr_entry;
	my $vservice_re;
	foreach( @$src ){
		next if m"^\s*(#|$)";
		if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
			my $host_regexp = qr"^$1$";
			my $service_regexp = qr"^$2$";
			my $curr_entry = {
				'host_regexp'    => $host_regexp,
				'service_regexp' => $service_regexp,
				'keyvalue'          => {},
			};
			push @rules, $curr_entry;
		}elsif( m"^(\w+)\s+(\w+)=(.*)" ){
			die "invalid value name, stopped" unless $1 eq $valuename;
			$$curr_entry{keyvalue}->{$1} = $2;
		}else{
			die "illegal format, stopped";
		}
	}

	$$this{rules} = \@rules;
}

sub generate ($$$) {
	my ($this, $host, $service) = @_;
	my $rules = $$this{rules};

	my %r;
	foreach( @$rules ){
		my $host_regexp    = $$_{host_regexp};
		my $service_regexp = $$_{service_regexp};
		next unless $host    =~ $host_regexp;
		next unless $service =~ $service_regexp;
		while( my ($k, $v) = each %{ $$_{keyvalue} } ){
			$r{$k} = $v;
		}
	}
	return %r;
}


1;

