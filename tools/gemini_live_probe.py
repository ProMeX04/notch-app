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

import websockets


MODEL = "gemini-3.1-flash-live-preview"
KEYCHAIN_SERVICE = "dev.notch"
KEYCHAIN_ACCOUNT = "GeminiLiveAPIKey"


def read_api_key() -> str:
    env_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if env_key:
        return env_key

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
        check=True,
        capture_output=True,
        text=True,
    )
    key = result.stdout.strip()
    if not key:
        raise RuntimeError("Gemini API key not found in environment or Keychain.")
    return key


async def send_json(ws, payload: dict) -> None:
    await ws.send(json.dumps(payload))


async def capture_audio(ws, args, summary: dict) -> None:
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


async def receive_events(ws, args, summary: dict) -> None:
    deadline = time.monotonic() + args.duration + args.tail_seconds

    while time.monotonic() < deadline:
        timeout = max(0.1, deadline - time.monotonic())
        try:
            message = await asyncio.wait_for(ws.recv(), timeout=timeout)
        except asyncio.TimeoutError:
            continue
        except websockets.ConnectionClosed:
            break

        if isinstance(message, bytes):
            message = message.decode("utf-8", errors="replace")

        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            print(f"[raw] {message}")
            continue

        error = payload.get("error")
        if error:
            print(f"[error] {error.get('message', error)}")
            summary["errors"].append(error)
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
    parser = argparse.ArgumentParser(description="Probe Gemini Live using mic audio from ffmpeg.")
    parser.add_argument("--device", default=":0", help="FFmpeg avfoundation input, default ':0' for the first mic.")
    parser.add_argument("--duration", type=float, default=12.0, help="Seconds to capture microphone audio.")
    parser.add_argument("--tail-seconds", type=float, default=8.0, help="Seconds to keep listening after mic capture stops.")
    parser.add_argument("--chunk-bytes", type=int, default=4096, help="PCM bytes to batch into each websocket frame.")
    args = parser.parse_args()

    api_key = read_api_key()
    url = (
        "wss://generativelanguage.googleapis.com/ws/"
        "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        f"?key={api_key}"
    )

    summary = {
        "audio_chunks": 0,
        "audio_bytes": 0,
        "output_audio_bytes": 0,
        "user_transcripts": [],
        "model_transcripts": [],
        "errors": [],
        "ffmpeg_stderr": "",
    }

    print("[probe] connecting to Gemini Live...")
    async with websockets.connect(url, max_size=None) as ws:
        await send_json(
            ws,
            {
                "setup": {
                    "model": f"models/{MODEL}",
                    "inputAudioTranscription": {},
                    "outputAudioTranscription": {},
                    "generationConfig": {
                        "responseModalities": ["AUDIO"],
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
                                "text": (
                                    "You are a concise voice assistant. "
                                    "Keep spoken replies brief."
                                )
                            }
                        ]
                    },
                }
            },
        )
        print("[probe] connected. speak now...")

        receiver = asyncio.create_task(receive_events(ws, args, summary))
        await capture_audio(ws, args, summary)
        await receiver

    print(
        "[summary] "
        f"chunks={summary['audio_chunks']} "
        f"in_bytes={summary['audio_bytes']} "
        f"out_audio_bytes={summary['output_audio_bytes']} "
        f"user_tx={len(summary['user_transcripts'])} "
        f"model_tx={len(summary['model_transcripts'])} "
        f"errors={len(summary['errors'])}"
    )
    if summary["ffmpeg_stderr"]:
        print(f"[ffmpeg] {summary['ffmpeg_stderr']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        raise SystemExit(130)
