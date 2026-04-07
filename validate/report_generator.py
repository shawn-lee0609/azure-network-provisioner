"""
report_generator.py

Reads validation_results.json produced by validator.py
and generates a color-coded HTML report summarizing
the validation status of each Azure resource.
"""

import json
import os
from datetime import datetime


# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────

INPUT_FILE  = "validation_results.json"
OUTPUT_FILE = "report.html"


# ─────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────

def load_results(input_path: str) -> list[dict]:
    """
    Loads the validation results from a JSON file
    produced by validator.py.
    """
    if not os.path.exists(input_path):
        print(f"[ERROR] Results file not found: {input_path}")
        print("[INFO]  Run validator.py first to generate validation_results.json")
        raise SystemExit(1)

    with open(input_path, "r") as f:
        return json.load(f)


def get_status_color(status: str) -> str:
    """
    Maps a validation status to a CSS color class.
    """
    colors = {
        "PASS":  "#2ecc71",   # green
        "FAIL":  "#e74c3c",   # red
        "DRIFT": "#f39c12"    # orange
    }
    return colors.get(status, "#95a5a6")  # grey for unknown


def build_summary(results: list[dict]) -> dict:
    """
    Calculates total, pass, fail, and drift counts
    from the full results list.
    """
    return {
        "total": len(results),
        "pass":  sum(1 for r in results if r["status"] == "PASS"),
        "fail":  sum(1 for r in results if r["status"] == "FAIL"),
        "drift": sum(1 for r in results if r["status"] == "DRIFT")
    }


# ─────────────────────────────────────────────
# HTML Generation
# ─────────────────────────────────────────────

def generate_html(results: list[dict], summary: dict) -> str:
    """
    Builds the full HTML report as a string.
    Uses inline CSS for portability — no external dependencies.
    """

    # Build one table row per validation result
    rows = ""
    for r in results:
        color      = get_status_color(r["status"])
        message    = r.get("message") or "—"
        rows += f"""
        <tr>
            <td>{r['resource']}</td>
            <td>{r['check']}</td>
            <td style="color: {color}; font-weight: bold;">{r['status']}</td>
            <td>{r['expected']}</td>
            <td>{r['actual']}</td>
            <td>{message}</td>
        </tr>"""

    # Determine overall status for the report header
    if summary["fail"] > 0:
        overall_status = "FAIL"
        overall_color  = "#e74c3c"
    elif summary["drift"] > 0:
        overall_status = "DRIFT DETECTED"
        overall_color  = "#f39c12"
    else:
        overall_status = "ALL PASS"
        overall_color  = "#2ecc71"

    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Full HTML document
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure Network Validation Report</title>
    <style>
        body {{
            font-family: 'Segoe UI', Arial, sans-serif;
            background-color: #1e1e2e;
            color: #cdd6f4;
            margin: 0;
            padding: 32px;
        }}
        h1 {{
            color: #cba6f7;
            margin-bottom: 4px;
        }}
        .subtitle {{
            color: #6c7086;
            font-size: 0.9rem;
            margin-bottom: 32px;
        }}
        .summary {{
            display: flex;
            gap: 16px;
            margin-bottom: 32px;
        }}
        .summary-card {{
            background: #2a2b3d;
            border-radius: 10px;
            padding: 20px 32px;
            text-align: center;
            min-width: 120px;
        }}
        .summary-card .count {{
            font-size: 2rem;
            font-weight: bold;
        }}
        .summary-card .label {{
            font-size: 0.85rem;
            color: #6c7086;
            margin-top: 4px;
        }}
        .overall {{
            font-size: 1.2rem;
            font-weight: bold;
            margin-bottom: 24px;
            color: {overall_color};
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            background: #2a2b3d;
            border-radius: 10px;
            overflow: hidden;
        }}
        th {{
            background: #313244;
            padding: 12px 16px;
            text-align: left;
            font-size: 0.85rem;
            color: #cba6f7;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }}
        td {{
            padding: 12px 16px;
            border-top: 1px solid #313244;
            font-size: 0.9rem;
        }}
        tr:hover td {{
            background: #313244;
        }}
        .footer {{
            margin-top: 24px;
            font-size: 0.8rem;
            color: #6c7086;
        }}
    </style>
</head>
<body>
    <h1>Azure Network Validation Report</h1>
    <div class="subtitle">Generated at: {generated_at}</div>

    <div class="overall">Overall Status: {overall_status}</div>

    <div class="summary">
        <div class="summary-card">
            <div class="count">{summary['total']}</div>
            <div class="label">Total Checks</div>
        </div>
        <div class="summary-card">
            <div class="count" style="color: #2ecc71;">{summary['pass']}</div>
            <div class="label">PASS</div>
        </div>
        <div class="summary-card">
            <div class="count" style="color: #e74c3c;">{summary['fail']}</div>
            <div class="label">FAIL</div>
        </div>
        <div class="summary-card">
            <div class="count" style="color: #f39c12;">{summary['drift']}</div>
            <div class="label">DRIFT</div>
        </div>
    </div>

    <table>
        <thead>
            <tr>
                <th>Resource</th>
                <th>Check</th>
                <th>Status</th>
                <th>Expected</th>
                <th>Actual</th>
                <th>Message</th>
            </tr>
        </thead>
        <tbody>
            {rows}
        </tbody>
    </table>

    <div class="footer">
        Azure Network Provisioner &amp; Validator — Portfolio Project
    </div>
</body>
</html>"""

    return html


# ─────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────

def main():
    # Resolve paths relative to this script's directory
    base_dir    = os.path.dirname(__file__)
    input_path  = os.path.join(base_dir, INPUT_FILE)
    output_path = os.path.join(base_dir, OUTPUT_FILE)

    # Load results from validator.py output
    results = load_results(input_path)
    summary = build_summary(results)

    # Generate and write HTML report
    html = generate_html(results, summary)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"[OK]  Report generated: {output_path}")
    print(f"[OK]  Total: {summary['total']} | "
          f"PASS: {summary['pass']} | "
          f"FAIL: {summary['fail']} | "
          f"DRIFT: {summary['drift']}")


if __name__ == "__main__":
    main()