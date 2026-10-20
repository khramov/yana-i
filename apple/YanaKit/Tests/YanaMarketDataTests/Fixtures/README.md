# Yahoo fixtures

These responses are hand-written to follow the shape of Yahoo Finance's `v8/finance/chart` and
`v10/finance/quoteSummary` JSON. The machine that built this change was rate-limited (HTTP 429) by Yahoo, so they
could not be recorded. To replace them with real captures, run `apple/scripts/record-yahoo-fixtures.sh` and check
that `./test.sh` still passes.
