# Sync payload v1

The portable format for synchronized Yana records. CloudKit stores it as the `payload` field, and a future
authenticated API can accept it unchanged. The implementation is
`apple/YanaKit/Sources/YanaSync/PayloadCodec.swift`, and the byte-exact examples are in
`apple/YanaKit/Tests/YanaSyncTests/Golden/`.

## Encoding rules

- UTF-8 JSON object. Keys are sorted lexicographically at every level, with no insignificant whitespace,
  and `/` is not escaped.
- An optional field is omitted when it has no value. `null` is never written.
- UUIDs are lowercase strings in canonical 8-4-4-4-12 form.
- Money, quantities, rates, and percentages are decimal **strings** with `.` as the separator, no exponent,
  no grouping, and no trailing zeros (`"1.5"`, `"105.25"`, `"0"`). Readers must not parse them as binary floats.
- Timestamps are ISO-8601 UTC with exactly three fractional digits (`2023-11-14T22:13:20.123Z`).
  Writers truncate to whole milliseconds.
- Calendar dates (`LocalDate`) are `YYYY-MM-DD` with no time zone.

## Envelope

| Key | Type | Meaning |
|---|---|---|
| `schemaVersion` | integer | `1` for this document. |
| `entity` | string | `Portfolio`, `Holding`, `Transaction`, or `Goal`. |
| `id` | UUID | Permanent record identity. |
| `version.revision` | integer | Incremented by every local edit (`stored + 1`). |
| `version.modifiedAt` | timestamp | When the edit was made. |
| `version.deviceID` | UUID | Device that made the edit. |
| `deletedAt` | timestamp, optional | Present only on tombstones. |
| `fields` | object | Entity fields below. A tombstone keeps its last fields. |

Conflicts are resolved per whole record: the greater `(revision, modifiedAt, deviceID)` tuple wins, and
`deviceID` is compared as a lowercase string. A tombstone competes under the same ordering.

A reader that sees a `schemaVersion` newer than it supports must still read the envelope, must keep the
payload bytes unchanged, and must never overwrite or delete that record.

## Fields

### Portfolio
| Key | Type |
|---|---|
| `name` | string, non-empty |
| `baseCurrency` | `EUR` \| `USD` \| `RUB` |
| `createdAt` | timestamp |

### Holding
`id` = UUIDv5(`6b1e3c0a-5f2d-4c8e-9a7b-3d4f5e6a7b8c`, `holding|<portfolioID>|<TICKER>`).

| Key | Type |
|---|---|
| `portfolioID` | UUID |
| `ticker` | string: trimmed and upper-cased, immutable |
| `name`, `sector` | string, optional |
| `assetClass` | `stock` \| `etf` \| `bond` \| `cash` |
| `currency` | currency code |
| `createdAt` | timestamp |

### Transaction
| Key | Type |
|---|---|
| `portfolioID`, `holdingID` | UUID |
| `kind` | `buy` \| `sell` \| `dividend` \| `fee` |
| `date` | `YYYY-MM-DD` |
| `quantity` | decimal, optional: shares traded, or the shares a dividend was paid on |
| `unitPrice` | decimal, optional: buy/sell price per share |
| `amount` | decimal, optional: dividend/fee total gross amount |
| `fee`, `tax` | decimal ≥ 0 |
| `currency` | currency code |
| `notes` | string, optional |
| `createdAt` | timestamp: breaks ties between same-day trades |

### Goal
`id` = UUIDv5(same namespace, `goal|<portfolioID>|<scope>|<key>`).

| Key | Type |
|---|---|
| `portfolioID` | UUID |
| `scope` | `holding` \| `asset_class` |
| `key` | normalized ticker, or asset class |
| `targetPercent` | decimal > 0 |
| `createdAt` | timestamp |

## Evolution

Adding or changing a field means bumping `schemaVersion` and documenting the new version in a separate file.
The CloudKit schema never changes for payload evolution. Its only fields are `payload`, `schemaVersion`,
`revision`, `modifiedAt`, `deviceID`, and `deleted`.
