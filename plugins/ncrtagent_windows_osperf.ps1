#!powershell

$cpu = Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor |
    Select Name,PercentIdleTime,PercentInterruptTime,PercentPrivilegedTime,PercentUserTime,PercentProcessorTime |
    Where-Object {$_.Name -eq "_Total"} 
$cpu_perf = ( "cpu-idle-pct={0} cpu-user-pct={1} cpu-system-pct={2}" -f $cpu[0].PercentIdleTime,
    $cpu[0].PercentUserTime, ($cpu[0].PercentInterruptTime + $cpu[0].PercentPrivilegedTime) )

$mem = Get-WmiObject Win32_OperatingSystem | Select TotalVisibleMemorySize, FreePhysicalMemory
$mem_perf = ( "mem-free={0,0:#.##} mem-total={1,0:#.##}" -f ($mem[0].FreePhysicalMemory/1024), ($mem[0].TotalVisibleMemorySize/1024) )

$proc = Get-CimInstance Win32_Process
$proc_perf = ( "procs={0}" -f $proc.Length )

$thread = Get-CimInstance Win32_Thread
$thread_perf = ( "threads={0}" -f $thread.Length )

write-host "OK | $cpu_perf $mem_perf $proc_perf $thread_perf"
exit 0

