#!/bin/bash
# Compute dates needed for the release-guardian-service-health skill.
# Outputs key=value pairs, one per line.

DOW=$(date +%u)  # 1=Mon .. 7=Sun

# Days until Friday (positive = future, negative = past). The
# weekly meeting is Friday, so that is the meeting date.
FRI_DIFF=$((5 - DOW))

# `date -v` wants a signed offset (+Nd or -Nd). Format the sign
# explicitly: a plain "${N:+"+"}${N}" prepends "+" to negatives too,
# yielding invalid offsets like "+-1d".
signed() { if [ "$1" -ge 0 ]; then echo "+$1"; else echo "$1"; fi; }

MEETING_DATE=$(date -v"$(signed "$FRI_DIFF")"d +%Y-%m-%d)
MEETING_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${MEETING_DATE}T00:00:00" "+%s")
MEETING_MS=$((MEETING_EPOCH * 1000))
MEETING_HUMAN=$(date -j -f "%Y-%m-%d" "$MEETING_DATE" "+%A, %B %d, %Y")

ONE_WEEK_AGO=$(date -v-7d "+%Y-%m-%dT00:00:00Z")
NOW=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

THIS_FRI=$(date -v"$(signed "$FRI_DIFF")"d +%Y-%m-%dT00:00:00Z)
NEXT_FRI=$(date -v"$(signed "$FRI_DIFF")"d -v+7d +%Y-%m-%dT00:00:00Z)

echo "MEETING_DATE=$MEETING_DATE"
echo "MEETING_MS=$MEETING_MS"
echo "MEETING_HUMAN=$MEETING_HUMAN"
echo "ONE_WEEK_AGO=$ONE_WEEK_AGO"
echo "NOW=$NOW"
echo "THIS_FRI=$THIS_FRI"
echo "NEXT_FRI=$NEXT_FRI"
