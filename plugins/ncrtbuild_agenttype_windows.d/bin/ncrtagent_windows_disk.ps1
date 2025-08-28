#!powershell

$disk = Get-Volume | ForEach-Object {
	$n = $_.DriveLetter
	if( $n -notmatch "[a-z]" ){$n = "system"}
	$avail = $_.SizeRemaining / 1024 / 1024 / 1024
	$total = $_.Size / 1024 / 1024 / 1024
	$avail_pct = 0;
	if( ($avail -gt 0) -And ($total -gt 0) ){ $avail_pct = $avail / $total * 100; }

	("disk[$n]-avail={0,0:#.##} disk[$n]-total={1,0:#.##} disk[$n]-avail-pct={2,0:#.##}" -f $avail, $total, $avail_pct)
}
$disk_perf = $disk -join " "
write-host "OK | $disk_perf"
exit 0

