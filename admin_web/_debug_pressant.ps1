$path = 'c:\eCILT\demo1\ADMINCILT\GRENVTPM003 Horarios envasado 000.csv'
$lines = Get-Content -Path $path
$header = $lines[9] -split ';'
$targets = @('20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026')
foreach($line in Select-String -Path $path -Pattern 'CRESPIN|ZAMBRANO|MORENO|TOALA' | Select-Object -First 10){
  $idxLine = $line.LineNumber - 1
  $row = $lines[$idxLine] -split ';'
  Write-Output ('LINE=' + $line.LineNumber + ' NAME=' + $row[3])
  foreach($date in $targets){
    $idx = [array]::IndexOf($header, $date)
    $horario = if($idx-1 -ge 0 -and $idx-1 -lt $row.Length){ $row[$idx-1] } else { '' }
    $maquina = if($idx -ge 0 -and $idx -lt $row.Length){ $row[$idx] } else { '' }
    $codigo  = if($idx+1 -ge 0 -and $idx+1 -lt $row.Length){ $row[$idx+1] } else { '' }
    Write-Output ('  ' + $date + ' => [' + $horario + '] [' + $maquina + '] [' + $codigo + ']')
  }
  Write-Output '---'
}
