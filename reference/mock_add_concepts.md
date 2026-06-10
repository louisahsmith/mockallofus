# Add concept definitions to the mock database

Inserts rows into the `concept` table for any `concept_id`s not already
present. Use this so that concept-name lookups (e.g. searching
`concept_name`) and joins on `concept_id` find your study's concepts.
Concepts already present are skipped, so it is safe to call repeatedly.

## Usage

``` r
mock_add_concepts(
  con,
  concept_id,
  concept_name = NULL,
  domain_id = "Observation"
)
```

## Arguments

- con:

  A connection from
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).

- concept_id:

  Integer vector of concept ids.

- concept_name:

  Optional character vector of names (parallel to `concept_id`). If
  `NULL`, generic placeholder names are used. Supply real names when
  your code searches `concept_name` (e.g. by `str_detect()`).

- domain_id:

  Value for the `domain_id` column (e.g. "Condition", "Drug").

## Value

The number of concept rows inserted, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- mock_aou_connect()
mock_add_concepts(con, c(201826, 4193704),
                  c("Type 2 diabetes mellitus", "T2DM without complication"),
                  domain_id = "Condition")
} # }
```
