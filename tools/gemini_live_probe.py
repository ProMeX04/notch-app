#!/usr/bin/env python3

import argparse
import asyncio
import base64
import json
import os
import signal
import subprocess
import sys
import time
from contextlib import suppress
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import websockets


DEFAULT_MODEL = "gemini-3.1-flash-live-preview"
KEYCHAIN_SERVICE = "dev.notch"
KEYCHAIN_ACCOUNT = "GeminiLiveAPIKey"


def read_api_key() -> str:
    env_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if env_key:
        return env_key

    try:
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-s",
                KEYCHAIN_SERVICE,
                "-a",
                KEYCHAIN_ACCOUNT,
                "-w",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as e:
        raise RuntimeError(
            "Không gọi được lệnh `security` (Keychain). "
            f"Đặt biến môi trường GEMINI_API_KEY hoặc chạy trên macOS. Chi tiết: {e}"
        ) from e

    if result.returncode != 0:
        # 44 = errSecItemNotFound — chưa lưu key trong Keychain giống app Notch
        hint = (
            "Không đọc được API key từ Keychain (exit "
            f"{result.returncode}). Cách nhanh: export GEMINI_API_KEY='...' rồi chạy lại probe. "
            f"Hoặc thêm generic password: service={KEYCHAIN_SERVICE!r}, account={KEYCHAIN_ACCOUNT!r} "
            "(đúng như app Notch dùng)."
        )
        if result.stderr.strip():
            hint += f" stderr: {result.stderr.strip()}"
        raise RuntimeError(hint)

    key = result.stdout.strip()
    if not key:
        raise RuntimeError(
            "Keychain trả về rỗng. Đặt GEMINI_API_KEY hoặc kiểm tra mục Keychain dev.notch / GeminiLiveAPIKey."
        )
    return key


def request_ephemeral_token(backend_url: str, client_token: str | None, model: str) -> str:
    trimmed = backend_url.rstrip("/")
    url = f"{trimmed}/v1/gemini-live/session-token"
    body = json.dumps(
        {
            "model": model,
            "response_modalities": ["AUDIO"],
        }
    ).encode("utf-8")

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if client_token:
        headers["Authorization"] = f"Bearer {client_token}"

    request = Request(url, method="POST", data=body, headers=headers)

    try:
        with urlopen(request, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Backend token API trả HTTP {e.code}: {detail}") from e
    except URLError as e:
        raise RuntimeError(f"Không gọi được backend token API: {e.reason}") from e

    token = str(payload.get("name", "")).strip()
    if not token.startswith("auth_tokens/"):
        raise RuntimeError(f"Backend không trả ephemeral token hợp lệ: {payload}")
    return token


async def send_json(ws, payload: dict) -> None:
    await ws.send(json.dumps(payload))


async def send_realtime_text(ws, user_text: str) -> None:
    """Gửi text input theo luồng realtime của Live API.

    Với `gemini-3.1-flash-live-preview`, tài liệu capability yêu cầu dùng
    `send_realtime_input(text=...)` cho text trong hội thoại. Ở raw WebSocket,
    payload tương ứng là `{"realtimeInput": {"text": ...}}`.
    """
    await send_json(
        ws,
        {
            "realtimeInput": {
                "text": user_text,
            }
        },
    )


async def capture_audio(ws, args, summary: dict) -> None:
    """Gửi PCM từ ffmpeg. Phải gọi sau khi server đã gửi setupComplete (giống Notch Swift)."""
    ffmpeg_cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "avfoundation",
        "-i",
        args.device,
        "-ac",
        "1",
        "-ar",
        "16000",
        "-f",
        "s16le",
        "-",
    ]

    proc = await asyncio.create_subprocess_exec(
        *ffmpeg_cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    summary["ffmpeg_pid"] = proc.pid
    started_at = time.monotonic()

    try:
        while True:
            if time.monotonic() - started_at >= args.duration:
                break

            chunk = await proc.stdout.read(args.chunk_bytes)
            if not chunk:
                break

            summary["audio_chunks"] += 1
            summary["audio_bytes"] += len(chunk)
            try:
                await send_json(
                    ws,
                    {
                        "realtimeInput": {
                            "audio": {
                                "data": base64.b64encode(chunk).decode("ascii"),
                                "mimeType": "audio/pcm;rate=16000",
                            }
                        }
                    },
                )
            except websockets.ConnectionClosed as e:
                summary["audio_send_stopped"] = repr(e)
                print(f"[probe] WebSocket đóng khi gửi audio: {e}", file=sys.stderr)
                break

        with suppress(websockets.ConnectionClosed):
            await send_json(ws, {"realtimeInput": {"audioStreamEnd": True}})
    finally:
        with suppress(ProcessLookupError):
            proc.send_signal(signal.SIGINT)
        with suppress(asyncio.TimeoutError):
            await asyncio.wait_for(proc.wait(), timeout=2)
        if proc.returncode is None:
            proc.kill()
            await proc.wait()

        stderr = await proc.stderr.read()
        if stderr:
            summary["ffmpeg_stderr"] = stderr.decode("utf-8", errors="replace").strip()


async def receive_events(
    ws,
    args,
    summary: dict,
    *,
    recv_until: dict[str, float],
    setup_gate: asyncio.Event | None = None,
    setup_fail: list[str | None] | None = None,
    text_input_mode: bool = False,
) -> None:
    def release_setup_gate(message: str | None) -> None:
        if setup_gate is None or setup_gate.is_set():
            return
        if message is not None and setup_fail is not None:
            setup_fail[0] = message
        setup_gate.set()

    while time.monotonic() < recv_until["t"]:
        timeout = max(0.1, recv_until["t"] - time.monotonic())
        try:
            message = await asyncio.wait_for(ws.recv(), timeout=timeout)
        except asyncio.TimeoutError:
            continue
        except websockets.ConnectionClosed as e:
            summary["ws_closed"] = repr(e)
            release_setup_gate(f"WebSocket đóng trước setupComplete: {e}")
            break

        if isinstance(message, bytes):
            message = message.decode("utf-8", errors="replace")

        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            print(f"[raw] {message}")
            continue

        if getattr(args, "debug_ws", False):
            print(f"[debug-ws] top-level keys: {sorted(payload.keys())}")

        if "setupComplete" in payload:
            print("[probe] setupComplete")
            release_setup_gate(None)

        error = payload.get("error")
        if error:
            msg = error.get("message", error) if isinstance(error, dict) else str(error)
            print(f"[error] {msg}")
            summary["errors"].append(error)
            release_setup_gate(str(msg))
            continue

        server = payload.get("serverContent") or {}

        if server.get("interrupted"):
            print("[server] interrupted=true")

        input_tx = server.get("inputTranscription") or {}
        if input_tx.get("text"):
            text = input_tx["text"]
            summary["user_transcripts"].append(text)
            print(f"[you] {text}")

        output_tx = server.get("outputTranscription") or {}
        if output_tx.get("text"):
            text = output_tx["text"]
            summary["model_transcripts"].append(text)
            print(f"[gemini] {text}")

        model_turn = server.get("modelTurn") or {}
        for part in model_turn.get("parts") or []:
            raw_text = part.get("text")
            if raw_text and text_input_mode:
                summary["model_text_parts"].append(raw_text)
                print(f"[model-text] {raw_text}")

            executable_code = part.get("executableCode") or {}
            if executable_code.get("code"):
                summary["executable_code_parts"].append(executable_code["code"])
                print(f"[exec-code]\n{executable_code['code']}")

            code_result = part.get("codeExecutionResult") or {}
            if code_result.get("output"):
                summary["code_execution_outputs"].append(code_result["output"])
                print(f"[exec-result]\n{code_result['output']}")

            inline = part.get("inlineData") or {}
            data = inline.get("data")
            if data:
                try:
                    decoded = base64.b64decode(data)
                except Exception:
                    decoded = b""
                summary["output_audio_bytes"] += len(decoded)
                if len(decoded) > 0:
                    print(f"[audio] {len(decoded)} bytes")


async def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe Gemini Live: mic (ffmpeg) hoặc gửi text qua realtimeInput.text sau setupComplete."
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model Live API để test. Default: {DEFAULT_MODEL}")
    parser.add_argument("--device", default=":0", help="FFmpeg avfoundation input, default ':0' for the first mic.")
    parser.add_argument("--duration", type=float, default=12.0, help="Seconds to capture microphone audio.")
    parser.add_argument("--tail-seconds", type=float, default=8.0, help="Seconds to keep listening after mic capture stops.")
    parser.add_argument("--chunk-bytes", type=int, default=4096, help="PCM bytes to batch into each websocket frame.")
    parser.add_argument(
        "--request-text-modality",
        action="store_true",
        help=(
            "Thử responseModalities TEXT+AUDIO (vẫn có speechConfig). "
            "Với gemini-3.1-flash-live-preview thường bị đóng WebSocket 1011 ngay sau setup — chỉ để thử API."
        ),
    )
    parser.add_argument(
        "--send-text",
        default=None,
        metavar="MSG",
        help=(
            "Sau setupComplete gửi text qua realtimeInput.text (không bật mic/ffmpeg). "
            "Dùng '-' để đọc nội dung từ stdin. Thời gian chờ phản hồi: --tail-seconds (tối thiểu 30s nội bộ nếu tail nhỏ)."
        ),
    )
    parser.add_argument(
        "--debug-ws",
        action="store_true",
        help="In top-level keys của mỗi JSON nhận từ server (debug).",
    )
    parser.add_argument(
        "--backend-url",
        default=os.environ.get("NOTCH_GEMINI_LIVE_BACKEND_URL", "").strip() or None,
        help="Gemini Live backend URL để xin ephemeral token, ví dụ https://laihieu2714.ddns.net/notch",
    )
    parser.add_argument(
        "--client-token",
        default=os.environ.get("NOTCH_GEMINI_LIVE_CLIENT_TOKEN", "").strip() or None,
        help="Bearer token cho backend ephemeral-token API (nếu backend yêu cầu).",
    )
    parser.add_argument(
        "--enable-google-search",
        action="store_true",
        help="Bật built-in Google Search tool trực tiếp trong Live API setup.",
    )
    args = parser.parse_args()

    user_text_turn: str | None
    if args.send_text is None:
        user_text_turn = None
    elif args.send_text.strip() == "-":
        user_text_turn = sys.stdin.read().strip()
    else:
        user_text_turn = args.send_text.strip()

    if args.send_text is not None and not user_text_turn:
        print("[probe] --send-text cần nội dung không rỗng (hoặc stdin khi dùng '-').", file=sys.stderr)
        return 2

    if args.backend_url:
        connection_credential = request_ephemeral_token(args.backend_url, args.client_token, args.model)
        url = (
            "wss://generativelanguage.googleapis.com/ws/"
            "google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
            f"?access_token={connection_credential}"
        )
        print(f"[probe] dùng ephemeral token từ backend {args.backend_url}")
    else:
        api_key = read_api_key()
        url = (
            "wss://generativelanguage.googleapis.com/ws/"
            "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
            f"?key={api_key}"
        )
        print("[probe] dùng API key trực tiếp")

    summary = {
        "audio_chunks": 0,
        "audio_bytes": 0,
        "output_audio_bytes": 0,
        "user_transcripts": [],
        "model_transcripts": [],
        "model_text_parts": [],
        "executable_code_parts": [],
        "code_execution_outputs": [],
        "errors": [],
        "ffmpeg_stderr": "",
    }

    # TEXT+AUDIO trong setup hay gây 1011 (internal error) trước setupComplete — mặc định chỉ AUDIO.
    if args.request_text_modality:
        modalities = ["TEXT", "AUDIO"]
        print(
            "[probe] cảnh báo: --request-text-modality hay bị server trả 1011.",
            file=sys.stderr,
        )
    else:
        modalities = ["AUDIO"]

    base_instruction = "You are a concise voice assistant. Keep spoken replies brief."
    tools = [{"google_search": {}}] if args.enable_google_search else None

    print("[probe] connecting to Gemini Live...")
    async with websockets.connect(url, max_size=None) as ws:
        setup_payload = {
            "setup": {
                "model": f"models/{args.model}",
                "inputAudioTranscription": {},
                "outputAudioTranscription": {},
                "generationConfig": {
                    "responseModalities": modalities,
                    "speechConfig": {
                        "voiceConfig": {
                            "prebuiltVoiceConfig": {
                                "voiceName": "Kore",
                            }
                        }
                    },
                },
                "systemInstruction": {
                    "parts": [
                        {
                            "text": base_instruction,
                        }
                    ]
                },
            }
        }
        if tools:
            setup_payload["setup"]["tools"] = tools
            print("[probe] bật built-in Google Search tool")

        await send_json(ws, setup_payload)
        print("[probe] đã gửi setup — chờ setupComplete từ server...")

        # Hạn nhận: ban đầu rộng để không cắt ngang lúc chờ setup; main sẽ thu hẹp sau setupComplete.
        recv_until: dict[str, float] = {"t": time.monotonic() + 600.0}

        setup_gate = asyncio.Event()
        setup_fail: list[str | None] = [None]
        text_input_mode = user_text_turn is not None
        receiver = asyncio.create_task(
            receive_events(
                ws,
                args,
                summary,
                recv_until=recv_until,
                setup_gate=setup_gate,
                setup_fail=setup_fail,
                text_input_mode=text_input_mode,
            )
        )
        try:
            await asyncio.wait_for(setup_gate.wait(), timeout=30.0)
        except asyncio.TimeoutError:
            print("[probe] Hết thời gian chờ setupComplete (30s).", file=sys.stderr)
            receiver.cancel()
            with suppress(asyncio.CancelledError):
                await receiver
            return 1

        if setup_fail[0]:
            print(f"[probe] Setup không thành công: {setup_fail[0]}", file=sys.stderr)
            receiver.cancel()
            with suppress(asyncio.CancelledError):
                await receiver
            return 1

        now = time.monotonic()
        if user_text_turn is not None:
            listen = max(args.tail_seconds, 30.0)
            recv_until["t"] = now + listen
            try:
                await send_realtime_text(ws, user_text_turn)
            except websockets.ConnectionClosed as e:
                print(f"[probe] WebSocket đóng khi gửi text: {e}", file=sys.stderr)
                receiver.cancel()
                with suppress(asyncio.CancelledError):
                    await receiver
                return 1
            print(f"[probe] đã gửi realtimeInput.text ({len(user_text_turn)} chars) — chờ model (~{listen:.0f}s)...")
        else:
            recv_until["t"] = now + args.duration + args.tail_seconds
            print("[probe] speak now...")
            await capture_audio(ws, args, summary)

        await receiver

    print(
        "[summary] "
        f"chunks={summary['audio_chunks']} "
        f"in_bytes={summary['audio_bytes']} "
        f"out_audio_bytes={summary['output_audio_bytes']} "
        f"user_tx={len(summary['user_transcripts'])} "
        f"model_tx={len(summary['model_transcripts'])} "
        f"model_text_parts={len(summary['model_text_parts'])} "
        f"exec_code_parts={len(summary['executable_code_parts'])} "
        f"exec_outputs={len(summary['code_execution_outputs'])} "
        f"errors={len(summary['errors'])}"
    )
    if summary["ffmpeg_stderr"]:
        print(f"[ffmpeg] {summary['ffmpeg_stderr']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except RuntimeError as e:
        print(f"[probe] {e}", file=sys.stderr)
        raise SystemExit(1)
    except KeyboardInterrupt:
        raise SystemExit(130)
