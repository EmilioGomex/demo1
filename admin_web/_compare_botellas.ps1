$path = 'c:\eCILT\demo1\ADMINCILT\GRENVTPM003 Horarios envasado 000.csv'
$lines = Get-Content -Path $path
$header = $lines[9] -split ';'
$targets = @('20/4/2026','21/4/2026','22/4/2026','23/4/2026','24/4/2026','25/4/2026','26/4/2026')
function Turno($horario, $codigo){
  $s = [string]$horario
  if($s -match '07:30' -or $s -match '06:00'){ return 'Mañana' }
  if($s -match '15:30' -or $s -match '14:00' -or $s -match '16:00'){ return 'Tarde' }
  if($s -match '19:30' -or $s -match '23:30' -or $s -match '22:00'){ return 'Noche' }
  $n = 0
  if([double]::TryParse([string]$codigo, [ref]$n)){
    if($n -in @(1,4,14)){ return 'Mañana' }
    if($n -in @(5,15)){ return 'Tarde' }
    if($n -in @(7,9)){ return 'Noche' }
  }
  return $null
}
$botellas = @{}
for($i=10; $i -lt $lines.Length; $i++){
  $row = $lines[$i] -split ';'
  if($row.Length -lt 4){ continue }
  $name = $row[3]
  if(-not $name){ continue }
  foreach($date in $targets){
    $idx = [array]::IndexOf($header, $date)
    if($idx -lt 0){ continue }
    $horario = if($idx-1 -ge 0 -and $idx-1 -lt $row.Length){ $row[$idx-1] } else { '' }
    $maquina = if($idx -ge 0 -and $idx -lt $row.Length){ $row[$idx] } else { '' }
    $codigo  = if($idx+1 -ge 0 -and $idx+1 -lt $row.Length){ $row[$idx+1] } else { '' }
    $maquinaNorm = ([string]$maquina).Trim()
    if(-not $maquinaNorm){ continue }
    $skip = ([string]$horario).ToLower()
    if($skip -match 'descanso|vacaciones|feriado|evento|cumple|medico|brigada|limpieza|capacitacion|arranque|mix|calamidad'){ continue }
    $turno = Turno $horario $codigo
    if(-not $turno){ continue }
    if($maquinaNorm -match 'llenadora|etiquetadora|lavadora|bt4|bt5|pz|depa/pale|enca/desenca|despaletizadora|paletizadora|encajonadora|desencajonadora'){
      $key = "$maquinaNorm|$turno|$date"
      if(-not $botellas.ContainsKey($key)){ $botellas[$key] = New-Object System.Collections.Generic.List[string] }
      $botellas[$key].Add($name)
    }
  }
}
$machines = @('PZ','BT4','Etiquetadora','BT5','Llenadora','Lavadora','Depa/Pale','Enca/desenca','Despaletizadora','Paletizadora','Encajonadora','Desencajonadora')
foreach($m in $machines){
  Write-Output ('MACHINE=' + $m)
  foreach($t in @('Mañana','Tarde','Noche')){
    $vals = foreach($d in $targets){
      $matches = @($botellas.Keys | Where-Object { $_ -like ($m + '|' + $t + '|' + $d) })
      if($matches.Count){ ($matches | ForEach-Object { $botellas[$_] } | ForEach-Object { $_ } | Sort-Object -Unique) -join ', ' } else { '—' }
    }
    Write-Output ('  ' + $t + ' => ' + ($vals -join ' || '))
  }
  Write-Output '---'
}
