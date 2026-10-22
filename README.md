# Controle Remoto para Android TV (protocolo oficial do Google)

Controle remoto gráfico para TVs Android TV / Google TV (testado em uma
Philips 50PUG7907/78), feito em Python + Tkinter, usando o **protocolo
oficial do Google Android TV Remote Service** — o mesmo que o app oficial
"Android TV Remote Control" usa.

Criado originalmente para contornar um controle remoto físico com defeito.

## Por que existe

Apps "remotos universais" não-oficiais costumam ter baixa latência mas
vêm cheios de anúncios. Este projeto busca a mesma baixa latência usando
uma biblioteca aberta que fala o protocolo nativo da TV, sem anúncios,
sem conta e **sem precisar deixar nenhuma porta de depuração aberta**.

## Por que não usa ADB

Uma versão anterior deste projeto usava `adb` + `monkey` (exigindo
"Depuração de rede" ligada na TV o tempo todo). Essa abordagem foi
abandonada por dois motivos:

1. **Segurança**: deixar a depuração de rede ligada expõe a TV a qualquer
   dispositivo na mesma rede.
2. **Praticidade**: o protocolo oficial (`androidtvremote2`) faz um
   **pareamento único por certificado** (como parear um Bluetooth) e
   depois disso conecta direto, sem exigir nenhuma configuração de
   desenvolvedor ligada na TV.

## Recursos

- Botões de navegação (D-pad), OK, Voltar, Home, Menu, Power, Volume,
  Canal e teclado numérico.
- Atalhos para abrir apps direto (Netflix, Prime Video, YouTube, etc. —
  edite a lista `APPS` em `remote_gui.py`).
- Campo de digitação em tempo real: o texto aparece na TV enquanto você
  digita no notebook, incluindo backspace.
- Navegação pelo teclado do notebook: setas = D-pad, Enter = OK,
  Esc = Voltar.
- Reconexão automática caso a conexão caia.

## Requisitos

- Python 3.10 ou mais recente.
- TV com Android TV / Google TV, na mesma rede Wi-Fi/local do notebook.
- **Não precisa** de ADB, nem de "Opções do desenvolvedor", nem de
  "Depuração de rede" ligada.
- VPN corporativa **desligada** no notebook durante o uso — a maioria
  das VPNs bloqueia o acesso à rede local, inclusive à TV.

## Como usar

1. Clone este repositório e instale as dependências:

   ```bash
   pip install -r requirements.txt
   ```

2. **Pareie com a TV** (só precisa fazer isso uma vez por notebook/TV):

   ```bash
   python pair.py <IP_DA_TV>
   ```

   A TV vai mostrar um código de 6 dígitos na tela. Crie o arquivo
   `config/pairing_code.txt` com esse código (o script fica esperando
   por ele), por exemplo:

   ```bash
   echo B6E003 > config/pairing_code.txt
   ```

   Isso gera `config/cert.pem` e `config/key.pem` — guarde-os com
   cuidado, são a "chave" que autentica seu notebook na TV. Nunca
   compartilhe ou versione a pasta `config/`.

3. **Abra o controle:**

   ```bash
   python remote_gui.py
   ```

## Estrutura do projeto

```
pair.py              -> pareamento inicial (roda uma vez por notebook/TV)
remote_gui.py         -> a interface gráfica do controle
requirements.txt      -> dependências (androidtvremote2)
config/               -> certificado, chave privada e IP da TV (gerado
                         localmente pelo pair.py, NUNCA versionado)
```

## Personalizando a lista de apps

Edite a lista `APPS` em `remote_gui.py` com os pacotes Android dos apps
que você usa. Para descobrir o nome de pacote de um app, use o Android
TV Remote Control oficial ou consulte a loja de apps da TV.

## Aviso

Este projeto usa a biblioteca de código aberto `androidtvremote2`, que
implementa o protocolo oficial do Google para controle remoto de
Android TV, apenas para enviar comandos à sua própria TV na sua própria
rede local. Nenhum dado é coletado ou enviado para terceiros.
