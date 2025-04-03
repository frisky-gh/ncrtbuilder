#

package NCRTBuild::ThresholdGenerator;

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
	};
}

####

sub setRules ($@) {
	my ($this, @src) = @_;
	$$this{src} = \@src;
}

sub prepare ($) {
	my ($this) = @_;
	my $src = $$this{src};

	my @rules;
	my $curr_thresholds;
	my $vservice_re;
	foreach( @$src ){
		next if m"^\s*(#|$)";
		if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
			my $host_regexp = qr"^$1$";
			my $service_regexp = qr"^$2$";
			$curr_thresholds = [];
			push @rules, {
				'host_regexp'    => $host_regexp,
				'service_regexp' => $service_regexp,
				'thresholds'     => $curr_thresholds,
			};
		}elsif( m"^(\S+)\s+(crit|warn)\s+\[\s*([-+]?\d+(?:\.\d+)?)\s*,\s*([-+]?\d+(?:\.\d+)?)\s*\]\s*$" ){
			my $namepattern = $1;
			my $severity = $2;
			my $upper = $3;
			my $lower = $4;
			push @$curr_thresholds, {
				"namepattern" => $namepattern,
				"severity" => $severity,
				"upper" => $upper,
				"lower" => $lower,
			};
		}else{
			die "illegal format, stopped";
		}
	}

	$$this{rules} = \@rules;
}

sub generate ($$$) {
	my ($this, $host, $service) = @_;
	my $rules = $$this{rules};

	my @r;
	foreach( @$rules ){
		my $host_regexp    = $$_{host_regexp};
		my $service_regexp = $$_{service_regexp};
		next unless $host    =~ $host_regexp;
		next unless $service =~ $service_regexp;
		push @r, @{ $$_{thresholds} };
	}
	return @r;
}


1;

