# Seed a concept set into the mock database

Guarantees that the given concepts exist (in `concept` and as
occurrences in the appropriate domain table, with matching EHR `_ext`
rows) for a fraction of participants. Use this so that
[`allofus::aou_concept_set()`](https://rdrr.io/pkg/allofus/man/aou_concept_set.html)
queries for your study's concepts return non-empty, develop-able
results. Call with the same `concepts`/`domain` you pass to
[`aou_concept_set()`](https://rdrr.io/pkg/allofus/man/aou_concept_set.html).

## Usage

``` r
mock_seed_concept_set(
  con,
  concepts,
  domain = "condition",
  prevalence = 0.3,
  max_per_person = 3L,
  values = c(0, 100),
  seed = NULL,
  quiet = FALSE
)
```

## Arguments

- con:

  A connection from
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).

- concepts:

  Integer vector of concept ids to seed.

- domain:

  One of "condition", "drug", "measurement", "observation", "procedure",
  "device", "visit".

- prevalence:

  Fraction of participants (0-1) who should have at least one
  occurrence. Values below 1 make eligibility joins return partial
  cohorts.

- max_per_person:

  Maximum occurrences generated per selected participant.

- values:

  For `domain = "measurement"`, a length-2 numeric range for
  `value_as_number`. Ignored for other domains.

- seed:

  Optional random seed for reproducible seeding.

- quiet:

  Suppress the summary message.

## Value

The number of occurrence rows inserted, invisibly.

## Details

For finer control (specific participants, specific dates), use the
lower-level
[`mock_add_occurrences()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_occurrences.md)
/
[`mock_add_concepts()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_concepts.md)
directly.
