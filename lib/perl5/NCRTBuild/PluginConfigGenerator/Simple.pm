#

package NCRTBuild::PluginConfigGenerator::Simple;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($$) {
	my ($class) = @_;
	return bless {
		'content' => undef,
		'name'    => undef,
		'category'    => undef,
	};
}

####

sub setOriginConfig ($@) {
	my ($this, @content) = @_;
	$$this{content} = \@content;
}

sub generate ($$$) {
	my ($this, $host, $service) = @_;
	my $content = $$this{content};
	return @$content;
}


####

1;

