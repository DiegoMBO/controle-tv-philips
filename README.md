# Controle Remoto para Android TV (via ADB)

Controle remoto gráfico para TVs Android TV / Google TV (testado em uma
Philips 50PUG7907/78), feito em PowerShell + Windows Forms, usando o
Android Debug Bridge (ADB) pela rede Wi-Fi — sem precisar instalar nada
na TV além de ativar a depuração de rede.

Criado originalmente para contornar um controle remoto físico com defeito.

## Por que existe

Apps "remotos universais" não-oficiais costumam ter baixa latência mas
vêm cheios de anúncios. Este projeto busca a mesma baixa latência usando
apenas ferramentas oficiais do Android (ADB + `monkey`), sem anúncios,
sem conta, sem instalar nada na TV.

## Recursos

- Botões de navegação (D-pad), OK, Voltar, Home, Menu, Power, Volume,
  Canal e teclado numérico.
- Atalhos para abrir apps direto (Netflix, Prime Video, YouTube, etc.
  — edite a lista em `remote_gui.ps1`).
- Campo de digitação em tempo real: o texto aparece na TV enquanto você
  digita no notebook, incluindo backspace.
- Navegação pelo teclado do notebook: setas = D-pad, Enter = OK,
  Esc = Voltar.
- **Baixa latência**: em vez de `adb shell input keyevent` por toque
  (que liga uma máquina virtual Java nova na TV a cada toque, ~150-300ms
  de atraso), o programa abre uma conexão TCP persistente com o
  utilitário `monkey` (nativo de todo Android TV) e envia cada tecla
  nessa conexão já aberta (~5-20ms por toque).
- 100% portátil: não precisa instalar nada no notebook, o ADB é baixado
  uma vez para dentro da própria pasta do projeto.

## Requisitos

- Windows com PowerShell (já vem de fábrica).
- TV com Android TV / Google TV, na mesma rede Wi-Fi/local do notebook.
- Na TV: **Opções do desenvolvedor → Depuração de rede (Network
  debugging)** ativada (ver passo a passo abaixo).
- VPN corporativa **desligada** no notebook durante o uso — a maioria
  das VPNs bloqueia o acesso à rede local, inclusive à TV.

## Como usar

1. Baixe/clone este repositório.
2. Dê duplo clique em **`Controle TV.vbs`**.
   - Na primeira vez, ele baixa o ADB (Android Platform Tools) oficial
     do Google para a pasta `platform-tools/` ao lado do script —
     é automático, só precisa de internet.
   - Também na primeira vez, uma caixa pede o **IP da TV**
     (ex: `192.168.1.102`). Fica salvo em `tv-ip.txt` (não versionado,
     é local de cada notebook/TV).
3. A janela do controle abre. Pronto.

### Ativando a depuração de rede na TV

1. **Configurações → Dispositivo → Sobre** → clique 7 vezes no número
   de build/versão até aparecer "Você agora é um desenvolvedor".
2. **Configurações → Dispositivo → Opções do desenvolvedor** → ative
   **Depuração de rede** (Network debugging).
3. Anote o IP da TV em **Configurações → Rede e Internet**.
4. Na primeira conexão, a TV pode mostrar um popup pedindo para
   autorizar o computador — aceite com "Sempre permitir".

### Depois de usar

Por segurança, **desligue a Depuração de rede** na TV quando terminar.
Deixada ligada, qualquer dispositivo na mesma rede pode tentar enviar
comandos para a TV.

## Estrutura do projeto

```
Controle TV.vbs     -> atalho (duplo clique para abrir, sem janela de console)
remote_gui.ps1       -> o programa (interface + lógica de comunicação com a TV)
setup.ps1            -> baixa o ADB automaticamente (roda uma vez por notebook)
.gitignore           -> ignora platform-tools/, tv-ip.txt e logs locais
tv-ip.txt.example    -> exemplo de formato do arquivo de IP (não é o real)
```

Arquivos gerados localmente e **não versionados** (cada notebook tem os
seus): `platform-tools/` (binários do ADB) e `tv-ip.txt` (IP da sua TV).

## Personalizando a lista de apps

Edite o array `$apps` em `remote_gui.ps1` com os pacotes Android dos
apps que você usa. Para descobrir o nome do pacote de um app instalado:

```powershell
.\platform-tools\adb.exe -s <IP_DA_TV>:5555 shell pm list packages -3
```

## Aviso

Este projeto usa o ADB (Android Debug Bridge), ferramenta oficial do
Google para desenvolvedores Android, apenas para enviar eventos de
teclado/toque à sua própria TV na sua própria rede local. Nenhum dado é
coletado ou enviado para terceiros.
