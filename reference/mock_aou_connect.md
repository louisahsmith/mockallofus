# Connect to the local mock All of Us database

Opens (building first if necessary) the local mock DuckDB database and
wires it into the `allofus` package the same way
[`allofus::aou_connect()`](https://rdrr.io/pkg/allofus/man/aou_connect.html)
does on the Researcher Workbench: the connection is stored in
`getOption("aou.default.con")` and a curated-data-repository name in
`getOption("aou.default.cdr")`. After calling this, `allofus` analysis
code that relies on those defaults runs against the mock database
unchanged.

## Usage

``` r
mock_aou_connect(
  path = default_mock_db_path(),
  cdr = "main",
  quiet = FALSE,
  ...
)
```

## Arguments

- path:

  Path to the DuckDB database file. Defaults to the cached location
  ([`default_mock_db_path()`](https://louisahsmith.github.io/mockallofus/reference/default_mock_db_path.md));
  built with
  [`build_mock_db()`](https://louisahsmith.github.io/mockallofus/reference/build_mock_db.md)
  if absent.

- cdr:

  The schema name used for `{CDR}` interpolation in `allofus` SQL
  helpers. Defaults to `"main"` (DuckDB's default schema, where the mock
  tables live), so references like `` `{CDR}.person` `` resolve.

- quiet:

  Suppress the connection message.

- ...:

  Further arguments passed to
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Value

A DuckDB connection object (`duckdb_connection`), also stored in
`getOption("aou.default.con")`.

## Details

BigQuery-compatibility macros are registered on the connection (see
[`register_bq_macros()`](https://louisahsmith.github.io/mockallofus/reference/register_bq_macros.md))
so SQL emitted by `allofus` in the BigQuery dialect executes on DuckDB.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- mock_aou_connect()
# the same code you would run on the Workbench:
dplyr::tbl(con, "person")
} # }
```
