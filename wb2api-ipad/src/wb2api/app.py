import asyncio
import json
from pathlib import Path

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW

from . import ios_runtime


class WB2API(toga.App):
    def startup(self):
        self.server_state = None
        self.status = toga.Label("正在启动本机服务…", style=Pack(padding=8))
        self.webview = toga.WebView(
            on_webview_load=self.on_webview_load,
            style=Pack(flex=1),
        )

        controls = toga.Box(
            children=[
                toga.Button("后退", on_press=self.go_back, style=Pack(padding=4)),
                toga.Button("前进", on_press=self.go_forward, style=Pack(padding=4)),
                toga.Button("刷新", on_press=self.reload, style=Pack(padding=4)),
            ],
            style=Pack(direction=ROW, padding=6),
        )
        content = toga.Box(
            children=[self.status, controls, self.webview],
            style=Pack(direction=COLUMN, flex=1),
        )

        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = content
        self.main_window.show()

    async def on_running(self):
        asyncio.create_task(self.start_local_service())

    async def start_local_service(self):
        self.status.text = "正在启动 FastAPI 与 SQLite…"
        try:
            state = await asyncio.to_thread(
                ios_runtime.start,
                str(Path(self.paths.config) / "wb2api"),
            )
            self.server_state = state
            self.status.text = f"本机 API 运行中 · {state['origin']}/v1"
            self.webview.url = f"{state['origin']}/admin?desktop=1&android=1"
        except Exception as error:
            self.status.text = f"服务启动失败：{error}"

    async def on_webview_load(self, widget, **kwargs):
        state = self.server_state
        if state is None or not widget.url or not widget.url.startswith(state["origin"]):
            return

        token = json.dumps(state["token"])
        origin = json.dumps(state["origin"])
        script = f"""
        (() => {{
          window.WBAndroid = {{
            sessionToken: () => {token},
            status: () => JSON.stringify({{alive:true, responsive:true, origin:{origin}}}),
            setTheme: () => {{}},
            openSystemSettings: () => false,
            restartService: () => location.reload(),
            saveText: (id, filename, text, mime) => {{
              const finish = (ok, message) => window.WBMobile?.saveResult(id, ok, message);
              try {{
                const file = new File([text], filename, {{type:mime || "text/plain"}});
                if (navigator.share && navigator.canShare && navigator.canShare({{files:[file]}})) {{
                  navigator.share({{files:[file], title:filename}})
                    .then(() => finish(true))
                    .catch(error => finish(false, error.message));
                  return true;
                }}
                const link = document.createElement("a");
                link.href = URL.createObjectURL(file);
                link.download = filename;
                link.click();
                setTimeout(() => {{ URL.revokeObjectURL(link.href); finish(true); }}, 500);
                return true;
              }} catch (error) {{
                finish(false, error.message);
                return false;
              }}
            }}
          }};
          window.WBMobileSettings = {{start: () => {{
            document.querySelector('[data-tab="sync"]')?.remove();
            document.getElementById("panel-sync")?.remove();
            document.querySelector('[data-tab="maintenance"]')?.remove();
            document.getElementById("panel-maintenance")?.remove();
            document.getElementById("appVersion")?.remove();
            document.querySelector(".topbar-update")?.remove();
            document.getElementById("panel-sync")?.querySelectorAll("input[type=file]").forEach(input => input.remove());
            document.getElementById("panel-sync")?.querySelectorAll(".mobile-setting-actions button").forEach(button => button.remove());
          }}}};
          if (window.WBDesktop) window.WBDesktop.checkUpdatesAtStartup = () => {{}};
          if (window.WBMobile) {{
            window.WBMobile.initialize({token});
            const mode = document.getElementById("topbarMode");
            if (mode) mode.textContent = "iPad 本机运行";
          }}
        }})();
        """
        await widget.evaluate_javascript(script)

    def go_back(self, widget):
        self.webview.evaluate_javascript("history.back()")

    def go_forward(self, widget):
        self.webview.evaluate_javascript("history.forward()")

    def reload(self, widget):
        self.webview.evaluate_javascript("location.reload()")

    async def on_exit(self):
        await asyncio.to_thread(ios_runtime.stop)
        return True


def main():
    return WB2API()
