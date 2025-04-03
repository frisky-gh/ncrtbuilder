#

package NCRTBuild::Generic::SimpleValueGenerator;

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
	};
}

####

sub setValueName ($$) {
	my ($this, $valuename) = @_;
	$$this{valuename} = $valuename;
}

sub setCategory ($$) {
	my ($this, $category) = @_;
	$$this{category} = $category;
}

sub getCategory ($) {
	my ($this) = @_;
	return $$this{category};
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
			$curr_entry = {
				'host_regexp'    => $host_regexp,
				'service_regexp' => $service_regexp,
				'value'          => undef,
			};
			push @rules, $curr_entry;
		}elsif( m"^(\w+)\s+(\S+)" ){
			die "invalid value name, stopped" unless $1 eq $valuename;
			$$curr_entry{value} = $2;
		}else{
			die "illegal format, stopped";
		}
	}

	$$this{rules} = \@rules;
}

sub get ($$$) {
	my ($this, $host, $service) = @_;
	my $rules = $$this{rules};

	my $r;
	foreach( @$rules ){
		my $host_regexp    = $$_{host_regexp};
		my $service_regexp = $$_{service_regexp};
		my $value          = $$_{value};
		next unless $host    =~ $host_regexp;
		next unless $service =~ $service_regexp;
		next unless defined $value;
		$r = $$_{value};
	}
	return $r;
}

1;

