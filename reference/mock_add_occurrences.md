# Add clinical-event occurrences to the mock database

Inserts rows into one of the OMOP clinical-event domain tables,
generating surrogate keys automatically and writing the matching `_ext`
row (which All of Us uses to record data source: EHR vs
survey/physical-measurement). This is the primitive for putting custom
events into the mock database — e.g. giving a specific set of
participants a specific concept on specific dates.

## Usage

``` r
mock_add_occurrences(
  con,
  domain,
  person_id,
  concept_id,
  date,
  value = NULL,
  source = c("ehr", "ppi")
)
```

## Arguments

- con:

  A connection from
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).

- domain:

  One of "condition", "drug", "measurement", "observation", "procedure",
  "device", "visit".

- person_id:

  Integer vector of participant ids (one per occurrence).

- concept_id:

  Integer concept id(s); recycled to `length(person_id)`.

- date:

  Event date(s) (Date or coercible); recycled to `length(person_id)`.
  Used for the domain's start date (and end date, where the table has
  one).

- value:

  Optional numeric value(s) written to `value_as_number` where the table
  has that column (e.g. measurements, observations).

- source:

  `"ehr"` tags the `_ext` row as EHR-sourced (`src_id` like "EHR site
  105", which EHR-based functions such as
  [`allofus::aou_observation_period()`](https://rdrr.io/pkg/allofus/man/aou_observation_period.html)
  look for); `"ppi"` tags it as survey/physical-measurement ("PPI/PM").

## Value

The generated surrogate ids, invisibly.

## Details

`person_id`, `concept_id`, and `date` are treated row-wise (recycled to
a common length), so one call inserts one occurrence per `person_id`
element.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- mock_aou_connect()
ids <- mock_person_ids(con)[1:50]
mock_add_concepts(con, 201826, "Type 2 diabetes mellitus", domain_id = "Condition")
mock_add_occurrences(con, "condition", person_id = ids, concept_id = 201826,
                     date = as.Date("2021-03-15"))
} # }
```
