# What's different from the Researcher Workbench

`mockallofus` aims to let the *same* `allofus` analysis code run locally
and on the All of Us Researcher Workbench. Most of it does, unchanged.
This page is the reference for what is fully supported, what is quietly
translated, and the few things that cannot work locally.

## The data is synthetic

The most important difference is the data itself. The mock database
contains **randomly generated, synthetic data** that does not resemble
real All of Us data (using real data here would violate the data use
agreement), so:

- **Results are not meaningful** — the goal is to exercise code, not to
  learn anything about pregnancy, diabetes, or anything else.
- **It does not contain your study’s concepts by default.** A query for
  a specific `concept_id` or survey question returns nothing until you
  [seed](https://louisahsmith.github.io/mockallofus/articles/mockallofus.md)
  it. This is a feature: you control exactly which concepts exist and at
  what prevalence.
- The `concept` table is a small mock vocabulary, not the full OMOP
  vocabulary, and `concept_ancestor` / `concept_relationship` are empty
  by default. If you need the real vocabulary — for example, to develop
  descendant/ancestor queries locally instead of on the Workbench —
  download the vocabulary files from [Athena](https://athena.ohdsi.org)
  and load them with
  \[[`mock_load_vocabulary()`](https://louisahsmith.github.io/mockallofus/reference/mock_load_vocabulary.md)\].

## Works unchanged

These run locally exactly as on the Workbench (`con` comes from
[`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
instead of
[`aou_connect()`](https://rdrr.io/pkg/allofus/man/aou_connect.html)):

| Function / pattern | Notes |
|----|----|
| `tbl(con, "<table>")` + dplyr/dbplyr | Translated per-backend automatically |
| [`aou_join()`](https://rdrr.io/pkg/allofus/man/aou_join.html) | Including inequality/[`within()`](https://rdrr.io/r/base/with.html) joins |
| [`aou_concept_set()`](https://rdrr.io/pkg/allofus/man/aou_concept_set.html) | `indicator`, `count`, `all` outputs; date windows |
| [`aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html) | Regular **and** family-health-history questions |
| [`aou_observation_period()`](https://rdrr.io/pkg/allofus/man/aou_observation_period.html) | Computed from seeded EHR events |
| [`aou_compute()`](https://rdrr.io/pkg/allofus/man/aou_compute.html), [`aou_create_temp_table()`](https://rdrr.io/pkg/allofus/man/aou_create_temp_table.html) | Temp tables on DuckDB |
| [`aou_collect()`](https://rdrr.io/pkg/allofus/man/aou_collect.html) | `integer64` -\> double conversion as on the Workbench |
| [`aou_sql()`](https://rdrr.io/pkg/allofus/man/aou_sql.html) | **If the SQL is portable** — see below |

All of the All of Us OMOP/CDM tables exist in the mock database (so
table references resolve), with the core clinical, survey, and
cohort-builder tables populated.

## Translated or emulated automatically

[`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
attaches translations and macros so common BigQuery idioms in All of Us
code run on DuckDB without changes:

**Case does not matter.** Like SQL, these function names are
case-insensitive: write `DATE_DIFF()` or `date_diff()`, `DATE_ADD()` or
`date_add()`, and so on. dbplyr passes the name straight through to SQL,
where case is irrelevant, so whichever case appears in your code (or in
the examples below) works.

| BigQuery idiom | Handled by |
|----|----|
| `date_diff(a, b, sql("day"))` (3-arg) | dbplyr translation -\> DuckDB `date_diff('day', b, a)` |
| `date_add(d, sql("INTERVAL -1 year"))` | dbplyr translation -\> DuckDB interval arithmetic |
| [`as.Date()`](https://rdrr.io/r/base/as.Date.html) of float-y strings (`"1994-5.0-28.0"`) | dbplyr translation (tolerant cast) |
| `string_agg()`, `cast(x AS string/int64)`, `ifnull()`, `regexp_extract()` | Native in DuckDB |
| `contains_substr()`, `regexp_contains()`, `countif()` | DuckDB macros (\[[`register_bq_macros()`](https://louisahsmith.github.io/mockallofus/reference/register_bq_macros.md)\]) |
| `collect(page_size = ...)` | `page_size` (a bigrquery argument) is ignored locally |

## Not available locally

These rely on Workbench/cloud infrastructure with no local equivalent.
They are out of scope by design — guard them with
[`allofus::on_workbench()`](https://rdrr.io/pkg/allofus/man/on_workbench.html)
(see the [“reproducible
workflows”](https://louisahsmith.github.io/mockallofus/articles/reproducible-workflows.md)
article).

| Function | Why |
|----|----|
| [`aou_workspace_to_bucket()`](https://rdrr.io/pkg/allofus/man/aou_workspace_to_bucket.html), [`aou_bucket_to_workspace()`](https://rdrr.io/pkg/allofus/man/aou_bucket_to_workspace.html) | Google Cloud Storage bucket I/O |
| [`aou_ls_workspace()`](https://rdrr.io/pkg/allofus/man/aou_ls_workspace.html), [`aou_ls_bucket()`](https://rdrr.io/pkg/allofus/man/aou_ls_bucket.html) | List Workbench / bucket files |
| [`aou_atlas_cohort()`](https://rdrr.io/pkg/allofus/man/aou_atlas_cohort.html) | Generates BigQuery-dialect SQL via `SqlRender` |
| [`aou_sql()`](https://rdrr.io/pkg/allofus/man/aou_sql.html) with BigQuery-only functions | `APPROX_QUANTILES`, etc. don’t exist in DuckDB |
| [`aou_session_info()`](https://rdrr.io/pkg/allofus/man/aou_session_info.html) CDR metadata | Reads Workbench-specific metadata tables |

For local file output, use `readr::write_*()` /
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) in place of the
bucket helpers.

## Other behavioral notes

- **Connection class.**
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
  returns a DuckDB connection (an S4 subclass, `mock_aou_connection`),
  not a `BigQueryConnection`. Code that branches on the connection class
  should use
  [`allofus::on_workbench()`](https://rdrr.io/pkg/allofus/man/on_workbench.html)
  instead.
- **Single writer.** A DuckDB file allows one read-write connection at a
  time; disconnect
  ([`mock_aou_disconnect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_disconnect.md))
  before reopening elsewhere.
- **Determinism.** Database generation and seeding are deterministic for
  a fixed `seed`, so tests and examples are reproducible.
