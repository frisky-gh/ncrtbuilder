#### generate metricfilter / thresholdfilter settings
sub generate_filter_settings ($\%\@) {
	my ($filtertype, $measure2measuretype, $host_service_measure_opts) = @_;

	##
	my $d = "$CONFDIR/$filtertype";
	opendir my $h, $d or do {
		die "$d: cannot open, stopped";
	};
	my @rules;
	foreach my $e ( sort readdir $h ){
		next unless $e =~ m"^\w.*\.filterrules$";
		my $f = "$d/$e";
		open my $i, "<", $f or do {
			die "$f: cannot open, stopped";
		};
		my $vhost_re;
		my $vservice_re;
		while( <$i> ){
			chomp;
			next if m"^\s*(#|$)";
			if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
				$vhost_re = qr"^$1$";
				$vservice_re = qr"^$2$";
			}elsif( m"^filter\s+(\S+)" ){
				my $filter = $1;

				# TODO: check filter path

				push @rules, [$vhost_re, $vservice_re, $filter];
			}else{
				die "$f:$.: illegal format, stopped";
			}
		}
		close $i;
	}
	closedir $h;

	foreach my $i ( @$host_service_measure_opts ){
		my ($host, $service, $measure, $opts) = @$i;
		my $measuretype = $$measure2measuretype{$measure};

		my $f;
		if( $measuretype eq 'agent' ){
			my $f = "$WORKDIR/ncrtagent/$host/conf/$filtertype/$filtertype.$host.$service";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach my $rule ( @rules ){
				next unless $host =~ $rule->[0];
				next unless $service =~ $rule->[1];
				print $h $rule->[2], "\n";
			}
			close $h;
			unlink $f unless -s $f;
		}

		foreach my $master ( @ncrtmasters ){
			my $f = "$WORKDIR/ncrtmaster/$master/conf/$filtertype/$filtertype.$host.$service";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach my $rule ( @rules ){
				next unless $host =~ $rule->[0];
				next unless $service =~ $rule->[1];
				print $h $rule->[2], "\n";
			}
			close $h;
			unlink $f unless -s $f;
		}
	}
}

sub generate_masterconf_for_filter ($$$@) {
	my ($filtertype, $measure2measuretype, $host_service_measure_opts, @masters) = @_;

	##
	my $d = "$CONFDIR/$filtertype";
	opendir my $h, $d or do {
		die "$d: cannot open, stopped";
	};
	my @rules;
	foreach my $e ( sort readdir $h ){
		next unless $e =~ m"^\w.*\.filterrules$";
		my $f = "$d/$e";
		open my $i, "<", $f or do {
			die "$f: cannot open, stopped";
		};
		my $vhost_re;
		my $vservice_re;
		while( <$i> ){
			chomp;
			next if m"^\s*(#|$)";
			if( m"^===\s+(\S+)\s+(\S+)\s+===$" ){
				$vhost_re = qr"^$1$";
				$vservice_re = qr"^$2$";
			}elsif( m"^filter\s+(\S+)" ){
				my $filter = $1;

				# TODO: check filter path

				push @rules, [$vhost_re, $vservice_re, $filter];
			}else{
				die "$f:$.: illegal format, stopped";
			}
		}
		close $i;
	}
	closedir $h;

	foreach my $i ( @$host_service_measure_opts ){
		my ($host, $service, $measure, $opts) = @$i;
		my $measuretype = $$measure2measuretype{$measure};

		foreach my $master ( @ncrtmasters ){
			my $f = "$WORKDIR/ncrtmaster/$master/conf/$filtertype/$filtertype.$measure.$host.$service";
			open my $h, '>', $f or do {
				die "$f: cannot open, stopped";
			};
			foreach my $rule ( @rules ){
				next unless $host =~ $rule->[0];
				next unless $service =~ $rule->[1];
				print $h $rule->[2], "\n";
			}
			close $h;
			unlink $f unless -s $f;
		}
	}
}

my %host2service2metricfilters;
if( $plan{Step13} ){
	generate_filter_settings 
		"metricfilter",
		%measure2measuretype,
		@host_service_measure_opts;

	generate_filter_settings 
		"thresholdfilter",
		%measure2measuretype,
		@host_service_measure_opts;

	generate_masterconf_for_filter 
		"metricfilter",
		\%measure2measuretype,
		\@host_service_measure_opts;

	generate_masterconf_for_filter 
		"thresholdfilter",
		\%measure2measuretype,
		\@host_service_measure_opts;
}

######## Step8. ########
