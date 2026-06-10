# Seed survey responses into the mock database

Inserts `observation` rows (with PPI `_ext` rows) for the given survey
question concept ids, so
[`allofus::aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html)
returns data for them. Call with the same question concept ids you pass
to [`aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html).

## Usage

``` r
mock_seed_survey(
  con,
  concept_ids,
  answers = NULL,
  prevalence = 0.8,
  hh_yes = 0.5,
  seed = NULL,
  quiet = FALSE
)
```

## Arguments

- con:

  A connection from
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).

- concept_ids:

  Integer vector of survey question concept ids (regular and/or
  health-history "specific" concept ids).

- answers:

  Optional character vector of answer codes (value_source_value) to
  sample from, for regular questions. If `NULL`, uses the codebook
  `choices` for each question.

- prevalence:

  Fraction of participants (0-1) who respond to each question.

- hh_yes:

  For health-history questions, the fraction of responders who answer
  "Yes" (have the condition). Ignored for regular questions.

- seed:

  Optional random seed.

- quiet:

  Suppress the summary message.

## Value

The number of observation rows inserted, invisibly.

## Details

Two kinds of survey questions are handled automatically:

- **Regular** questions (those in
  [`allofus::aou_codebook`](https://rdrr.io/pkg/allofus/man/aou_codebook.html)):
  a response is inserted with `value_source_value` drawn from the
  question's answer `choices` (or from `answers`).

- **Family-health-history** questions (the "specific" condition/person
  concept ids in
  [`allofus::aou_health_history`](https://rdrr.io/pkg/allofus/man/aou_health_history.html),
  e.g. `43529932` for "type 2 diabetes / self"): responses are inserted
  in the nested structure
  [`aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html)
  expects, so it returns "Yes"/"No". The fraction answering "Yes" is
  controlled by `hh_yes`.
