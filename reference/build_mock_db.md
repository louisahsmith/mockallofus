# Build a local mock All of Us DuckDB database

Creates a DuckDB database file whose tables and columns mirror the All
of Us Curated Data Repository (OMOP CDM core tables plus All of Us
extension and cohort-builder tables), populated with fully synthetic,
randomly generated data. The data does **not** reflect real All of Us
data and results are not meant to be realistic; the purpose is to let
`allofus` analysis code run and be developed locally.

## Usage

``` r
build_mock_db(
  path = default_mock_db_path(),
  n_persons = 2000L,
  seed = 20240101L,
  survey_questions = NULL,
  overwrite = FALSE,
  quiet = FALSE
)
```

## Arguments

- path:

  File path for the DuckDB database. Defaults to a cached location under
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html).

- n_persons:

  Number of synthetic participants to generate. Default 2000.

- seed:

  Random seed for reproducible generation. Default 20240101.

- survey_questions:

  Optional integer vector of survey question concept ids (from
  [`allofus::aou_codebook`](https://rdrr.io/pkg/allofus/man/aou_codebook.html))
  to populate in `observation`. Defaults to a sample that includes the
  vignette questions (gender `1585838`, birthplace `1586135`).

- overwrite:

  Overwrite an existing database file. Default `FALSE` (an existing file
  at `path` is left untouched and its path returned).

- quiet:

  Suppress progress messages.

## Value

The `path` to the built database, invisibly.

## Details

All tables in the All of Us data dictionary are created (so table
references resolve); a core subset is populated with data: `person`,
`concept`, the clinical domain tables and their `_ext` tables, survey
rows in `observation`, `observation_period`, `cb_search_person`,
`ds_survey`, and `survey_conduct`. The clinical concept ids used in the
`allofus` vignettes are included so the documented workflows return
data.

Use
[`mock_seed_concept_set()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_concept_set.md)
/
[`mock_seed_survey()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_survey.md)
afterwards to guarantee coverage of the specific concepts your own study
queries.
