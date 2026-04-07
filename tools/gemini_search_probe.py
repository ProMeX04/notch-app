#!/usr/bin/env python3
"""Small Gemini Google Search grounding probe.

This mirrors the OpenClaw Gemini web_search provider flow closely:
- POST generateContent
- pass tools: [{"google_search": {}}]
- read text from candidates[0].content.parts
- read citations from groundingMetadata.groundingChunks[].web
- optionally resolve redirect URLs with a safe HEAD/GET follow
"""

from __future__ import annotations

import argparse
import html
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


DEFAULT_MODEL = "gemini-2.5-flash"
DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_TIMEOUT = 20.0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Test Gemini Google Search grounding from the command line."
    )
    parser.add_argument("query", help="Search query to send to Gemini")
    parser.add_argument(
        "--api-key",
        default=os.environ.get("GEMINI_API_KEY", "").strip(),
        help="Gemini API key. Defaults to GEMINI_API_KEY.",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Default: {DEFAULT_MODEL}")
    parser.add_argument(
        "--base-url", default=DEFAULT_BASE_URL, help=f"Default: {DEFAULT_BASE_URL}"
    )
    parser.add_argument(
        "--timeout", type=float, default=DEFAULT_TIMEOUT, help=f"Default: {DEFAULT_TIMEOUT}"
    )
    parser.add_argument(
        "--no-resolve-citations",
        action="store_true",
        help="Keep citation URLs as returned by Gemini.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the parsed result as JSON.",
    )
    parser.add_argument(
        "--html-out",
        help="Write a human-friendly HTML report to this path.",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print the raw Gemini response JSON.",
    )
    return parser


def fetch_json(url: str, payload: dict[str, Any], headers: dict[str, str], timeout: float) -> Any:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def resolve_redirect_url(url: str, timeout: float) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return url
    opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler())
    methods = ["HEAD", "GET"]
    for method in methods:
        req = urllib.request.Request(url, method=method, headers={"User-Agent": "notch-app-probe"})
        try:
            with opener.open(req, timeout=timeout) as response:
                return response.geturl()
        except Exception:
            continue
    return url


def extract_result(data: dict[str, Any], resolve_citations: bool, timeout: float) -> dict[str, Any]:
    candidate = ((data.get("candidates") or [None])[0]) or {}
    content_parts = (((candidate.get("content") or {}).get("parts")) or [])
    text_parts = [part.get("text", "") for part in content_parts if isinstance(part, dict)]
    content = "\n".join(part for part in text_parts if part).strip() or "No response"

    chunks = (((candidate.get("groundingMetadata") or {}).get("groundingChunks")) or [])
    citations: list[dict[str, str]] = []
    for chunk in chunks:
        if not isinstance(chunk, dict):
            continue
        web = chunk.get("web")
        if not isinstance(web, dict):
            continue
        uri = web.get("uri")
        if not isinstance(uri, str) or not uri.strip():
            continue
        final_url = resolve_redirect_url(uri, timeout) if resolve_citations else uri
        entry: dict[str, str] = {"url": final_url}
        title = web.get("title")
        if isinstance(title, str) and title.strip():
            entry["title"] = title.strip()
        citations.append(entry)

    supports = (((candidate.get("groundingMetadata") or {}).get("groundingSupports")) or [])
    claims: list[dict[str, Any]] = []
    for support in supports:
        if not isinstance(support, dict):
            continue
        segment = support.get("segment")
        if not isinstance(segment, dict):
            continue
        text = segment.get("text")
        if not isinstance(text, str) or not text.strip():
            continue
        indices = support.get("groundingChunkIndices")
        if not isinstance(indices, list):
            indices = []
        claims.append(
            {
                "text": text.strip(),
                "groundingChunkIndices": [index for index in indices if isinstance(index, int)],
            }
        )

    search_entry_point = (candidate.get("groundingMetadata") or {}).get("searchEntryPoint")
    rendered_content = ""
    if isinstance(search_entry_point, dict):
        rendered = search_entry_point.get("renderedContent")
        if isinstance(rendered, str):
            rendered_content = rendered

    web_search_queries = (candidate.get("groundingMetadata") or {}).get("webSearchQueries")
    if not isinstance(web_search_queries, list):
        web_search_queries = []

    return {
        "provider": "gemini",
        "content": content,
        "citations": citations,
        "claims": claims,
        "renderedContent": rendered_content,
        "webSearchQueries": web_search_queries,
    }


def slugify_filename(value: str) -> str:
    parts: list[str] = []
    for char in value.lower():
        if char.isalnum():
            parts.append(char)
        elif char in {" ", "-", "_"}:
            parts.append("-")
    slug = "".join(parts).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "query"


def build_html_report(result: dict[str, Any], raw_data: dict[str, Any]) -> str:
    query = html.escape(str(result.get("query", "")))
    model = html.escape(str(result.get("model", "")))
    took_ms = html.escape(str(result.get("tookMs", "")))
    answer = html.escape(str(result.get("content", "")))
    raw_json = html.escape(json.dumps(raw_data, ensure_ascii=False, indent=2))

    citations_html_parts: list[str] = []
    for index, citation in enumerate(result.get("citations", [])):
        if not isinstance(citation, dict):
            continue
        title = html.escape(str(citation.get("title") or "(no title)"))
        url = html.escape(str(citation.get("url") or ""))
        citations_html_parts.append(
            f'<li><strong>[{index}] {title}</strong><br><a href="{url}" target="_blank" rel="noreferrer">{url}</a></li>'
        )
    citations_html = "\n".join(citations_html_parts) if citations_html_parts else "<li>(none)</li>"

    claims_html_parts: list[str] = []
    for claim in result.get("claims", []):
        if not isinstance(claim, dict):
            continue
        text = html.escape(str(claim.get("text") or ""))
        indices = claim.get("groundingChunkIndices")
        labels: list[str] = []
        if isinstance(indices, list):
            labels = [f'<span class="chip">source {index}</span>' for index in indices if isinstance(index, int)]
        chips = " ".join(labels) if labels else '<span class="chip muted">no source indices</span>'
        claims_html_parts.append(f'<li><div>{text}</div><div class="claim-sources">{chips}</div></li>')
    claims_html = "\n".join(claims_html_parts) if claims_html_parts else "<li>(none)</li>"

    query_html_parts: list[str] = []
    for item in result.get("webSearchQueries", []):
        if isinstance(item, str) and item.strip():
            query_html_parts.append(f"<li>{html.escape(item.strip())}</li>")
    queries_html = "\n".join(query_html_parts) if query_html_parts else "<li>(none)</li>"

    rendered_content = result.get("renderedContent")
    if not isinstance(rendered_content, str) or not rendered_content.strip():
        rendered_content = "<div class='empty'>No renderedContent returned.</div>"

    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Gemini Search Report</title>
    <style>
      :root {{
        color-scheme: light dark;
        font-family: "SF Pro Text", "Segoe UI", sans-serif;
      }}
      body {{
        margin: 0;
        padding: 28px;
        background:
          radial-gradient(circle at top left, rgba(0, 143, 93, 0.16), transparent 32%),
          radial-gradient(circle at top right, rgba(66, 133, 244, 0.16), transparent 30%),
          #f4f7f9;
        color: #16202a;
      }}
      .page {{
        max-width: 1100px;
        margin: 0 auto;
      }}
      .hero {{
        margin-bottom: 18px;
      }}
      .hero h1 {{
        margin: 0 0 8px;
        font-size: 28px;
      }}
      .hero p {{
        margin: 0;
        line-height: 1.5;
      }}
      .grid {{
        display: grid;
        grid-template-columns: 1.2fr 0.8fr;
        gap: 18px;
      }}
      .card {{
        background: rgba(255, 255, 255, 0.84);
        backdrop-filter: blur(12px);
        border: 1px solid rgba(22, 32, 42, 0.08);
        border-radius: 18px;
        padding: 18px;
        box-shadow: 0 20px 60px rgba(22, 32, 42, 0.10);
      }}
      .card h2 {{
        margin: 0 0 14px;
        font-size: 18px;
      }}
      .meta {{
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-bottom: 14px;
      }}
      .pill {{
        border-radius: 999px;
        padding: 6px 10px;
        background: rgba(66, 133, 244, 0.10);
        border: 1px solid rgba(66, 133, 244, 0.18);
        font-size: 13px;
      }}
      .answer {{
        white-space: pre-wrap;
        line-height: 1.6;
      }}
      ol, ul {{
        margin: 0;
        padding-left: 20px;
      }}
      li {{
        margin-bottom: 10px;
        line-height: 1.5;
      }}
      a {{
        color: #0b63ce;
        word-break: break-all;
      }}
      .claim-sources {{
        margin-top: 8px;
      }}
      .chip {{
        display: inline-block;
        margin-right: 8px;
        margin-top: 4px;
        padding: 4px 8px;
        border-radius: 999px;
        background: rgba(15, 105, 225, 0.10);
        border: 1px solid rgba(15, 105, 225, 0.18);
        font-size: 12px;
      }}
      .muted {{
        opacity: 0.7;
      }}
      .rendered-preview {{
        padding: 14px;
        border-radius: 14px;
        background: linear-gradient(180deg, rgba(255,255,255,0.88), rgba(245,247,250,0.92));
        border: 1px solid rgba(22, 32, 42, 0.08);
        overflow: auto;
      }}
      .raw {{
        white-space: pre-wrap;
        overflow: auto;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 12px;
        line-height: 1.5;
        background: rgba(22, 32, 42, 0.04);
        padding: 14px;
        border-radius: 12px;
      }}
      .full {{
        grid-column: 1 / -1;
      }}
      .empty {{
        opacity: 0.7;
      }}
      @media (max-width: 860px) {{
        .grid {{
          grid-template-columns: 1fr;
        }}
      }}
      @media (prefers-color-scheme: dark) {{
        body {{
          background:
            radial-gradient(circle at top left, rgba(0, 143, 93, 0.20), transparent 32%),
            radial-gradient(circle at top right, rgba(66, 133, 244, 0.18), transparent 30%),
            #0f151b;
          color: #e8eef5;
        }}
        .card {{
          background: rgba(18, 25, 33, 0.84);
          border-color: rgba(232, 238, 245, 0.08);
          box-shadow: 0 20px 60px rgba(0, 0, 0, 0.34);
        }}
        .pill {{
          background: rgba(66, 133, 244, 0.16);
          border-color: rgba(66, 133, 244, 0.24);
        }}
        a {{
          color: #83b7ff;
        }}
        .chip {{
          background: rgba(131, 183, 255, 0.12);
          border-color: rgba(131, 183, 255, 0.20);
        }}
        .rendered-preview {{
          background: linear-gradient(180deg, rgba(24, 30, 38, 0.9), rgba(17, 22, 28, 0.92));
          border-color: rgba(232, 238, 245, 0.08);
        }}
        .raw {{
          background: rgba(232, 238, 245, 0.05);
        }}
      }}
    </style>
  </head>
  <body>
    <div class="page">
      <div class="hero">
        <h1>Gemini Search Report</h1>
        <p><strong>Query:</strong> {query}</p>
      </div>
      <div class="grid">
        <section class="card">
          <h2>Answer</h2>
          <div class="meta">
            <span class="pill">Model: {model}</span>
            <span class="pill">Provider: gemini</span>
            <span class="pill">Took: {took_ms} ms</span>
          </div>
          <div class="answer">{answer}</div>
        </section>
        <section class="card">
          <h2>Search Queries Used</h2>
          <ul>{queries_html}</ul>
        </section>
        <section class="card">
          <h2>Sources</h2>
          <ol>{citations_html}</ol>
        </section>
        <section class="card">
          <h2>Claim to Source Mapping</h2>
          <ol>{claims_html}</ol>
        </section>
        <section class="card full">
          <h2>Rendered Search Entry</h2>
          <div class="rendered-preview">{rendered_content}</div>
        </section>
        <section class="card full">
          <h2>Raw JSON</h2>
          <div class="raw">{raw_json}</div>
        </section>
      </div>
    </div>
  </body>
</html>
"""


def write_html_report(path: str, result: dict[str, Any], raw_data: dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(build_html_report(result, raw_data))


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if not args.api_key:
        print("Missing API key. Set GEMINI_API_KEY or pass --api-key.", file=sys.stderr)
        return 2

    endpoint = f"{args.base_url.rstrip('/')}/models/{args.model}:generateContent"
    payload = {
        "contents": [{"parts": [{"text": args.query}]}],
        "tools": [{"google_search": {}}],
    }
    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": args.api_key,
    }

    started = time.time()
    try:
        data = fetch_json(endpoint, payload, headers, args.timeout)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"HTTP {exc.code}: {detail}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"Request failed: {exc}", file=sys.stderr)
        return 1

    elapsed_ms = int((time.time() - started) * 1000)

    if isinstance(data, dict) and isinstance(data.get("error"), dict):
        err = data["error"]
        code = err.get("code", "unknown")
        message = err.get("message") or err.get("status") or "unknown error"
        print(f"Gemini API error ({code}): {message}", file=sys.stderr)
        return 1

    result = extract_result(
        data if isinstance(data, dict) else {},
        resolve_citations=not args.no_resolve_citations,
        timeout=args.timeout,
    )
    result["query"] = args.query
    result["model"] = args.model
    result["tookMs"] = elapsed_ms
    html_out = args.html_out or os.path.join(
        "tools", f"gemini_search_report_{slugify_filename(args.query)}.html"
    )
    write_html_report(html_out, result, data if isinstance(data, dict) else {})

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        print(f"\nHTML report: {html_out}", file=sys.stderr)
        return 0

    if args.raw:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        print(f"\nHTML report: {html_out}", file=sys.stderr)
        return 0

    print(f"Query: {args.query}")
    print(f"Model: {args.model}")
    print(f"Took: {elapsed_ms} ms")
    print("")
    print("Answer:")
    print(result["content"])
    print("")
    print("Citations:")
    if not result["citations"]:
        print("- (none)")
    else:
        for index, citation in enumerate(result["citations"], start=1):
            title = citation.get("title") or "(no title)"
            print(f"{index}. {title}")
            print(f"   {citation['url']}")
    print("")
    print(f"HTML report: {html_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
