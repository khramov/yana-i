#!/bin/sh
# Re-records the Yahoo Finance fixtures used by YanaMarketDataTests from the live endpoints.
set -eu
DIR="$(cd "$(dirname "$0")/../YanaKit/Tests/YanaMarketDataTests/Fixtures" && pwd)"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT
chart() { curl -fsS -A "$UA" "https://query1.finance.yahoo.com/v8/finance/chart/$1?$2" -o "$DIR/$3"; }

for s in AAPL VTI SBER.ME VOD.L USDEUR=X; do chart "$s" "range=1d&interval=1d" "chart-$s.json"; done
chart KO "range=2y&interval=1mo&events=div" "chart-KO-div.json"
curl -sS -A "$UA" "https://query1.finance.yahoo.com/v8/finance/chart/ZZZZQ?range=1d&interval=1d" -o "$DIR/chart-notfound.json"

curl -sS -A "$UA" -c "$JAR" -o /dev/null https://fc.yahoo.com/ || true
CRUMB="$(curl -fsS -A "$UA" -b "$JAR" https://query2.finance.yahoo.com/v1/test/getcrumb)"
summary() { curl -fsS -A "$UA" -b "$JAR" "https://query2.finance.yahoo.com/v10/finance/quoteSummary/$1?modules=$2&crumb=$CRUMB" -o "$DIR/$3"; }
summary KO "calendarEvents,summaryDetail,defaultKeyStatistics" "quoteSummary-KO.json"
summary AAPL "assetProfile" "quoteSummary-AAPL-assetProfile.json"
echo "Recorded fixtures into $DIR"
