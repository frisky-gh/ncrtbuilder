use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;
use IO::Socket::INET;
use LWP::UserAgent;
use Time::HiRes qw(time sleep);

plan skip_all => 'Linux process supervision test' unless $^O eq 'linux';
my $home = tempdir(CLEANUP => 1);
make_path("$home/bin", "$home/daemonconf", "$home/plugins");
local $ENV{HOME} = $home;
my $daemon = "$home/bin/ncrtagentdaemon";
open my $source, '<', "$FindBin::Bin/../plugins/ncrtbuild_agenttype_linux.d/bin/ncrtagentdaemon" or die $!;
my $code = do { local $/; <$source> };
close $source;
# Exercise the production loop with shorter heartbeat intervals.
$code =~ s/\$PING_RENEWAL_SEC = 900/\$PING_RENEWAL_SEC = 2/ or die;
$code =~ s/\$PONG_EXPIRATION_SEC = 180/\$PONG_EXPIRATION_SEC = 4/ or die;
open my $out, '>', $daemon or die $!;
print $out $code;
close $out;

my $reservation = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1,
) or die $!;
my $port = $reservation->sockport;
open my $conf, '>', "$home/daemonconf/ncrtagentdaemon.conf" or die $!;
print $conf "listen_address=127.0.0.1\nlisten_port=$port\ndaemon_user=\nDEBUG=1\nallow=127.0.0.1\n";
close $conf;
$reservation->close;
open my $plugin, '>', "$home/plugins/ncrtagent_linux_test" or die $!;
print $plugin "#!/bin/sh\nprintf 'value=42\\nmessage=measured\\n'\n";
close $plugin;
chmod 0755, "$home/plugins/ncrtagent_linux_test";

my $pidfile = "$home/.ncrt/ncrtagentdaemon.pid";
my $logfile = "$home/.ncrt/ncrtagentdaemon.log";
my $parent;
my $ua = LWP::UserAgent->new(timeout => 2);
$ua->env_proxy;
$ua->no_proxy('127.0.0.1');
my $url = "http://127.0.0.1:$port";

sub contents {
	my ($file) = @_;
	open my $fh, '<', $file or return '';
	local $/;
	return <$fh> // '';
}

sub worker {
	return unless $parent;
	my @children = split ' ', contents("/proc/$parent/task/$parent/children");
	foreach my $pid (@children) {
		return $pid if contents("/proc/$pid/cmdline") =~ /^ncrtagentdaemon \[child\]/;
	}
	return;
}

sub until_true {
	my ($test, $seconds) = @_;
	my $deadline = time + $seconds;
	while( time < $deadline ){
		return 1 if $test->();
		sleep 0.1;
	}
	return 0;
}

sub gone {
	my ($pid) = @_;
	return 1 unless -e "/proc/$pid/stat";
	return contents("/proc/$pid/stat") =~ /^\d+ \(.*\) Z /;
}

END {
	$parent ||= int(contents($pidfile) || 0);
	if( $parent > 1 and not gone($parent) ){
		my $child = worker();
		kill 'TERM', $parent;
		unless( until_true(sub { gone($parent) }, 25) ){
			kill 'KILL', -$child if $child;
			kill 'KILL', $parent;
		}
	}
}

is(system($^X, $daemon, 'daemon') >> 8, 0, 'daemon starts');
$parent = int(contents($pidfile) || 0);
ok($parent > 1, 'startup returns with supervisor PID file ready') or BAIL_OUT('no supervisor');
is(system($^X, $daemon, 'alive') >> 8, 0, 'alive identifies supervisor');
ok(until_true(sub { worker() && $ua->get("$url/ping")->is_success }, 5), 'worker serves HTTP');
my $child = worker();
ok($child && $child != $parent, 'separate processing child');
my @stat = split ' ', contents("/proc/$parent/stat");
is($stat[5], $parent, 'supervisor is a detached session leader');
is(system($^X, $daemon, 'daemon') >> 8, 255, 'duplicate startup rejected');
is($ua->get("$url/ping")->content, "OK\n", 'existing ping response preserved');
my $measure = $ua->get("$url/measure/test/localhost/service");
is($measure->code, 200, 'measurement subprocess succeeds');
is($measure->content, "value=42\nmessage=measured\n", 'measurement output preserved');
ok(until_true(sub { contents($logfile) =~ /received pong/ }, 8), 'idle worker answers periodic signal')
	or diag contents($logfile);
is(worker(), $child, 'healthy worker is not restarted');

rename $logfile, "$logfile.old" or die $!;
is(system($^X, $daemon, 'hup') >> 8, 0, 'reload accepted');
ok(until_true(sub {
	$ua->get("$url/ping");
	return contents($logfile) =~ /req:.*path=\/ping/;
}, 5), 'reload reopens worker log');
is(worker(), $child, 'reload preserves processing child');

kill 'KILL', $child;
ok(until_true(sub { my $pid = worker(); $pid && $pid != $child }, 5), 'crashed worker restarted');
$child = worker();
ok($ua->get("$url/ping")->is_success, 'HTTP works after crash recovery');

kill 'STOP', $child;
ok(until_true(sub { my $pid = worker(); $pid && $pid != $child }, 22), 'unresponsive worker forcibly replaced');
ok(gone($child), 'stopped worker killed and reaped');
$child = worker();
ok($ua->get("$url/ping")->is_success, 'HTTP works after hang recovery');
is(int(contents($pidfile)), $parent, 'supervisor PID remains stable');

my $stalled = IO::Socket::INET->new(
	PeerAddr => '127.0.0.1', PeerPort => $port, Timeout => 2,
) or die $!;
print $stalled "GET /ping HTTP/1.0\r\n";
sleep 3;
close $stalled;
ok(until_true(sub { $ua->get("$url/ping")->is_success }, 5), 'signals during incomplete requests preserve service');

$child = worker();
kill 'STOP', $child;
is(system($^X, $daemon, 'kill') >> 8, 0, 'stop waits for forced termination of hung worker');
ok(gone($child), 'stop removes processing child');
ok(!-e $pidfile, 'stop removes supervisor PID file');
is(system($^X, $daemon, 'alive') >> 8, 1, 'alive fails after stop');
$parent = undef;

# A bind failure must be reported to the startup caller, not hidden after fork.
is(system($^X, $daemon, 'daemon') >> 8, 0, 'daemon can start again after stop');
$parent = int(contents($pidfile) || 0);
is(system($^X, $daemon, 'kill') >> 8, 0, 'restarted daemon stops');
$parent = undef;
my $occupied = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1', LocalPort => $port, Listen => 1, ReuseAddr => 1,
) or die $!;
ok((system($^X, $daemon, 'daemon') >> 8) != 0, 'bind failure reported synchronously');
ok(!-e $pidfile, 'failed startup leaves no PID file');
$occupied->close;
done_testing;
