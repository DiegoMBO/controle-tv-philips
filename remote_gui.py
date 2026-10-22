"""
Controle remoto da TV via protocolo oficial do Google (Android TV Remote
Service), em Tkinter. Requer pareamento previo (veja pair.py).

Vantagem sobre a versao PowerShell/ADB anterior: nao depende de ADB nem de
"Depuracao de rede" ligada na TV - usa o mesmo protocolo do app oficial do
Google, com pareamento por certificado (como um Bluetooth). Mais seguro e
nao exige lembrar de desligar nada na TV depois de usar.
"""

import asyncio
import sys
import threading
import tkinter as tk
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

APPS = [
    ("Netflix", "com.netflix.ninja"),
    ("Prime Video", "com.amazon.amazonvideo.livingroom"),
    ("YouTube", "com.google.android.youtube.tv"),
    ("Crunchyroll", "com.crunchyroll.crunchyroid"),
    ("Spotify", "com.spotify.tv.android"),
    ("Max", "com.wbd.stream"),
]

BG = "#1e1e1e"
BTN_BG = "#323232"
BTN_FG = "white"
ACCENT_RED = "#822828"
ACCENT_BLUE = "#0078aa"
LABEL_FG = "#969696"
STATUS_OK = "#64b464"
STATUS_BAD = "#c86060"


class RemoteApp:
    def __init__(self) -> None:
        if not IP_FILE.exists() or not CERT_FILE.exists() or not KEY_FILE.exists():
            print("Nenhum pareamento encontrado. Rode primeiro: python pair.py <IP_DA_TV>")
            sys.exit(1)

        self.host = IP_FILE.read_text().strip()
        self.connected = False

        self.loop = asyncio.new_event_loop()
        self.remote = AndroidTVRemote(
            client_name="Controle Python",
            certfile=str(CERT_FILE),
            keyfile=str(KEY_FILE),
            host=self.host,
            loop=self.loop,
        )

        self.loop_thread = threading.Thread(target=self._run_loop, daemon=True)
        self.loop_thread.start()
        asyncio.run_coroutine_threadsafe(self._connect(), self.loop)

        self.root = tk.Tk()
        self.root.title(f"Controle Remoto - {self.host}")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)
        self.root.geometry("1040x430")

        self._build_ui()
        self._bind_global_keys()

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # --- asyncio / comunicacao com a TV -----------------------------------

    def _run_loop(self) -> None:
        asyncio.set_event_loop(self.loop)
        self.loop.run_forever()

    async def _connect(self) -> None:
        try:
            await self.remote.async_connect()
            self.connected = True
            self.remote.keep_reconnecting()
            self.root.after(0, self._set_status, f"Conectado a {self.host}", STATUS_OK)
        except InvalidAuth:
            self.root.after(
                0, self._set_status,
                "Pareamento invalido - rode 'python pair.py' de novo", STATUS_BAD,
            )
        except (CannotConnect, ConnectionClosed) as exc:
            self.root.after(0, self._set_status, f"Nao foi possivel conectar: {exc}", STATUS_BAD)

    def send_key(self, key: str) -> None:
        if not self.connected:
            return
        self.loop.call_soon_threadsafe(self.remote.send_key_command, key)

    def send_text(self, text: str) -> None:
        if not self.connected or not text:
            return
        self.loop.call_soon_threadsafe(self.remote.send_text, text)

    def launch_app(self, pkg: str) -> None:
        if not self.connected:
            return
        self.loop.call_soon_threadsafe(self.remote.send_launch_app_command, pkg)

    # --- construcao da interface -------------------------------------------

    def _set_status(self, text: str, color: str) -> None:
        self.lbl_status.config(text=text, fg=color)

    def _btn(self, parent, text, key, x, y, w, h, bg=BTN_BG, fontsize=11):
        b = tk.Button(
            parent, text=text, bg=bg, fg=BTN_FG, activebackground="#444444",
            relief="flat", takefocus=0, font=("Segoe UI", fontsize, "bold"),
            command=lambda: self.send_key(key),
        )
        b.place(x=x, y=y, width=w, height=h)
        return b

    def _label(self, parent, text, x, y, w, color=LABEL_FG, size=8):
        tk.Label(parent, text=text, bg=BG, fg=color, font=("Segoe UI", size)).place(x=x, y=y, width=w)

    def _build_ui(self) -> None:
        root = self.root

        # Linha superior
        self._btn(root, "POWER", "POWER", 15, 15, 150, 40, bg=ACCENT_RED)
        self._btn(root, "HOME", "HOME", 180, 15, 150, 40)
        self._btn(root, "VOLTAR", "BACK", 345, 15, 150, 40)
        self._btn(root, "MENU", "MENU", 510, 15, 150, 40)

        # Rotulos
        self._label(root, "NAVEGACAO", 62, 95, 230)
        self._label(root, "VOLUME", 312, 95, 140)
        self._label(root, "CANAL", 472, 95, 140)
        self._label(root, "NUMERICO", 632, 95, 180)
        self._label(root, "APPS", 862, 95, 160)

        # D-pad
        self._btn(root, "^", "DPAD_UP", 142, 115, 70, 40, fontsize=14)
        self._btn(root, "<", "DPAD_LEFT", 72, 165, 70, 40, fontsize=14)
        self._btn(root, "OK", "DPAD_CENTER", 142, 165, 70, 40, fontsize=12)
        self._btn(root, ">", "DPAD_RIGHT", 212, 165, 70, 40, fontsize=14)
        self._btn(root, "v", "DPAD_DOWN", 142, 215, 70, 40, fontsize=14)

        # Volume
        self._btn(root, "VOL +", "VOLUME_UP", 312, 115, 140, 40)
        self._btn(root, "MUDO", "MUTE", 312, 165, 140, 40)
        self._btn(root, "VOL -", "VOLUME_DOWN", 312, 215, 140, 40)

        # Canal
        self._btn(root, "CANAL +", "CHANNEL_UP", 472, 140, 140, 40)
        self._btn(root, "CANAL -", "CHANNEL_DOWN", 472, 190, 140, 40)

        # Numerico
        num = 1
        for r in range(3):
            for c in range(3):
                x = 632 + c * 77
                y = 115 + r * 50
                self._btn(root, str(num), str(num), x, y, 66, 40)
                num += 1
        self._btn(root, "0", "0", 709, 265, 66, 40)

        # Apps
        y = 115
        for name, pkg in APPS:
            b = tk.Button(
                root, text=name, bg=BTN_BG, fg=BTN_FG, activebackground="#444444",
                relief="flat", takefocus=0, font=("Segoe UI", 10),
                command=lambda p=pkg: self.launch_app(p),
            )
            b.place(x=862, y=y, width=160, height=34)
            y += 42

        # Digitacao em tempo real
        self._label(root, "DIGITAR AO VIVO (aparece na TV enquanto voce digita)", 15, 325, 700, size=9)
        self.entry = tk.Entry(root, font=("Segoe UI", 18))
        self.entry.place(x=15, y=345, width=860, height=40)

        btn_clear = tk.Button(
            root, text="Limpar", bg=BTN_BG, fg=BTN_FG, activebackground="#444444",
            relief="flat", takefocus=0, font=("Segoe UI", 11),
            command=self._clear_entry,
        )
        btn_clear.place(x=895, y=345, width=130, height=40)

        self.entry.bind("<KeyPress>", self._on_entry_keypress)
        self.entry.bind("<BackSpace>", self._on_entry_backspace)
        self.entry.bind("<Return>", self._on_entry_return)

        # Status
        self.lbl_status = tk.Label(
            root, text=f"Conectando a {self.host}...", bg=BG, fg=LABEL_FG, font=("Segoe UI", 8),
        )
        self.lbl_status.place(x=15, y=395, width=1000)

    def _clear_entry(self) -> None:
        self.entry.delete(0, tk.END)
        self.entry.focus_set()

    # --- digitacao em tempo real na caixa de busca -------------------------

    def _on_entry_keypress(self, event) -> None:
        ch = event.char
        if ch and ch.isprintable() and len(ch) == 1:
            self.send_text(ch)

    def _on_entry_backspace(self, event) -> None:
        if self.entry.get():
            self.send_key("DEL")

    def _on_entry_return(self, event):
        self.send_key("ENTER")
        return "break"

    # --- navegacao pelo teclado do notebook em qualquer lugar da janela ----

    def _bind_global_keys(self) -> None:
        self.root.bind_all("<Up>", lambda e: self.send_key("DPAD_UP"))
        self.root.bind_all("<Down>", lambda e: self.send_key("DPAD_DOWN"))
        self.root.bind_all("<Left>", self._on_global_left)
        self.root.bind_all("<Right>", self._on_global_right)
        self.root.bind_all("<Return>", self._on_global_return)
        self.root.bind_all("<Escape>", lambda e: self.send_key("BACK"))

    def _entry_focused(self) -> bool:
        return self.root.focus_get() is self.entry

    def _on_global_left(self, event) -> None:
        if not self._entry_focused():
            self.send_key("DPAD_LEFT")

    def _on_global_right(self, event) -> None:
        if not self._entry_focused():
            self.send_key("DPAD_RIGHT")

    def _on_global_return(self, event) -> None:
        if not self._entry_focused():
            self.send_key("DPAD_CENTER")

    # --- encerramento -------------------------------------------------------

    def _on_close(self) -> None:
        try:
            self.loop.call_soon_threadsafe(self.remote.disconnect)
        except Exception:
            pass
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    RemoteApp().run()
