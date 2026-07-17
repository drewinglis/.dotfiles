#!/usr/bin/env bash
#
# slo-status.sh — fetch the owner-scoped Release Guardian SLOs from the
# Datadog SLO API and report each one's status for a single evaluation
# window (default: 7d). Emits JSON to stdout for the skill to parse.
#
# Usage:
#   slo-status.sh [timeframe]      # timeframe default: 7d
#
# Reads:
#   - DD_PAT from ~/.env-datadog (override path with DD_ENV_FILE)
#   - datadog.sloQuery / datadog.sloApiUrl from the config.json
#     next to this script
#
# The PAT is used only as a bearer token and is never printed.

set -euo pipefail

TIMEFRAME="${1:-7d}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

ENV_FILE="${DD_ENV_FILE:-$HOME/.env-datadog}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found (expected DD_PAT)" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [[ -z "${DD_PAT:-}" ]]; then
  echo "error: DD_PAT not set in $ENV_FILE" >&2
  exit 1
fi

# Pull query + endpoint from config (with sane fallbacks).
read -r SLO_QUERY SLO_API < <(python3 -c "
import json
c = json.load(open('$CONFIG')).get('datadog', {})
print(
    c.get('sloQuery', 'owner:team-release-guardian'),
    c.get('sloApiUrl', 'https://api.datadoghq.com/api/v1/slo/search'),
)
")

Q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SLO_QUERY")

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
CODE=$(curl -s -o "$TMP" -w '%{http_code}' \
  -H "Authorization: Bearer $DD_PAT" \
  "$SLO_API?query=$Q&page%5Bsize%5D=1000")
if [[ "$CODE" != "200" ]]; then
  echo "error: SLO API returned HTTP $CODE" >&2
  head -c 800 "$TMP" >&2
  echo >&2
  exit 1
fi

TIMEFRAME="$TIMEFRAME" SLO_QUERY="$SLO_QUERY" python3 - "$TMP" <<'PY'
import json, os, sys

tf = os.environ["TIMEFRAME"]
d = json.load(open(sys.argv[1]))
slos = d["data"]["attributes"]["slos"]
total = d["meta"]["pagination"]["total"]

# no_data / no_window are treated as green (idle SLOs, nothing to breach).
GREEN = {"ok", "no_data", "no_window"}
EMOJI = {"breached": "\U0001F534", "warning": "\U0001F7E1"}  # red, yellow
RANK = {"breached": 0, "warning": 1, "ok": 2, "no_data": 3, "no_window": 4}

out = []
for s in slos:
    data = s["data"]
    a = data["attributes"]
    sid = data["id"]
    entry = next(
        (x for x in a.get("overall_status", []) if x.get("timeframe") == tf),
        None,
    )
    if entry is None:
        state, ebr, status, target = "no_window", None, None, None
    else:
        state = entry.get("state") or "no_data"
        ebr = entry.get("error_budget_remaining")
        status = entry.get("status")
        target = entry.get("target")
    out.append({
        "name": a["name"],
        "id": sid,
        "url": f"https://app.datadoghq.com/slo?slo_id={sid}",
        "timeframe": tf,
        "state": state,
        "emoji": EMOJI.get(state, ""),
        "error_budget_remaining": ebr,
        "status": status,
        "target": target,
    })

out.sort(key=lambda r: (RANK.get(r["state"], 9), r["name"]))

counts = {}
for r in out:
    counts[r["state"]] = counts.get(r["state"], 0) + 1

result = {
    "query": os.environ["SLO_QUERY"],
    "timeframe": tf,
    "total": total,
    "pulled": len(out),
    "counts": counts,
    "all_green": all(r["state"] in GREEN for r in out),
    "non_green": [r for r in out if r["state"] not in GREEN],
    "slos": out,
}

if len(out) != total:
    print(
        f"warning: pulled {len(out)} of {total} SLOs "
        "(increase page[size] / add pagination)",
        file=sys.stderr,
    )

print(json.dumps(result, indent=2))
PY
