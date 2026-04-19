$path = 'c:\eCILT\demo1\ADMINCILT\GRENVTPM003 Horarios envasado 000.csv'
$lines = Get-Content -Path $path
$header = $lines[9] -split ';'
$row = $lines[24] -split ';'
$targets = @('20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026')
foreach($date in $targets){
  $idx = [array]::IndexOf($header, $date)
  Write-Output ("DATE=" + $date + " IDX=" + $idx)
  if($idx -ge 0){
    for($i=$idx-2; $i -le $idx+3; $i++){
      $hv = if($i -ge 0 -and $i -lt $header.Length){$header[$i]} else {''}
      $rv = if($i -ge 0 -and $i -lt $row.Length){$row[$i]} else {''}
      Write-Output (("{0}: H=[{1}] R=[{2}]") -f $i, $hv, $rv)
    }
  }
  Write-Output '---'
}
