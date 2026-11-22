from __future__ import annotations

import json
import logging
import os
import secrets
import socket
import threading
import time
import urllib.request
from logging.handlers import RotatingFileHandler
from pathlib import Path

_server = None
_thread = None
_state = None
_lock = threading.RLock()


def _load_config(path: Path) -> dict:
    from desktop.common import atomic_json

    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("invalid app configuration")
    except (OSError, ValueError):
        config = {}

    config.setdefault("username", "ipad")
    config.setdefault("password", secrets.token_urlsafe(32))
    config.setdefault("jwt_secret", secrets.token_urlsafe(48))
    config.setdefault("port", 8790)
    atomic_json(path, config)
    return config


def _close_server() -> None:
    global _server, _thread, _state

    if _server is not None:
        _server.should_exit = True
    if _thread is not None:
        _thread.join(timeout=10)
        if _thread.is_alive():
            raise RuntimeError("本机服务仍在停止")
    _server = None
    _thread = None
    _state = None


def start(data_directory: str) -> dict:
    global _server, _thread, _state

    with _lock:
        if _thread is not None and _thread.is_alive() and _server is not None and _server.started:
            return dict(_state)
        _close_server()

        backend = Path(__file__).parent / "backend"
        import sys

        backend_path = str(backend)
        if backend_path not in sys.path:
            sys.path.insert(0, backend_path)

        data = Path(data_directory)
        data.mkdir(parents=True, exist_ok=True)
        config = _load_config(data / "config.json")
        logs = data / "logs"
        logs.mkdir(exist_ok=True)

        socket_handle = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        socket_handle.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            socket_handle.bind(("127.0.0.1", int(config.get("port", 8790))))
        except OSError:
            socket_handle.bind(("127.0.0.1", 0))
        port = socket_handle.getsockname()[1]
        socket_handle.listen(128)

        nonce = secrets.token_urlsafe(32)
        os.environ.update(
            {
                # Upstream currently uses this flag for its embedded mobile mode.
                "WORKBUDDY_IOS": "1",
                "WORKBUDDY_DESKTOP_DATA": str(data),
                "WB_DESKTOP_BOOT": nonce,
                "ADMIN_DATABASE_URL": "sqlite:///" + (data / "workbuddy.db").as_posix(),
                "ADMIN_GATEWAY_LIMIT_BACKEND": "memory",
                "ADMIN_REDIS_URL": "",
                "ADMIN_HOST": "127.0.0.1",
                "ADMIN_PORT": str(port),
                "ADMIN_USERNAME": config["username"],
                "ADMIN_PASSWORD": config["password"],
                "ADMIN_JWT_SECRET": config["jwt_secret"],
                "ADMIN_DEV_TOOLS": "0",
            }
        )
        log_handler = RotatingFileHandler(
            logs / "ios.log",
            maxBytes=4 * 1024 * 1024,
            backupCount=3,
            encoding="utf-8",
        )
        log_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
        logging.basicConfig(level=logging.INFO, handlers=[log_handler], force=True)

        # Import configuration is read at module load time.
        from admin.config import settings
        from admin.db import init_db

        settings.DATABASE_URL = "sqlite:///" + (data / "workbuddy.db").as_posix()
        settings.REDIS_URL = ""
        settings.GATEWAY_LIMIT_BACKEND = "memory"
        settings.HOST = "127.0.0.1"
        settings.PORT = port
        settings.ADMIN_USERNAME = config["username"]
        settings.ADMIN_PASSWORD = config["password"]
        settings.ADMIN_PASSWORD_FROM_ENV = True
        settings.JWT_SECRET = config["jwt_secret"]
        if not init_db():
            raise RuntimeError("无法初始化 iPad 本机 SQLite 数据库")

        import uvicorn
        from admin.server import app

        server = uvicorn.Server(
            uvicorn.Config(
                app,
                host="127.0.0.1",
                port=port,
                log_config=None,
                access_log=False,
                loop="asyncio",
                ws="none",
                proxy_headers=False,
            )
        )
        _server = server
        failures = []

        def serve() -> None:
            try:
                server.run(sockets=[socket_handle])
            except BaseException as error:
                failures.append(error)
                logging.getLogger("wb2api.ios").exception("Local API server stopped")
            finally:
                socket_handle.close()

        _thread = threading.Thread(target=serve, name="wb2api-local-api", daemon=True)
        _thread.start()
        origin = f"http://127.0.0.1:{port}"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline and _thread.is_alive():
            try:
                request = urllib.request.Request(
                    origin + "/api/app/desktop-ready",
                    headers={"X-Desktop-Boot": nonce},
                )
                with opener.open(request, timeout=1) as response:
                    if json.load(response).get("ready") is True:
                        break
            except OSError:
                time.sleep(0.15)
        else:
            error = failures[-1] if failures else RuntimeError("等待本机 API 启动超时")
            _close_server()
            raise RuntimeError(f"本机服务启动失败：{error}")

        import jwt
        from admin.config import settings as live_settings

        token = jwt.encode(
            {"sub": live_settings.ADMIN_USERNAME, "local_shell": True},
            live_settings.JWT_SECRET,
            algorithm="HS256",
        )
        _state = {"origin": origin, "token": token, "port": port}
        config["port"] = port
        from desktop.common import atomic_json

        atomic_json(data / "config.json", config)
        return dict(_state)


def healthy() -> bool:
    if _thread is None or not _thread.is_alive() or _state is None:
        return False
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(_state["origin"] + "/api/app/version", timeout=3) as response:
            return response.status == 200
    except OSError:
        return False


def stop() -> None:
    with _lock:
        _close_server()
