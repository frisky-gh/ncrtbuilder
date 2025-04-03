
                        my @conffiles = $validator->listConfFile( $measurement );
                        foreach my $conffile ( @conffiles ){
                                my @src = $conf->get_content( $conffile );
                                my @dst = $formatter->convert( $host, @src );
                                $work->store_content_for_agent( $host, $measurement, $host, $conffile, @dst );
                        }


#### generate confs for which service type is agentless
sub generate_masterconf_for_agentless ($$@) {
	my ($measure, $conf, @ncrtmasters) = @_;
	my %vhost2rules;
	my $vhost;
	my $f = "$CONFDIR/$conf";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		if( m"^===\s+(\S+)\s+===$" ){
			$vhost = $1;
		}elsif( m"^(\S+)" ){
			push @{$vhost2rules{$vhost}}, $_;
		}else{
			die "$f:$.: illegal format, stopped";
		}
	}
	close $h;

	foreach my $master ( @ncrtmasters ){
		while( my ($vhost, $rules) = each %vhost2rules ){
			my $f = "$WORKDIR/ncrtmaster/$master/$conf.$measure.$vhost";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach my $rule ( @$rules ){
				print $h $rule, "\n";
			}
			close $h;
		}
	}
}

	while( my ($measure, $measuretype) = each %measure2measuretype ){
		next unless $measuretype eq 'agentless';
		my @confs = @{$measure2conf{$measure}};

		foreach my $conf ( @confs ){
			generate_masterconf_for_agentless $measure, $conf, @ncrtmasters;
		}
	}
}

######## Step10. ########
######## Step10. ########

#### generate confs for which service type is indirect
sub diff (\%\%) {
	my ($old, $new) = @_;
	my %keys;
	my %d;
	while( my ($k) = each %$old ){ $keys{$k} = 1; }
	while( my ($k) = each %$new ){ $keys{$k} = 1; }
	while( my ($k) = each %keys ){
		my $o = $old->{$k};
		my $n = $new->{$k};
		next if $o eq $n;
		$d{$k} = $n;
	}
	return %d;
}

sub generate_agentconf_for_indirect ($$$$) {
	my ($measure, $conf, $host2agenttype, $vhostvservice2proxyhosts) = @_;
	my $vhostvservice;
	my %vhostvservice2rules;
	my %option;
	my $f = "$CONFDIR/$conf";
	open my $h, '<', $f or do {
		die "$f: cannot open, stopped";
	};
	while( <$h> ){
		chomp;
		next if m"^\s*(#|$)";
		if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
			$vhostvservice = "$1 $2";
			%option = ();
		}elsif( m"^(\w+)=(\S*)$" ){
			$option{$1} = $2;
		}elsif( m"^(\S+)\s+(\S.*)$" ){
			push @{$vhostvservice2rules{$vhostvservice}},
				[qr"^$1$", $2, {%option}];
		}else{
			die "$f:$.: illegal format, stopped";
		}
	}
	close $h;

	while( my ($proxyhost, $agenttype) = each %$host2agenttype ){
		foreach my $vhostvservice ( sort keys %vhostvservice2rules ){
			my ($vhost, $vservice) = split m"\s+", $vhostvservice;
			my $rules = $vhostvservice2rules{$vhostvservice};
			my %option;
			my @settings;
			foreach my $rule ( @$rules ){
				my ($proxyhost_re, $setting, $option) = @$rule;
				next unless $proxyhost =~ m"$proxyhost_re";
				my %d = diff %option, %$option;
				while( my ($k, $v) = each %d ){
					push @settings, "$k=$v";
					$option{$k} = $v;
				}
				push @settings, $setting;
			}
			next unless @settings;
			my $f = "$WORKDIR/ncrtagent/$proxyhost/conf/$conf.$measure.$vhost.$vservice";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach( @settings ){ print $h $_, "\n"; }
			close $h;
			$$vhostvservice2proxyhosts{$vhostvservice}->{$proxyhost} = 1;
		}
	}
}

sub generate_masterconf_for_indirect ($$@) {
	my ($measure, $vhostvservice2proxyhosts, @ncrtmasters) = @_;
	foreach my $master ( @ncrtmasters ){
		foreach my $vhostvservice ( sort keys %$vhostvservice2proxyhosts ){
			my $proxyhosts = $$vhostvservice2proxyhosts{$vhostvservice};
			my ($vhost, $vservice) = split m"\s+", $vhostvservice;
			my $f = "$WORKDIR/ncrtmaster/$master/indirect/proxyhosts.$measure.$vhost.$vservice";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach my $proxyhost ( sort keys %$proxyhosts ){
				print $h $proxyhost, "\n";
			}
			close $h;
		}
	}
}

if( $plan{Step10} ){
	while( my ($measure, $measuretype) = each %measure2measuretype ){
		next unless $measuretype eq 'indirect';
		my @confs = @{$measure2conf{$measure}};

		my %vhostvservice2proxyhosts;
		foreach my $conf ( @confs ){
			generate_agentconf_for_indirect $measure, $conf, \%host2agenttype, \%vhostvservice2proxyhosts;
		}
		generate_masterconf_for_indirect $measure, \%vhostvservice2proxyhosts, @ncrtmasters;
	}
}

######## Step11. ########
