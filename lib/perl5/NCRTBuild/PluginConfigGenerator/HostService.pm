#

package NCRTBuild::PluginConfigGenerator::HostService;

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

sub setOriginConfig ($@) {
	my ($this, @origin) = @_;

	my @rules;
	my $curr_section;
	my $vservice_re;
	foreach( @origin ){
		next if m"^\s*(#|$)";
		if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
			my $host_regexp = qr"^$1$";
			my $service_regexp = qr"^$2$";
			$curr_section = [];
			push @rules, {
				'host_regexp'    => $host_regexp,
				'service_regexp' => $service_regexp,
				'contents'       => $curr_section,
			};
		}else{
			push @$curr_section, $_;
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
		my $contents       = $$_{contents};
		next unless $host    =~ $host_regexp;
		next unless $service =~ $service_regexp;
		push @r, @$contents;
	}
	return @r;
}

####

1;

