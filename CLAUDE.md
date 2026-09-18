# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`mockallofus` builds a local DuckDB database of fully synthetic data whose tables
and columns mirror the *All of Us* Curated Data Repository (OMOP CDM + All of Us
extension/cohort-builder tables), so `allofus` analysis code can be developed and
tested off the (paid, BigQuery-backed) Researcher Workbench.

The central design promise: **the only line that changes between a local script
and a Workbench script is `mock_aou_connect()` instead of `allofus::aou_connect()`.**
Every architectural decision below exists to preserve that. When adding features,
ask whether they keep local and Workbench code identical; if a divergence is
unavoidable, it must be documented in `vignettes/whats-different.Rmd`.

## Development commands

```r
devtools::load_all()
devtools::test()
devtools::document()   # regenerates man/ and NAMESPACE from roxygen; never edit those by hand
devtools::check()
pkgdown::build_site()
```

Run a single test file or filter:

```r
devtools::test(filter = "translation")   # -> tests/testthat/test-translation.R
testthat::test_file("tests/testthat/test-seed.R")
```

CI runs **only** `pkgdown` (`.github/workflows/pkgdown.yaml`) — there is no
R-CMD-check workflow, so `devtools::check()` locally is the only gate.

`allofus` must come from the `mock-duckdb-support` branch (declared in
`Remotes:`); its backend-aware query execution is what lets `allofus` functions
run against DuckDB at all:

```r
pak::pak("roux-ohdsi/allofus@mock-duckdb-support")
```

`tests/testthat/test-allofus-integration.R` skips when `allofus` is absent, so a
green test run without it proves much less than it looks like.

## Architecture

### Schema comes from bundled data, not hand-written DDL

`R/sysdata.rda` holds four datasets copied from `allofus`: `aou_table_info`
(table name → comma-separated column list), `aou_codebook` (survey questions,
answer `choices`, `field_type`), `aou_health_history`, `aou_concept_codes`.
Bundling them means the mock db can be built without loading `allofus` and its
BigQuery stack.

`build_mock_db()` creates *every* table in `aou_table_info` (so any table
reference resolves) and populates a core subset. Column types are **inferred from
column names** by `duckdb_type()` in [R/utils.R](R/utils.R) — `*_date` → DATE,
`*_id` → BIGINT, `has_*`/`is_*` → INTEGER, etc., with a hard-coded override list
for the OMOP vocabulary keys that end in `_id` but are strings (`src_id`,
`domain_id`, `vocabulary_id`, ...). A new type problem is usually fixed there,
not at the call site.

`table_spec()` also scrubs upstream dictionary defects (whitespace inside column
names, duplicated columns). Regenerate `sysdata.rda` with
[data-raw/prepare_data.R](data-raw/prepare_data.R) when the upstream `allofus`
datasets change — note it reads a **hard-coded absolute path** to a local clone
of the `allofus` repo.

### Layers, lowest to highest

1. [R/utils.R](R/utils.R) — `table_spec()`, `duckdb_type()`, `assemble_rows()`,
   concept pools, `resample()`, `parse_choice_codes()`.
2. [R/build_mock_db.R](R/build_mock_db.R) — `populate_*()` generators, one per
   table/domain, plus `default_mock_db_path()` / `find_project_dir()`.
3. [R/mock_add.R](R/mock_add.R) — exported primitives `mock_add_concepts()`,
   `mock_add_occurrences()`, `mock_person_ids()`, plus `domain_map()` (the single
   source of truth mapping a domain name to its table/id/concept/start/end
   columns) and `next_id()`.
4. [R/mock_seed.R](R/mock_seed.R) — user-facing `mock_seed_concept_set()` /
   `mock_seed_survey()`, built entirely on layer 3.

`assemble_rows(spec, n, values)` is the pattern that holds this together: a
generator supplies only the columns it cares about and gets back a full-width,
correctly-typed frame (missing columns filled with typed `NA`) ready for
`DBI::dbAppendTable()`. Never build a frame column-by-column against a table's
real schema; go through `table_spec()` + `assemble_rows()`.

### The `_ext` invariant

Every inserted clinical row needs a matching row in the table's `_ext` companion
carrying `src_id` — `"EHR site <n>"` for EHR-sourced, `"PPI/PM"` for
survey/physical-measurement. `allofus` functions like
`aou_observation_period()` filter on this, so a row without its `_ext` partner is
invisible to them. Any new insertion path must write both tables (the existing
generators and `mock_add_occurrences()` all do).

### Two separate BigQuery-compatibility mechanisms

They are not interchangeable, and picking the wrong one is the most likely
mistake here:

- **DuckDB macros** ([R/register_macros.R](R/register_macros.R)) — for BigQuery
  functions that are missing from DuckDB but expressible in SQL:
  `CONTAINS_SUBSTR`, `REGEXP_CONTAINS`, `COUNTIF`. Registered per-connection by
  `register_bq_macros()`, idempotent via `CREATE OR REPLACE`.
- **dbplyr translations** ([R/translation.R](R/translation.R)) — for idioms a
  macro *cannot* handle: a signature clash (BigQuery's 3-arg
  `date_diff(a, b, sql("day"))` vs DuckDB's `date_diff(part, start, end)`), a
  bare unit identifier, a negative `INTERVAL` literal, or a cast that must be
  rewritten (`as.Date()` on `"1994-5.0-28.0"`, which All of Us date-of-birth code
  produces because `if_else()` promotes integer parts to double).

Rule of thumb: if the fix needs to see the R call before SQL generation, it's a
translation; if it's a plain SQL-level function shim, it's a macro. Both
`lower_case` and `UPPER_CASE` spellings are registered for translated functions,
since dbplyr passes names through verbatim.

### The connection object

`mock_aou_connect()` opens DuckDB with `bigint = "integer64"` (matching
`aou_connect()`), then upgrades the connection to the S4 subclass
`mock_aou_connection` (`contains = "duckdb_connection"`). The subclass is defined
inside `.onLoad()` in [R/zzz.R](R/zzz.R), not at top level, so duckdb's S4 class
exists when it is created. The subclass is the *only* clean hook for attaching
translations — modifying the DuckDB S4 object directly corrupts it.

Two S3 methods hang off it, registered via `@exportS3Method` on dbplyr generics:

- `sql_translation.mock_aou_connection` — extends DuckDB's translation table.
- `db_collect.mock_aou_connection` — drops BigQuery-only download args
  (`page_size`, `billing`, ...) that DuckDB's `collect()` would reject.

Both delegate to the parent method fetched with
`utils::getS3method(..., envir = asNamespace("dbplyr"))`.

The contract with `allofus` is entirely through options:
`aou.default.con` (the connection) and `aou.default.cdr = "main"` (so
`` `{CDR}.person` `` interpolation resolves to DuckDB's default schema).

### Database location

`default_mock_db_path()` → `getOption("mockallofus.path")`, else
`mock_aou.duckdb` in the **project directory**, found by walking up for a
`.Rproj`, `.git`, `.here`, or `DESCRIPTION`. Deliberately per-project rather than
a global cache. DuckDB allows one read-write connection per file — disconnect
before reopening elsewhere.

## Conventions

- **Determinism is a feature.** Build and seeding are reproducible for a fixed
  `seed` (via `withr::local_seed()`), and tests and vignettes depend on it.
  Don't introduce unseeded randomness.
- **Use `resample(x, n)`, not `sample(x, n, replace = TRUE)`**, for concept pools:
  base `sample()` silently switches to `sample.int()` when `x` has length 1.
- Package internals use base-R idioms (`for`, `vapply`, `lapply`, `ifelse`) in
  the generators alongside `purrr`/`dplyr` elsewhere. Match the surrounding file
  rather than importing the tidyverse-first style used for analysis scripts.
- User-facing messages go through `cli` (`cli_inform`/`cli_warn`/`cli_abort`) and
  every noisy function takes `quiet`.
- Seeded data attaches to participants already in `person` (via
  `mock_person_ids()`), and surrogate keys come from `next_id()`, so referential
  integrity and key uniqueness hold across repeated seeding.

### Adding a new exported function

1. Implement it in the right layer (reuse `mock_add_*` primitives rather than
   writing raw inserts).
2. roxygen docs with `@export`, then `devtools::document()`.
3. Add it to the matching `reference:` section of
   [_pkgdown.yml](_pkgdown.yml) — pkgdown (and therefore CI) fails if an
   exported function is missing from the index.
4. Add tests in `tests/testthat/`; use the `local_mock_con()` helper from
   [tests/testthat/helper-mockdb.R](tests/testthat/helper-mockdb.R), which builds
   a small db in a temp file per test so write-heavy seeding tests don't
   interfere.
5. If it changes what does or doesn't work locally, update
   `vignettes/whats-different.Rmd`.
