# Disconnect from the mock database and clear the stored connection

Disconnect from the mock database and clear the stored connection

## Usage

``` r
mock_aou_disconnect(con = getOption("aou.default.con"), shutdown = TRUE)
```

## Arguments

- con:

  The connection to close. Defaults to `getOption("aou.default.con")`.

- shutdown:

  Whether to shut down the DuckDB instance. Default `TRUE`.

## Value

`NULL`, invisibly.
