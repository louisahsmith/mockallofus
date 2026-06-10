# Register BigQuery-compatibility macros on a DuckDB connection

Defines DuckDB macros so SQL written in the BigQuery dialect (as emitted
by some `allofus` functions, e.g. the `clean_answers` path of
[`aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html))
executes locally. Idempotent (`CREATE OR REPLACE`).

## Usage

``` r
register_bq_macros(con)
```

## Arguments

- con:

  A DuckDB connection (read-write).

## Value

`con`, invisibly.
