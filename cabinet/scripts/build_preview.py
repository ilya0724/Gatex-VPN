"""Build a single-file demo of the cabinet (no Telegram, sample data).

    python3 cabinet/scripts/build_preview.py out.html

The output has no <html>/<head> wrapper so it can be published as a Claude
Artifact; browsers render it as-is too.
"""
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent / "web"


def main(out: str) -> None:
    css = (WEB / "app.css").read_text(encoding="utf-8")
    js = (WEB / "app.js").read_text(encoding="utf-8")
    qr = (WEB / "vendor" / "qrcode.js").read_text(encoding="utf-8")
    html = f"""<title>Кабинет GateX</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Unbounded:wght@500;600;700&display=swap">
<style>
{css}
</style>
<div id="app"></div>
<script>window.GATEX_PREVIEW = true;</script>
<script>
{qr}
</script>
<script>
{js}
</script>
"""
    Path(out).write_text(html, encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "cabinet-preview.html")
