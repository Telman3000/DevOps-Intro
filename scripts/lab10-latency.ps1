# Lab 10 — measure warm / cold latency against a QuickNotes URL
# Usage:
#   .\scripts\lab10-latency.ps1 -Url https://YOUR.onrender.com
#   .\scripts\lab10-latency.ps1 -Url https://YOUR.onrender.com -Mode cold
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [ValidateSet('warm', 'cold', 'note')][string]$Mode = 'warm',
  [int]$WarmRuns = 5
)

$health = "$Url".TrimEnd('/') + '/health'
$notes = "$Url".TrimEnd('/') + '/notes'

function Invoke-TimedGet([string]$u) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 180
    $sw.Stop()
    return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3); Body = $r.Content }
  } catch {
    $sw.Stop()
    return [pscustomobject]@{ Ok = $false; Status = 0; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3); Body = $_.Exception.Message }
  }
}

switch ($Mode) {
  'warm' {
    $times = @()
    1..$WarmRuns | ForEach-Object {
      $m = Invoke-TimedGet $health
      Write-Host ("warm#{0}: {1}s status={2}" -f $_, $m.Seconds, $m.Status)
      if ($m.Ok) { $times += $m.Seconds }
    }
    $sorted = $times | Sort-Object
    $p50 = $sorted[[math]::Floor(($sorted.Count - 1) * 0.5)]
    Write-Host ("warm p50 ({0} ok): {1}s" -f $times.Count, $p50)
  }
  'cold' {
    Write-Host "Make sure the service has been idle >= 15-20 min (spun down)."
    $m = Invoke-TimedGet $health
    Write-Host ("cold: {0}s status={1} body={2}" -f $m.Seconds, $m.Status, $m.Body)
  }
  'note' {
    $body = '{"title":"lab10-persist","body":"spin-down test"}'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-WebRequest -Uri $notes -Method POST -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 180
    $sw.Stop()
    Write-Host ("POST /notes: {0}s status={1} body={2}" -f ([math]::Round($sw.Elapsed.TotalSeconds, 3)), $r.StatusCode, $r.Content)
    Write-Host "Now idle 20+ minutes, then: .\scripts\lab10-latency.ps1 -Url $Url -Mode warm"
    Write-Host "and curl $notes to see if the note survived spin-down."
  }
}
