"""
Pareamento com a TV via protocolo oficial do Google (Android TV Remote Service).

Diferente da versao anterior (PowerShell + ADB), isto NAO precisa de
"Depuracao de rede" ligada na TV - usa o mesmo protocolo do app oficial
"Android TV Remote Control" do Google. O pareamento e feito uma vez (gera
um certificado salvo em config/) e depois disso o controle conecta direto,
sem exigir nenhuma configuracao de desenvolvedor na TV.

Uso:
    python pair.py <IP_DA_TV>

Como o pareamento e um protocolo interativo (a TV mostra um codigo na tela
que precisa ser digitado aqui), este script fica esperando o codigo
aparecer no arquivo config/pairing_code.txt - isso permite que outro
processo/pessoa forneca o codigo sem precisar de um terminal interativo
anexado a este processo.
"""

import asyncio
import sys
from pathlib import Path

from androidtvremote2 import (
    AndroidTVRemote,
    CannotConnect,
    ConnectionClosed,
    InvalidAuth,
)

CONFIG_DIR = Path(__file__).parent / "config"
CERT_FILE = CONFIG_DIR / "cert.pem"
KEY_FILE = CONFIG_DIR / "key.pem"
IP_FILE = CONFIG_DIR / "tv_ip.txt"
CODE_FILE = CONFIG_DIR / "pairing_code.txt"


async def wait_for_code_file() -> str:
    print("AGUARDANDO_CODIGO", flush=True)
    while not CODE_FILE.exists():
        await asyncio.sleep(0.5)
    code = CODE_FILE.read_text().strip()
    try:
        CODE_FILE.unlink()
    except FileNotFoundError:
        pass
    return code


async def pair(remote: AndroidTVRemote) -> None:
    name, mac = await remote.async_get_name_and_mac()
    print(f"Pareando com {remote.host} ({name}, {mac}) - isso pode ligar a TV...", flush=True)
    await remote.async_start_pairing()
    while True:
        code = await wait_for_code_file()
        try:
            await remote.async_finish_pairing(code)
            print("PAREAMENTO_OK", flush=True)
            return
        except InvalidAuth:
            print("Codigo invalido. Aguardando novo codigo em config/pairing_code.txt...", flush=True)
            continue
        except ConnectionClosed:
            print("Conexao perdida durante o pareamento, reiniciando...", flush=True)
            return await pair(remote)


async def main() -> None:
    if len(sys.argv) < 2:
        print("Uso: python pair.py <IP_DA_TV>")
        sys.exit(1)

    host = sys.argv[1].strip()
    CONFIG_DIR.mkdir(exist_ok=True)
    IP_FILE.write_text(host)
    try:
        CODE_FILE.unlink()
    except FileNotFoundError:
        pass

    remote = AndroidTVRemote(
        client_name="Controle Python",
        certfile=str(CERT_FILE),
        keyfile=str(KEY_FILE),
        host=host,
    )

    if await remote.async_generate_cert_if_missing():
        print("Certificado gerado em config/cert.pem e config/key.pem", flush=True)

    try:
        await pair(remote)
    except (CannotConnect, ConnectionClosed) as exc:
        print(f"ERRO: nao foi possivel conectar na TV ({exc}). Verifique o IP e a rede.", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
