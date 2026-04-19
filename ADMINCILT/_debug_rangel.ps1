$path = 'c:\eCILT\demo1\ADMINCILT\GRENVTPM003 Horarios envasado 000.csv'
$lines = Get-Content -Path $path
$header = $lines[9] -split ';'
$targets = @('20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026')
$rows = @(20,24,25)
foreach($lineNo in $rows){
  $row = $lines[$lineNo] -split ';'
  Write-Output ('LINE=' + ($lineNo+1) + ' NAME=' + $row[3])
  foreach($date in $targets){
    $idx = [array]::IndexOf($header, $date)
    $horario = ''
    $maquina = ''
    $codigo = ''
    if($idx - 1 -ge 0 -and $idx - 1 -lt $row.Length){ $horario = $row[$idx-1] }
    if($idx -ge 0 -and $idx -lt $row.Length){ $maquina = $row[$idx] }
    if($idx + 1 -ge 0 -and $idx + 1 -lt $row.Length){ $codigo = $row[$idx+1] }
    Write-Output ('  ' + $date + ' => horario=[' + $horario + '] maquina=[' + $maquina + '] codigo=[' + $codigo + ']')
  }
  Write-Output '---'
}
