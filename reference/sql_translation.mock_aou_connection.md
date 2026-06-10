# dbplyr SQL translation for mock All of Us (DuckDB) connections

Extends DuckDB's dbplyr translation with BigQuery-compatible functions
(currently `date_diff()`/`DATE_DIFF()`) used by All of Us analysis code.
Not called directly.

## Usage

``` r
# S3 method for class 'mock_aou_connection'
sql_translation(con)
```

## Arguments

- con:

  A `mock_aou_connection`.

## Value

A `dbplyr` `sql_variant`.
