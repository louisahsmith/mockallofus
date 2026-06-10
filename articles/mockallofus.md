# Getting started with mockallofus

This vignette assumes you already know the [All of
Us](https://www.researchallofus.org/) data and the
[`allofus`](https://roux-ohdsi.github.io/allofus/) package — if not,
read the `allofus` “getting started” and data-extraction vignettes
first. Here we cover the one new thing you need for `mockallofus`:
**putting your study’s data into a local database so your `allofus` code
returns results.**

The mock database is synthetic and random; it does **not** reflect real
All of Us data, and results are not meaningful. The point is to develop
and debug code locally, without the (metered) Researcher Workbench.

## Connect

The only change from a Workbench script is the connection call.
[`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
builds a local DuckDB database (on first use) and stores it in
`getOption("aou.default.con")` — exactly where `allofus` looks — so
every `allofus` function works against it unchanged.

``` r

library(mockallofus)
library(allofus)
suppressMessages(library(dplyr))

con <- mock_aou_connect()
```

The database already has synthetic participants and a broad spread of
generic clinical events and survey responses, so ordinary
`dplyr`/`dbplyr` works right away:

``` r

tbl(con, "person") |> tally()
#> # Source:   SQL [?? x 1]
#> # Database: DuckDB 1.5.2 [unknown@Linux 6.17.0-1015-azure:R 4.6.0//home/runner/.cache/R/mockallofus/mock_aou.duckdb]
#>         n
#>   <int64>
#> 1    2000

tbl(con, "measurement") |>
  summarise(n = n(), n_people = n_distinct(person_id))
#> # Source:   SQL [?? x 2]
#> # Database: DuckDB 1.5.2 [unknown@Linux 6.17.0-1015-azure:R 4.6.0//home/runner/.cache/R/mockallofus/mock_aou.duckdb]
#>         n n_people
#>   <int64>  <int64>
#> 1   10002     1819
```

What it does **not** have is *your study’s specific concepts*. A query
for a particular `concept_id` or survey question will simply come back
empty — which is where seeding comes in.

## Seed your study’s data

We’ll reproduce the eligibility logic from the `allofus` paper’s case
study, which builds a cohort from electronic health record (EHR) concept
sets and survey responses. First, seed the concepts that analysis looks
for.

[`mock_seed_concept_set()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_concept_set.md)
is the workhorse: give it the same concept ids and domain you would pass
to
[`allofus::aou_concept_set()`](https://rdrr.io/pkg/allofus/man/aou_concept_set.html),
plus a `prevalence` (the fraction of participants who should have the
concept). Keeping prevalence below 1 is what makes eligibility joins
return a *partial* cohort — some people qualify, some don’t — which is
what you want when developing filtering logic.

``` r

# devices, a condition/drug set, and a lab test (with values in a chosen range)
mock_seed_concept_set(con, c(2616672, 3034639), domain = "device",
                      prevalence = 0.15, seed = 1)
mock_seed_concept_set(con, c(201826, 4193704), domain = "condition",
                      prevalence = 0.20, seed = 2)
mock_seed_concept_set(con, c(40164929, 40164897), domain = "drug",
                      prevalence = 0.20, seed = 3)
mock_seed_concept_set(con, c(3004410, 3005673), domain = "measurement",
                      prevalence = 0.30, values = c(4, 11), seed = 4)
```

Survey questions are seeded with
[`mock_seed_survey()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_survey.md),
using the same question concept ids you pass to
[`allofus::aou_survey()`](https://rdrr.io/pkg/allofus/man/aou_survey.html).
Both ordinary survey questions and family-health-history questions work:
here we seed a health-history question (type 2 diabetes, concept id
`43529932`) plus education and income. For health-history questions,
`hh_yes` sets the fraction who answer “Yes”.

``` r

mock_seed_survey(con, c(43529932, 1585940, 1585375),
                 prevalence = 0.8, hh_yes = 0.3, seed = 5)
```

## Run your analysis, unchanged

From here the code is ordinary `allofus`. Build an eligibility cohort:
everyone whose full year before their first survey falls within their
observation period.

``` r

observation_period_tbl <- aou_observation_period()

survey_date_tbl <- tbl(con, "ds_survey") |>
  summarize(first_survey = as.Date(min(survey_datetime)), .by = "person_id") |>
  mutate(year_before_survey = DATE_ADD(first_survey, sql(paste("INTERVAL", -1, "year"))))

eligible <- survey_date_tbl |>
  aou_join(observation_period_tbl, type = "inner",
           by = join_by(person_id,
                        within(year_before_survey, first_survey,
                               observation_period_start_date,
                               observation_period_end_date)))

tally(eligible)
#> # Source:   SQL [?? x 1]
#> # Database: DuckDB 1.5.2 [unknown@Linux 6.17.0-1015-azure:R 4.6.0//home/runner/.cache/R/mockallofus/mock_aou.duckdb]
#>         n
#>   <int64>
#> 1    1805
```

Pull EHR concept sets over the year before the survey and exclude
participants who have a device or repeated high lab values:

``` r

device <- aou_concept_set(eligible, c(2616672, 3034639),
                          start_date = "year_before_survey", end_date = "first_survey",
                          output = "indicator", concept_set_name = "device",
                          domains = "device") |>
  filter(device == 1) |>
  distinct(person_id)

lab_test <- aou_concept_set(eligible, c(3004410, 3005673),
                            start_date = "year_before_survey", end_date = "first_survey",
                            output = "all", concept_set_name = "lab_test",
                            domains = "measurement") |>
  filter(value_as_number > 6.5) |>
  summarise(n = n(), .by = "person_id") |>
  filter(n >= 2) |>
  distinct(person_id)

ineligible <- list(device, lab_test) |>
  purrr::reduce(union_all) |>
  aou_compute()

eligible <- anti_join(eligible, ineligible, by = "person_id")
```

Finally, attach survey data and keep only participants who did **not**
report type 2 diabetes:

``` r

survey_data <- aou_survey(eligible, questions = c(43529932, 1585940, 1585375),
                          question_output = c("t2dm", "edu", "income"))

eligible <- survey_data |>
  filter(t2dm == "No") |>
  aou_join(eligible, type = "inner", by = "person_id")

cohort <- collect(eligible)
nrow(cohort)
#> [1] 975
head(cohort)
#> # A tibble: 6 × 11
#>   person_id t2dm  income    edu   t2dm_date  income_date edu_date   first_survey
#>     <int64> <chr> <chr>     <chr> <date>     <date>      <date>     <date>      
#> 1   1000002 No    AnnualIn… High… 2022-09-30 2018-03-31  2022-02-28 2018-12-20  
#> 2   1000003 No    AnnualIn… High… 2021-03-19 2018-12-12  2019-08-15 2019-10-07  
#> 3   1000004 No    AnnualIn… High… 2017-08-20 2019-08-03  2019-05-02 2019-08-09  
#> 4   1000005 No    NA        High… 2020-01-26 NA          2020-04-15 2020-10-06  
#> 5   1000007 No    NA        PMI_… 2020-02-21 NA          2020-03-22 2019-10-15  
#> 6   1000010 No    NA        High… 2017-11-21 NA          2022-05-31 2020-03-04  
#> # ℹ 3 more variables: year_before_survey <date>,
#> #   observation_period_start_date <date>, observation_period_end_date <date>
```

That is the whole workflow: connect, seed the concepts/questions your
study uses, then run your real `allofus` code.

## Finer control over seeded data

[`mock_seed_concept_set()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_concept_set.md)
scatters a concept randomly across participants. When you need exact
control — specific people, specific dates, temporally structured events
— use the lower-level primitives:

- `mock_add_concepts(con, concept_id, concept_name, domain_id)` — add
  concept definitions (with real names, so name-based lookups work).
- `mock_add_occurrences(con, domain, person_id, concept_id, date, value, source)`
  — add events to a domain table, generating keys and the matching
  `_ext` source rows automatically.
- `mock_person_ids(con)` — the participant ids to attach data to.

``` r

ids <- mock_person_ids(con)
mock_add_concepts(con, 99999001, "My study's condition", domain_id = "Condition")
mock_add_occurrences(con, "condition", person_id = ids[1:50],
                     concept_id = 99999001, date = as.Date("2021-03-15"))
```

For a worked example that builds a temporally coherent cohort with these
primitives — the HIPPS pregnancy algorithm run end-to-end on the mock
database — see
[`vignette("hipps-pregnancy-example")`](https://louisahsmith.github.io/mockallofus/articles/hipps-pregnancy-example.md).

## What works, and what doesn’t

Most `allofus` workflows run unchanged; common BigQuery idioms are
translated automatically; and a few Workbench/cloud features (bucket
I/O,
[`aou_atlas_cohort()`](https://rdrr.io/pkg/allofus/man/aou_atlas_cohort.html))
have no local equivalent. For the full breakdown, see [*What’s different
from the Researcher
Workbench*](https://louisahsmith.github.io/mockallofus/articles/whats-different.md).
