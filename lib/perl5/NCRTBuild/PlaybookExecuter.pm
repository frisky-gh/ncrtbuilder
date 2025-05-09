#!/usr/bin/perl

package NCRTBuild::PlaybookExecuter;

use Exporter import;
our @EXPORT = (
);

use strict;
use NCRTBuild::Common;

####

sub new ($) {
	my ($class) = @_;
	return bless {
		'playbookdir'	=> undef,
		'basename'	=> undef,
		'pattern'	=> qr"^.*$",
	};
}

####

sub hash2yaml ($) {
	my ($params) = @_;
	my @params;
	foreach my $k ( sort keys %$params ){
		my $v = $$params{$k};
		push @params, "\"$k\":\"$v\"";
	}
	return "{" . join(", ", @params) . "}";
}

####

sub setPlaybookDirPath ($$) {
	my ($this, $playbookdir) = @_;
	$$this{playbookdir} = $playbookdir;
}

sub setPluginDirPath ($$) {
	my ($this, $plugindir) = @_;
	$$this{plugindir} = $plugindir;
}

sub setPluginConfigDirPath ($$) {
	my ($this, $pluginconfdir) = @_;
	$$this{pluginconfdir} = $pluginconfdir;
}

sub setPluginWorkDirPath ($$) {
	my ($this, $pluginworkdir) = @_;
	$$this{pluginworkdir} = $pluginworkdir;
}

sub setDistributedDirPath ($$) {
	my ($this, $distributeddir) = @_;
	$$this{distributeddir} = $distributeddir;
}

sub setBaseName ($$) {
	my ($this, $basename) = @_;
	$$this{basename} = $basename;
}

sub setTargetPattern ($$) {
	my ($this, $pattern) = @_;
	$$this{pattern} = qr"^$pattern$";
}

sub setQuick ($) {
	my ($this) = @_;
	$$this{quick} = 1;
}

sub setDryRun ($) {
	my ($this) = @_;
	$$this{dryrun} = 1;
}

sub setAnsibleOptions ($$) {
	my ($this, $ansibleoptions) = @_;
	$$this{ansibleoptions} = $ansibleoptions;
}

sub setHosts ($@) {
	my ($this, @hosts) = @_;
	$$this{hosts} = \@hosts;

	my %hosttype2plugintypes;
	foreach( @hosts ){
		if    ( defined $$_{agenttype} ){
			$$_{hosttype} = $$_{agenttype};
			$$_{plugintype} = "agenttype";
			$hosttype2plugintypes{ $$_{agenttype}  }->{agenttype} = 1;
		}elsif( defined $$_{mastertype} ){
			$$_{hosttype} = $$_{mastertype};
			$$_{plugintype} = "mastertype";
			$hosttype2plugintypes{ $$_{mastertype} }->{mastertype} = 1;
		}
	}
	$$this{hosttype2plugintypes} = \%hosttype2plugintypes;

	my @hosttypes;
	foreach my $hosttype ( sort keys %hosttype2plugintypes ){
		my $plugintypes = $hosttype2plugintypes{$hosttype};
		foreach my $plugintype ( sort keys %$plugintypes ){
			push @hosttypes, {
				"hosttype"   => $hosttype,
				"plugintype" => $plugintype,
			};
		}
	}
	$$this{hosttypes} = \@hosttypes;
}

sub buildVarsYML ($) {
	my ($this) = @_;
	my $playbookdir = $$this{playbookdir};
	my $basename = $$this{basename};

	my $f = "$playbookdir/${basename}_vars.yml";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	print $h <<"EOF";
---
 NCRTAGENTHOME:       "/opt/ncrtagent"
 NCRTMASTERHOME:      "/opt/ncrtmaster"

EOF
	close $h;
}


sub buildHostsYML ($) {
	my ($this) = @_;
	my $playbookdir   = $$this{playbookdir};
	my $basename  = $$this{basename};
	my $pattern   = $$this{pattern};
	my $hosts     = $$this{hosts};
	my $hosttypes = $$this{hosttypes};

	my $f = "$playbookdir/${basename}_hosts.yml";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	print $h
		"all:\n",
		"  children:\n",
		"    AllHosts:\n",
		"      children:\n";
	foreach( @$hosttypes ){
		my $plugintype = $$_{plugintype};
		my $hosttype   = $$_{hosttype};
		print $h "        PLUGINTYPE_$plugintype.HOSTTYPE_$hosttype:\n";
	}
	foreach( @$hosttypes ){
		my $target_plugintype = $$_{plugintype};
		my $target_hosttype   = $$_{hosttype};
		print $h
			"    PLUGINTYPE_$target_plugintype.HOSTTYPE_$target_hosttype:\n",
			"      hosts:\n";
		foreach my $host ( @$hosts ){
			my $plugintype = $$host{plugintype};
			my $hosttype   = $$host{hosttype};
			my $hostname   = $$host{hostname};
			next unless $plugintype eq $target_plugintype;
			next unless $hosttype eq $target_hosttype;
			next unless $hostname =~ m"$pattern";

			my $ansibleparam = $$host{ansibleparam};
			my $yaml_hash = hash2yaml $ansibleparam;
			print $h "        $hostname: $yaml_hash\n";
		}
	}
	close $h;
}

sub buildPlaybookYML ($) {
	my ($this) = @_;
	my $playbookdir = $$this{playbookdir};
	my $plugindir = $$this{plugindir};
	my $basename  = $$this{basename};
	my $pattern   = $$this{pattern};
	my $hosts     = $$this{hosts};
	my $hosttypes = $$this{hosttypes};

	my $f = "$playbookdir/${basename}_playbook.yml";
	my $vars_yml = "$playbookdir/${basename}_vars.yml";
	open my $h, '>', $f or do {
		die "$f: cannot open, stopped";
	};
	print $h
		"- hosts: all\n",
		"  tasks:\n",
		"    - name: include variables\n",
		"      include_vars: $vars_yml\n",
		"      tags: [ common ]\n";
	foreach( @$hosttypes ){
		my $plugintype = $$_{plugintype};
		my $hosttype   = $$_{hosttype};
		my $plugin_playbook = "$plugindir/ncrtbuild_${plugintype}_$hosttype.yml";
		if( -f $plugin_playbook ){
			print $h
				"- name: import playbook $hosttype of $plugintype\n",
				"  import_playbook: $plugin_playbook\n";
#				"- hosts: PLUGINTYPE_$plugintype.HOSTTYPE_$hosttype\n",
#				"  tasks:\n",
#				"    - name: import playbook $hosttype of $plugintype\n",
#				"      import_playbook: $plugin_playbook\n";
		}
	}
	close $h;
}

sub buildCommandLine ($) {
	my ($this) = @_;
	my $playbookdir    = $$this{playbookdir};
	my $pluginconfdir  = $$this{pluginconfdir};
	my $pluginworkdir  = $$this{pluginworkdir};
	my $distributeddir = $$this{distributeddir};
	my $basename  = $$this{basename};
	my $quick = $$this{quick};
	my $ansibleoptions = $$this{ansibleoptions};

	my $playbook_yml = "$playbookdir/${basename}_playbook.yml";
	my $hosts_yml    = "$playbookdir/${basename}_hosts.yml";

	my @tags = ('common');
	push @tags, 'commoninstall' unless $quick;
	my $tags = join ",", @tags;


	my $cmd = "ansible-playbook -v" .
		" -i $hosts_yml" .
		" -e PLUGINCONFDIR=$pluginconfdir" .
		" -e PLUGINWORKDIR=$pluginworkdir" .
		" -e PLAYBOOKDIR=$playbookdir" .
		" -e DISTRIBUTEDDIR=$distributeddir" .
		" -t $tags" .
		" $ansibleoptions" .
		" $playbook_yml";
	$$this{cmd} = $cmd;
}

sub execAnsible ($) {
	my ($this) = @_;
	my $cmd = $$this{cmd};
	my $dryrun = $$this{dryrun};
	print "$cmd\n";
	if( $dryrun ){
		print "skip running ansible.\n";
		return;
	}
	system_or_die $cmd;
}

sub deploy ($$) {
	my ($this) = @_;

	$this->buildVarsYML;
	$this->buildHostsYML;
	$this->buildPlaybookYML;
	$this->buildCommandLine;
	$this->execAnsible;
}

####

1;

