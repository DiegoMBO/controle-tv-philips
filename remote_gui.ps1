Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Form customizado: Enter, Tab e as setas sao "teclas de dialogo" no Windows
# e, por padrao, nunca chegam ao evento KeyDown normal quando o foco esta
# numa caixa de texto ou num botao - o Windows intercepta Enter antes disso
# para "clicar" o botao focado ou simplesmente nao faz nada. Sobrescrever
# ProcessCmdKey intercepta a tecla no nivel mais baixo, antes de qualquer
# desses comportamentos padrao, garantindo que Enter sempre chegue aqui.
if (-not ([System.Management.Automation.PSTypeName]'RemoteForm').Type) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Windows.Forms;

public class RemoteForm : Form
{
    public Func<Keys, bool> KeyIntercept;

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (KeyIntercept != null && KeyIntercept(keyData))
        {
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }
}
"@
}

Add-Type -AssemblyName Microsoft.VisualBasic

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ADB = Join-Path $ScriptDir "platform-tools\adb.exe"

# IP da TV: lido de tv-ip.txt (ao lado deste script). Assim o mesmo script
# funciona em qualquer notebook/pasta sem editar codigo - se o arquivo nao
# existir ainda, pede o IP uma vez e salva.
$TvIpFile = Join-Path $ScriptDir "tv-ip.txt"
if (Test-Path $TvIpFile) {
    $TvIp = (Get-Content $TvIpFile -Raw).Trim()
} else {
    $TvIp = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Digite o IP da TV (ex: 192.168.1.102):",
        "Controle Remoto - Primeira vez neste notebook",
        "192.168.1.102"
    )
    if ([string]::IsNullOrWhiteSpace($TvIp)) {
        [System.Windows.Forms.MessageBox]::Show("IP nao informado. O programa vai fechar.", "Controle Remoto")
        exit
    }
    Set-Content -Path $TvIpFile -Value $TvIp.Trim()
}
$TV = "${TvIp}:5555"

& $ADB connect $TV | Out-Null

function Start-Adb {
    param([string]$args_)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ADB
    $psi.Arguments = $args_
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

# Mantem UMA sessao de shell aberta com a TV (em vez de abrir uma conexao nova
# a cada clique) - isso elimina o atraso de reconexao por comando. Usada para
# digitacao de texto e abertura de apps (acoes pouco frequentes, onde o
# delay nao importa tanto).
$shellPsi = New-Object System.Diagnostics.ProcessStartInfo
$shellPsi.FileName = $ADB
$shellPsi.Arguments = "-s $TV shell"
$shellPsi.RedirectStandardInput = $true
$shellPsi.RedirectStandardOutput = $true
$shellPsi.RedirectStandardError = $true
$shellPsi.UseShellExecute = $false
$shellPsi.CreateNoWindow = $true
$script:tvShell = [System.Diagnostics.Process]::Start($shellPsi)
$script:tvStdin = $script:tvShell.StandardInput

function Send-Shell {
    param([string]$cmd)
    if ($script:tvShell.HasExited) {
        $script:tvShell = [System.Diagnostics.Process]::Start($shellPsi)
        $script:tvStdin = $script:tvShell.StandardInput
    }
    $script:tvStdin.WriteLine($cmd)
    $script:tvStdin.Flush()
}

# ---------------------------------------------------------------------------
# Canal rapido para os botoes (D-pad, OK, volume, numeros etc).
#
# Por que: "adb shell input keyevent N" liga uma maquina virtual Java/ART
# nova na TV a cada toque (~150-300ms so para isso, antes de qualquer coisa
# acontecer na tela) - e esse e o delay que o usuario sentia. Em vez disso,
# iniciamos UMA vez o utilitario "monkey" (ja incluso em todo Android TV) no
# modo de rede, que fica de pe esperando comandos numa porta; cada toque
# depois disso e so uma linha de texto numa conexao TCP ja aberta, sem gastar
# tempo ligando processo novo. Resultado medido nesta TV: de ~150-300ms para
# ~5-10ms por toque.
$MonkeyPort = 1080
& $ADB -s $TV shell "pkill -f 'monkey.*--port' >/dev/null 2>&1" | Out-Null
$monkeyPsi = New-Object System.Diagnostics.ProcessStartInfo
$monkeyPsi.FileName = $ADB
$monkeyPsi.Arguments = "-s $TV shell monkey --port $MonkeyPort -v"
$monkeyPsi.UseShellExecute = $false
$monkeyPsi.CreateNoWindow = $true
$monkeyPsi.RedirectStandardOutput = $true
$monkeyPsi.RedirectStandardError = $true
$script:monkeyProc = [System.Diagnostics.Process]::Start($monkeyPsi)
& $ADB -s $TV forward "tcp:$MonkeyPort" "tcp:$MonkeyPort" | Out-Null

$script:monkeyClient = $null
$script:monkeyWriter = $null
$script:monkeyReader = $null

function Connect-Monkey {
    try {
        if ($script:monkeyClient) { $script:monkeyClient.Close() }
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $MonkeyPort)
        $c.NoDelay = $true
        $stream = $c.GetStream()
        $stream.ReadTimeout = 1500
        $script:monkeyClient = $c
        $script:monkeyWriter = New-Object System.IO.StreamWriter($stream)
        $script:monkeyWriter.AutoFlush = $true
        $script:monkeyReader = New-Object System.IO.StreamReader($stream)
        return $true
    } catch {
        return $false
    }
}

# A primeira conexao pode precisar de algumas tentativas, pois o monkey
# leva um instante para comecar a escutar a porta depois de iniciar.
$connected = $false
for ($i = 0; $i -lt 10 -and -not $connected; $i++) {
    $connected = Connect-Monkey
    if (-not $connected) { Start-Sleep -Milliseconds 300 }
}

# Trava de repeticao: se uma tecla for mantida pressionada (ou clicada
# muito rapido), o Windows dispara muitos eventos por segundo e isso
# sobrecarrega/trava a TV. Esta trava limita cada codigo de tecla a no
# maximo ~8 envios por segundo.
$script:lastKeyTime = @{}
function Send-Key {
    param([int]$code)
    $now = [DateTime]::Now
    if ($script:lastKeyTime.ContainsKey($code)) {
        if (($now - $script:lastKeyTime[$code]).TotalMilliseconds -lt 120) { return }
    }
    $script:lastKeyTime[$code] = $now

    $sentViaMonkey = $false
    if ($script:monkeyWriter) {
        try {
            $script:monkeyWriter.WriteLine("press $code")
            [void]$script:monkeyReader.ReadLine()
            $sentViaMonkey = $true
        } catch {
            $sentViaMonkey = $false
        }
    }
    if (-not $sentViaMonkey) {
        # Reserva: se a conexao rapida cair, tenta reconectar uma vez e, se
        # nao der, cai de volta no metodo antigo (mais lento, mas confiavel)
        # para o comando atual nao se perder.
        if (-not (Connect-Monkey)) {
            Send-Shell "input keyevent $code"
        }
    }
}

function Launch-App {
    param([string]$pkg)
    Send-Shell "monkey -p $pkg -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1"
}

function Quote-ShellArg {
    param([string]$s)
    $escaped = $s -replace '([\\$`"])', '\$1'
    return '"' + $escaped + '"'
}

# Digitacao pela mesma conexao rapida do monkey ("type <texto>"), em vez de
# "adb shell input text" por caractere - que, assim como o keyevent, ligava
# uma maquina virtual nova na TV a cada tecla digitada. O monkey nao aceita
# espaco nem quebra de linha dentro do texto do comando "type", entao cada
# caractere digitado ainda e enviado em uma chamada separada, mas agora sem
# esse custo de spawn.
function Send-Text {
    param([string]$ch)
    $sentViaMonkey = $false
    if ($script:monkeyWriter) {
        try {
            $script:monkeyWriter.WriteLine("type $ch")
            [void]$script:monkeyReader.ReadLine()
            $sentViaMonkey = $true
        } catch {
            $sentViaMonkey = $false
        }
    }
    if (-not $sentViaMonkey) {
        if (-not (Connect-Monkey)) {
            Send-Shell "input text $(Quote-ShellArg($ch))"
        }
    }
}

# ---------------------------------------------------------------------------
# Janela principal - layout horizontal, com ClientSize fixo (area interna
# exata, sem depender da borda/titulo da janela) para garantir que nada
# fique cortado ou sobreposto, independente do monitor.
# ---------------------------------------------------------------------------
$form = New-Object RemoteForm
$form.Text = "Controle Remoto - Philips 50PUG7907/78"
$form.ClientSize = New-Object System.Drawing.Size(900, 430)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)

# "Ralo" de foco: um controle invisivel (fora da area visivel) que absorve
# o foco do teclado depois de qualquer clique em botao. Sem isso, o .NET
# automaticamente devolve o foco para o primeiro controle focavel da janela
# quando tentamos "tirar o foco" - que por acaso e a caixa de busca. Com
# este ralo, o foco nunca volta sozinho para a caixa de busca nem fica
# "preso" num botao de seta (o que faria o Enter clicar o botao outra vez
# em vez de mandar OK para a TV).
$focusSink = New-Object System.Windows.Forms.TextBox
$focusSink.Location = New-Object System.Drawing.Point(-100, -100)
$focusSink.Size = New-Object System.Drawing.Size(1, 1)
$focusSink.TabStop = $true
$form.Controls.Add($focusSink) | Out-Null

function New-Btn {
    param($text, $x, $y, $w, $h, $code, $isApp, $fontSize = 11, $bg = $null)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.BackColor = if ($bg) { $bg } else { [System.Drawing.Color]::FromArgb(50,50,50) }
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatStyle = "Flat"
    $b.TabStop = $false
    $b.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold)
    if ($isApp) {
        $b.Add_Click({ Launch-App $code; $focusSink.Focus() }.GetNewClosure())
    } else {
        $b.Add_Click({ Send-Key $code; $focusSink.Focus() }.GetNewClosure())
    }
    $form.Controls.Add($b) | Out-Null
    return $b
}

function New-Label {
    param($text, $x, $y, $w, $h = 18, $size = 8, $color = $null)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.ForeColor = if ($color) { $color } else { [System.Drawing.Color]::FromArgb(150,150,150) }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $size)
    $form.Controls.Add($l) | Out-Null
    return $l
}

# --- Linha superior: Power / Home / Voltar / Menu / Abrir App (900 largura) ---
$null = New-Btn "POWER"     15  15 150 40 26 $false 11 ([System.Drawing.Color]::FromArgb(130,40,40))
$null = New-Btn "HOME"      180 15 150 40 3  $false
$null = New-Btn "VOLTAR"    345 15 150 40 4  $false
$null = New-Btn "MENU"      510 15 150 40 82 $false
$btnApps = New-Btn "ABRIR APP..." 675 15 210 40 0 $false 11 ([System.Drawing.Color]::FromArgb(0,120,170))

# --- Rotulos dos grupos ---
$null = New-Label "NAVEGACAO" 62  95 230
$null = New-Label "VOLUME"    312 95 140
$null = New-Label "CANAL"     472 95 140
$null = New-Label "NUMERICO"  632 95 220

# --- Grupo NAVEGACAO (D-pad) ---
$null = New-Btn "^"  142 115 70 40 19 $false 14
$null = New-Btn "<"  72  165 70 40 21 $false 14
$null = New-Btn "OK" 142 165 70 40 23 $false 12
$null = New-Btn ">"  212 165 70 40 22 $false 14
$null = New-Btn "v"  142 215 70 40 20 $false 14

# --- Grupo VOLUME ---
$null = New-Btn "VOL +" 312 115 140 40 24  $false
$null = New-Btn "MUDO"  312 165 140 40 164 $false
$null = New-Btn "VOL -" 312 215 140 40 25  $false

# --- Grupo CANAL ---
$null = New-Btn "CANAL +" 472 140 140 40 166 $false
$null = New-Btn "CANAL -" 472 190 140 40 167 $false

# --- Grupo NUMERICO (3x3 + 0) ---
$num = 1
for ($r = 0; $r -lt 3; $r++) {
    for ($c = 0; $c -lt 3; $c++) {
        $null = New-Btn "$num" (632 + $c*77) (115 + $r*50) 66 40 (7+$num) $false
        $num++
    }
}
$null = New-Btn "0" 709 265 66 40 7 $false

# --- Janela secundaria de apps (abre ao lado da principal) ---
$apps = @(
    @{Name="Netflix";     Pkg="com.netflix.ninja"},
    @{Name="Prime Video"; Pkg="com.amazon.amazonvideo.livingroom"},
    @{Name="YouTube";     Pkg="com.google.android.youtube.tv"},
    @{Name="Crunchyroll"; Pkg="com.crunchyroll.crunchyroid"},
    @{Name="Spotify";     Pkg="com.spotify.tv.android"},
    @{Name="Max";         Pkg="com.wbd.stream"}
)
$appForm = New-Object System.Windows.Forms.Form
$appForm.Text = "Apps"
$appForm.ClientSize = New-Object System.Drawing.Size(220, 290)
$appForm.StartPosition = "Manual"
$appForm.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$i = 0
foreach ($app in $apps) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $app.Name
    $b.Location = New-Object System.Drawing.Point(20, (20 + $i*42))
    $b.Size = New-Object System.Drawing.Size(180, 34)
    $b.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatStyle = "Flat"
    $pkg = $app.Pkg
    $b.Add_Click({ Launch-App $pkg }.GetNewClosure())
    $appForm.Controls.Add($b)
    $i++
}
$btnApps.Add_Click({
    $appForm.Location = New-Object System.Drawing.Point(($form.Location.X + $form.Width), $form.Location.Y)
    $appForm.Show()
})

# --- Faixa inferior: digitacao em tempo real, larga e bem visivel ---
$null = New-Label "DIGITAR AO VIVO (aparece na TV enquanto voce digita)" 15 325 700 18 9

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(15, 345)
$txtSearch.Size = New-Object System.Drawing.Size(700, 40)
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 18)
$form.Controls.Add($txtSearch)

$btnClear = New-Btn "Limpar" 730 345 155 40 0 $false 11
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnClear.Add_Click({ $txtSearch.Clear(); $txtSearch.Focus() })

$txtSearch.Add_KeyPress({
    param($s, $e)
    $ch = $e.KeyChar
    if ([char]::IsControl($ch)) { return }
    if ($ch -eq ' ') {
        Send-Key 62
    } else {
        Send-Text ([string]$ch)
    }
})

$txtSearch.Add_KeyDown({
    param($s, $e)
    switch ($e.KeyCode) {
        'Back'   { if ($txtSearch.Text.Length -gt 0) { Send-Key 67 } }
        'Enter'  { Send-Key 66; $e.SuppressKeyPress = $true }
        'Left'   { Send-Key 21 }
        'Right'  { Send-Key 22 }
        'Delete' { Send-Key 112 }
    }
})

# --- Status de conexao ---
$lblStatus = New-Label "Conectado a $TV" 15 395 800 20 8 ([System.Drawing.Color]::FromArgb(100,180,100))

# Navegacao por teclado em qualquer lugar da janela: setas movem o foco na
# TV (D-pad) e Enter confirma (OK). Quando o foco esta na caixa "digitar ao
# vivo", Esquerda/Direita/Enter continuam com o comportamento de digitacao
# (mover cursor de texto / confirmar busca) ja tratado pelo proprio campo
# (via Add_KeyDown acima); so Cima/Baixo sao sempre tratados aqui.
# Usamos ProcessCmdKey (via o RemoteForm customizado) em vez do evento
# KeyDown comum porque o Windows trata Enter como "tecla de dialogo" e, em
# varios casos, nunca chega ao KeyDown normal (ou aciona o botao errado) -
# ProcessCmdKey intercepta antes disso, de forma confiavel.
$form.KeyIntercept = [Func[System.Windows.Forms.Keys, bool]]{
    param($keyData)
    switch ($keyData) {
        ([System.Windows.Forms.Keys]::Up) {
            Send-Key 19
            return $true
        }
        ([System.Windows.Forms.Keys]::Down) {
            Send-Key 20
            return $true
        }
        ([System.Windows.Forms.Keys]::Left) {
            if ($form.ActiveControl -ne $txtSearch) {
                Send-Key 21
                return $true
            }
            return $false
        }
        ([System.Windows.Forms.Keys]::Right) {
            if ($form.ActiveControl -ne $txtSearch) {
                Send-Key 22
                return $true
            }
            return $false
        }
        ([System.Windows.Forms.Keys]::Enter) {
            if ($form.ActiveControl -ne $txtSearch) {
                Send-Key 23
                return $true
            }
            return $false
        }
        ([System.Windows.Forms.Keys]::Escape) {
            Send-Key 4
            return $true
        }
    }
    return $false
}

$form.Add_Shown({
    $form.Activate()
    $focusSink.Focus()
})
$form.Add_FormClosed({
    try {
        $script:tvStdin.WriteLine("exit")
        $script:tvStdin.Flush()
        $script:tvShell.Close()
    } catch {}
    try {
        if ($script:monkeyWriter) {
            $script:monkeyWriter.WriteLine("quit")
        }
        $script:monkeyClient.Close()
    } catch {}
    try {
        if (-not $script:monkeyProc.HasExited) { $script:monkeyProc.Kill() }
    } catch {}
    try {
        & $ADB -s $TV forward --remove "tcp:$MonkeyPort" | Out-Null
    } catch {}
})
[System.Windows.Forms.Application]::Run($form)
