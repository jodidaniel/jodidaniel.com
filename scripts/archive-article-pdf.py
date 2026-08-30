#!/usr/bin/env python3
"""Render an archive PDF of an external article, for the PRIVATE media archive.

    pip install requests readability-lxml weasyprint
    python3 scripts/archive-article-pdf.py OUTDIR WORKLIST.json

WORKLIST.json is a list of {"slug", "url", "source"} objects; one
<slug>.pdf is written into OUTDIR per entry, stamped with the source, the
original URL and the retrieval date so the copy is self-identifying.

The output NEVER belongs in this repo. jodidaniel.com is public, so a committed
copy of a third-party article would be world-readable at raw.githubusercontent
.com forever, and git history would keep it after any `git rm`. Upload to the
private archive with scripts/media-archive.sh, then name the object in the
item's `pdf_archive_file`. See docs/CONTENT-MODEL.md, "Archived PDFs".

Two things worth knowing before trusting a batch:

* Many publishers (Cloudflare, WAFs, LinkedIn) answer 403/999 to any automated
  client. Those entries fail here and need a human with a browser; that is not
  a bug in this script.
* A 200 is not a usable archive. A paywall or sign-in stub renders perfectly
  and yields a few hundred characters of boilerplate — which, published behind
  a "Download PDF" button, is a lying button. Check the extracted body length
  before accepting an output (roughly: under ~800 characters is a stub).
"""
import datetime, html, json, os, sys, urllib.parse
import requests
from readability import Document
from weasyprint import HTML

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/126.0.0.0 Safari/537.36")
CSS = """
@page { size: Letter; margin: 0.75in; @bottom-center {
  content: "Archived copy — page " counter(page) " of " counter(pages);
  font: 9pt/1.3 sans-serif; color: #666; } }
body { font: 11pt/1.55 Georgia, serif; color: #1a1a1a; }
.prov { border-bottom: 2px solid #333; padding-bottom: 10px; margin-bottom: 22px;
        font: 9pt/1.5 sans-serif; color: #444; }
.prov b { color: #000; } .prov a { color: #444; word-break: break-all; }
h1 { font: 700 20pt/1.25 Georgia, serif; margin: 0 0 14px; }
img { max-width: 100%; } pre { white-space: pre-wrap; }
figure { margin: 1em 0; } blockquote { margin-left: 1.2em; color: #333; }
"""

def archive(url, dest, source_label=""):
    r = requests.get(url, headers={"User-Agent": UA}, timeout=60, allow_redirects=True)
    r.raise_for_status()
    doc = Document(r.content)
    title = (doc.short_title() or "").strip()
    content = doc.summary(html_partial=True)
    today = datetime.date.today().isoformat()
    prov = (
        '<div class="prov">'
        f"<b>Archived copy for reference.</b><br>"
        f"Source: {html.escape(source_label or urllib.parse.urlparse(url).netloc)}<br>"
        f'Original URL: <a href="{html.escape(url)}">{html.escape(url)}</a><br>'
        f"Retrieved: {today}"
        "</div>"
    )
    page = (f"<!doctype html><meta charset='utf-8'><style>{CSS}</style>"
            f"{prov}<h1>{html.escape(title)}</h1>{content}")
    HTML(string=page, base_url=url).write_pdf(dest)
    return {"title": title, "bytes": os.path.getsize(dest), "chars": len(content)}

if __name__ == "__main__":
    out = sys.argv[1]
    for line in json.load(open(sys.argv[2])):
        dest = os.path.join(out, line["slug"] + ".pdf")
        rec = {"slug": line["slug"], "url": line["url"]}
        try:
            rec.update(archive(line["url"], dest, line.get("source", "")))
        except Exception as e:
            rec["error"] = f"{type(e).__name__}: {str(e)[:140]}"
        print(json.dumps(rec), flush=True)
