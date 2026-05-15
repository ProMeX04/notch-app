#!/usr/bin/env python3
"""Probe whether Gemini Live accepts TEXT-only response modality.

Usage:
  GEMINI_API_KEY=... python tools/gemini_live_text_probe.py
  GEMINI_API_KEY=... python tools/gemini_live_text_probe.py --model gemini-2.5-flash-native-audio-preview-12-2025
"""

import argparse
import asyncio
import os
import sys

from google import genai
from google.genai import types


async def run_case(api_key: str, model: str, prompt: str, api_version: str, modality: str) -> tuple[bool, bool, bool]:
    client = genai.Client(api_key=api_key, http_options={"api_version": api_version})
    response_modality = getattr(types.Modality, modality, modality)
    config = types.LiveConnectConfig(
        response_modalities=[response_modality],
        system_instruction="You are a concise assistant. Reply in plain text only.",
    )

    print(f"\nConnecting model={model} api_version={api_version} response_modalities=['{modality}']")

    async with client.aio.live.connect(model=model, config=config) as session:
        await session.send_client_content(
            turns=types.Content(
                role="user",
                parts=[types.Part(text=prompt)],
            ),
            turn_complete=True,
        )

        saw_text = False
        saw_audio = False
        saw_error = False

        async for response in session.receive():
            if getattr(response, "server_content", None):
                content = response.server_content.model_turn
                if content and content.parts:
                    for part in content.parts:
                        if getattr(part, "text", None):
                            saw_text = True
                            print(f"TEXT: {part.text}")
                        inline_data = getattr(part, "inline_data", None)
                        if inline_data:
                            saw_audio = True
                            mime_type = getattr(inline_data, "mime_type", "unknown")
                            data = getattr(inline_data, "data", b"") or b""
                            print(f"AUDIO: mime_type={mime_type} bytes={len(data)}")

                if response.server_content.turn_complete:
                    break

            if getattr(response, "error", None):
                saw_error = True
                print(f"ERROR: {response.error}", file=sys.stderr)
                break

        print("Result:")
        print(f"  saw_text={saw_text}")
        print(f"  saw_audio={saw_audio}")
        print(f"  saw_error={saw_error}")
        return saw_text, saw_audio, saw_error


async def probe_text_only(model: str, prompt: str, api_versions: list[str], include_audio_control: bool) -> int:
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("Missing GEMINI_API_KEY or GOOGLE_API_KEY environment variable", file=sys.stderr)
        return 2

    cases = [(api_version, "TEXT") for api_version in api_versions]
    if include_audio_control:
        cases.extend((api_version, "AUDIO") for api_version in api_versions)

    text_only_ok = False
    for api_version, modality in cases:
        try:
            saw_text, saw_audio, saw_error = await run_case(api_key, model, prompt, api_version, modality)
            if modality == "TEXT" and saw_text and not saw_audio and not saw_error:
                text_only_ok = True
        except Exception as exc:
            print(f"Result:\n  failed={type(exc).__name__}: {exc}", file=sys.stderr)

    return 0 if text_only_ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Test Gemini Live TEXT-only output support")
    parser.add_argument("--model", default="gemini-3.1-flash-live-preview")
    parser.add_argument("--prompt", default="Say hello in one short Vietnamese sentence.")
    parser.add_argument("--api-version", action="append", choices=["v1alpha", "v1beta"], dest="api_versions")
    parser.add_argument("--skip-audio-control", action="store_true")
    args = parser.parse_args()
    return asyncio.run(
        probe_text_only(
            args.model,
            args.prompt,
            args.api_versions or ["v1alpha", "v1beta"],
            not args.skip_audio_control,
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
