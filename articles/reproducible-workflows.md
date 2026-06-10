# Reproducible and portable workflows

The [“getting
started”](https://louisahsmith.github.io/mockallofus/articles/mockallofus.md)
vignette covers interactive use. This one covers using `mockallofus` to
make All of Us analysis code **reproducible** and **portable**: building
a fixed local database, writing one script that runs both locally and on
the Researcher Workbench, and testing analysis code in CI without the
Workbench.

``` r

library(mockallofus)
library(allofus)
suppressMessages(library(dplyr))
```

## Build a database once, reuse it

[`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
builds a default database on first use and caches it. For a reproducible
project you usually want an explicit, version-pinned database instead:
control the size and the random seed, build it to a known path, seed
your study’s data, and reuse it. Generation is deterministic, so the
same `seed` always yields the same database.

``` r

db_path <- tempfile(fileext = ".duckdb") # for a real project, a stable path

build_mock_db(db_path, n_persons = 500, seed = 42, quiet = TRUE)

con <- mock_aou_connect(db_path, quiet = TRUE)
mock_seed_concept_set(con, c(201826, 4193704), domain = "condition",
                      prevalence = 0.3, seed = 1, quiet = TRUE)
```

Because the database is a file, seeded data persists. You can disconnect
and reconnect later (in another session, another script) and the data is
still there — so you build and seed once, then iterate on analysis code
against a stable dataset.

``` r

mock_aou_disconnect(con)

con <- mock_aou_connect(db_path, quiet = TRUE) # reopen the same file
tbl(con, "condition_occurrence") |>
  filter(condition_concept_id %in% c(201826, 4193704)) |>
  summarise(people = n_distinct(person_id))
#> # Source:   SQL [?? x 1]
#> # Database: DuckDB 1.5.2 [unknown@Linux 6.17.0-1015-azure:R 4.6.0//tmp/RtmpxFqVmg/file1ec410a9d9eb.duckdb]
#>    people
#>   <int64>
#> 1     345
```

[`build_mock_db()`](https://louisahsmith.github.io/mockallofus/reference/build_mock_db.md)
does nothing if the file already exists; pass `overwrite = TRUE` to
rebuild. The default cache location is
[`default_mock_db_path()`](https://louisahsmith.github.io/mockallofus/reference/default_mock_db_path.md).
A common project setup is a small script that builds and seeds the
database (committed to your repo), with the `.duckdb` file itself
git-ignored and rebuilt on demand.

## Raw SQL with `aou_sql()`

[`aou_sql()`](https://rdrr.io/pkg/allofus/man/aou_sql.html) works
locally as long as the SQL is portable. The `{CDR}` template resolves to
the local schema, just as it resolves to the curated data repository on
the Workbench.

``` r

aou_sql("
  SELECT gender_concept_id, COUNT(*) AS n
  FROM `{CDR}.person`
  GROUP BY gender_concept_id
", collect = TRUE)
#>   gender_concept_id   n
#> 1          45878463 241
#> 2          45880669 259
```

BigQuery-only SQL functions (`COUNTIF`, `APPROX_QUANTILES`, …) will not
run on the local backend; a couple of common ones (`CONTAINS_SUBSTR`,
`REGEXP_CONTAINS`) are emulated. Keep raw SQL portable, or guard
Workbench-specific queries (see the next section). dplyr/dbplyr code,
which is translated per-backend, is portable automatically.

## One script, both places

[`allofus::on_workbench()`](https://rdrr.io/pkg/allofus/man/on_workbench.html)
reports whether you are on the Researcher Workbench. Route your
connection through it and the *same script* connects to the real data on
the Workbench and to the mock database locally:

``` r

connect_aou <- function() {
  if (on_workbench()) {
    aou_connect()          # real All of Us data (BigQuery)
  } else {
    mock_aou_connect()     # local synthetic data (DuckDB)
  }
}
```

Write your analysis as a function of the connection (defaulting to the
stored option, exactly as the `allofus` functions do). Nothing inside it
is mock-specific:

``` r

high_a1c_cohort <- function(threshold = 6.5, con = getOption("aou.default.con")) {
  aou_concept_set(concepts = c(3004410, 3005673), domains = "measurement",
                  output = "all", concept_set_name = "a1c", con = con) |>
    filter(value_as_number > threshold) |>
    distinct(person_id)
}
```

Locally, seed the inputs and run it; on the Workbench, the identical
call runs against real data.

``` r

mock_seed_concept_set(con, c(3004410, 3005673), domain = "measurement",
                      prevalence = 0.4, values = c(5, 11), seed = 3, quiet = TRUE)

high_a1c_cohort(con = con) |> tally()
#> # Source:   SQL [?? x 1]
#> # Database: DuckDB 1.5.2 [unknown@Linux 6.17.0-1015-azure:R 4.6.0//tmp/RtmpxFqVmg/file1ec410a9d9eb.duckdb]
#>         n
#>   <int64>
#> 1     359
```

## Test analysis code without the Workbench

Because the mock database is deterministic and local, you can unit-test
analysis functions in CI. A typical `testthat` setup builds and seeds a
small database, then checks your function’s behavior against data you
control. For example, seeding A1c values in `c(5, 11)` at a known
prevalence lets you assert the high-A1c cohort is non-empty but not
everyone:

``` r

library(testthat)

test_that("high_a1c_cohort selects participants above the threshold", {
  # in a package, this would live in tests/testthat/ with the db built in setup
  path <- withr::local_tempfile(fileext = ".duckdb")
  build_mock_db(path, n_persons = 300, seed = 99, quiet = TRUE)
  con <- mock_aou_connect(path, quiet = TRUE)
  withr::defer(mock_aou_disconnect(con))
  mock_seed_concept_set(con, c(3004410, 3005673), domain = "measurement",
                        prevalence = 0.5, values = c(5, 11), seed = 1, quiet = TRUE)

  result <- high_a1c_cohort(con = con) |> collect()

  expect_s3_class(result, "data.frame")
  expect_true("person_id" %in% names(result))
  expect_gt(nrow(result), 0)
  expect_lt(nrow(result), 300)
})
```

    #> Test passed.

This gives you a fast, offline, reproducible test suite for code that
ultimately runs on real All of Us data — catching regressions before you
spend Workbench time.

## Summary

- Build a deterministic database with
  `build_mock_db(path, n_persons, seed)` and reuse the file across
  sessions.
- Keep raw [`aou_sql()`](https://rdrr.io/pkg/allofus/man/aou_sql.html)
  portable; dplyr/dbplyr is portable automatically.
- Route connections through
  [`on_workbench()`](https://rdrr.io/pkg/allofus/man/on_workbench.html)
  so one script runs in both places.
- Test connection-taking analysis functions against a seeded mock
  database in CI.
