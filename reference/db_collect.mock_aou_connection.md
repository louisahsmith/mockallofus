# Collect method that tolerates BigQuery-only download arguments

All of Us code often calls `collect(page_size = ...)`, where `page_size`
is a `bigrquery` download argument. DuckDB's
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html)
rejects unknown `...` arguments, so drop the BigQuery-specific ones
before collecting.

## Usage

``` r
# S3 method for class 'mock_aou_connection'
db_collect(con, sql, n = -1, warn_incomplete = TRUE, ...)
```

## Arguments

- con:

  A `mock_aou_connection`.

- sql, n, warn_incomplete, ...:

  Passed to the underlying DBI collect method.

## Value

A data frame.
