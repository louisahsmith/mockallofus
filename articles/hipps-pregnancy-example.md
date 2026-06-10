# Developing a real pipeline locally: the HIPPS pregnancy algorithm

This vignette shows how to develop a substantial, real-world All of Us
analysis against a local mock database. The example is the **HIPPS
pregnancy algorithm**
([louisahsmith/allofus-pregnancy](https://github.com/louisahsmith/allofus-pregnancy)),
which identifies pregnancy episodes from OMOP clinical-event tables. We
run its unmodified algorithm code on a local DuckDB database built by
`mockallofus`.

The synthetic data is random and does **not** resemble real All of Us
data; the goal is to exercise the code, not to produce meaningful
results.

The general recipe is:

1.  Connect to a mock database with
    [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).
2.  **Seed** the data your analysis looks for, so its queries return
    rows.
3.  Run your analysis code exactly as you would on the Workbench.

## Seeding: the building blocks

A freshly built mock database contains synthetic participants and a
broad spread of generic events, but it won’t contain *your study’s*
specific concepts. The two exported primitives below let you put exactly
the data your code needs into the database:

- [`mock_add_concepts()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_concepts.md)
  — add rows to the `concept` table (so concept-name searches and
  `concept_id` joins find them).
- [`mock_add_occurrences()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_occurrences.md)
  — add clinical-event rows to a domain table (`condition_occurrence`,
  `measurement`, …), automatically generating surrogate keys and the
  matching `_ext` source-tracking rows.

``` r

library(mockallofus)
suppressMessages(library(dplyr))

# build a small database in a temp file for this example
con <- mock_aou_connect(path = tempfile(fileext = ".duckdb"), quiet = TRUE)

# define a custom concept, then give it to 20 participants on a specific date
mock_add_concepts(con, 99999001, "My custom condition", domain_id = "Condition")
people <- mock_person_ids(con)
mock_add_occurrences(
  con,
  domain     = "condition",
  person_id  = people[1:20],
  concept_id = 99999001,
  date       = as.Date("2021-06-01"),
  source     = "ehr"
)

# the seeded data is now queryable, exactly as real data would be
tbl(con, "condition_occurrence") |>
  filter(condition_concept_id == 99999001) |>
  summarise(n = n()) |>
  collect()
#> # A tibble: 1 × 1
#>         n
#>   <int64>
#> 1      20
```

[`mock_add_occurrences()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_occurrences.md)
recycles `concept_id` and `date`, so you can pass a vector per
participant to build up temporally structured data — which is what the
pregnancy example below does. `source = "ehr"` tags the `_ext` row so
that EHR-based functions (such as
[`allofus::aou_observation_period()`](https://rdrr.io/pkg/allofus/man/aou_observation_period.html))
see the event.

For coarser, prevalence-based seeding there are also
[`mock_seed_concept_set()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_concept_set.md)
and
[`mock_seed_survey()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_survey.md),
which are built on these same primitives.

## The full HIPPS pipeline

The remaining code reproduces the project’s `code/01_run-hipps.qmd`
against the mock database. It is **not executed when this vignette is
built** (it downloads the algorithm and code lists from GitHub and takes
a little time), but it is complete and runnable — copy it into a script
and run it.

Only three things differ from running on the Workbench, all marked
below:

1.  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
    replaces
    [`aou_connect()`](https://rdrr.io/pkg/allofus/man/aou_connect.html).
2.  `seed_mock_pregnancies()` inserts synthetic pregnancies (the mock
    database has none by default).
3.  The final
    [`aou_workspace_to_bucket()`](https://rdrr.io/pkg/allofus/man/aou_workspace_to_bucket.html)
    (Google Cloud Storage) step is dropped.

``` r

library(tidyverse)
library(allofus)     # the mock-duckdb-support branch (see installation)
library(mockallofus)

# the project's algorithm code and code lists, read straight from GitHub
repo <- "https://raw.githubusercontent.com/louisahsmith/allofus-pregnancy/main/"
source_repo <- function(path) source(url(paste0(repo, path)))
read_repo_xlsx <- function(path) {
  tmp <- tempfile(fileext = ".xlsx")
  download.file(paste0(repo, path), tmp, mode = "wb", quiet = TRUE)
  readxl::read_excel(tmp)
}

# (1) connect to a local mock database instead of aou_connect()
con <- mock_aou_connect()
```

### Seeding synthetic pregnancies

This function is the part you would adapt for your own study. It is the
same pattern as the simple demo above, just richer: it builds
*temporally coherent* pregnancies so the algorithm’s date logic
(gestational windows, outcome timing) has something to find. Read the
comments as a template for manufacturing structured data for a different
project.

``` r

seed_mock_pregnancies <- function(con, n_pregnancies = 250L, seed = 99L) {

  # --- 0. the study's code lists -------------------------------------------
  # HIP_concepts: pregnancy-related concepts, each tagged with an outcome
  #   `category` (LB = live birth, DELIV = delivery, SB = stillbirth,
  #   AB/SA = abortion, ECT = ectopic, PREG = gestation marker) and, for
  #   gestation markers, a `gest_value` (weeks).
  # PPS_concepts: "pregnancy progression signature" concepts with the
  #   gestational month window in which each typically occurs.
  hip <- read_repo_xlsx("data/HIP_concepts.xlsx")
  pps <- read_repo_xlsx("data/PPS_concepts.xlsx") |>
    mutate(domain_concept_id = as.integer(domain_concept_id))
  gestation_markers <- filter(hip, category == "PREG", !is.na(gest_value))

  # approximate days from conception to each outcome type, used to place the
  # outcome event a realistic distance after conception
  term_days <- c(LB = 270, DELIV = 270, SB = 200, AB = 70, SA = 70, ECT = 56)

  # --- 1. make sure every concept EXISTS in `concept` -----------------------
  # The algorithm both joins on concept_id and searches concept_name (e.g.
  # str_detect(concept_name, "gestation period")), so we insert the real names.
  # Concepts already present are skipped.
  mock_add_concepts(con, hip$concept_id, hip$concept_name, domain_id = "Observation")
  mock_add_concepts(con, pps$domain_concept_id, pps$domain_concept_name, domain_id = "Measurement")

  # --- 2. choose who is "pregnant" ------------------------------------------
  # Pick reproductive-age women from the existing participants (so every seeded
  # event attaches to a real person_id and all downstream joins stay consistent).
  set.seed(seed)
  women <- DBI::dbGetQuery(con, "
    SELECT person_id, year_of_birth, month_of_birth, day_of_birth
    FROM person WHERE sex_at_birth_concept_id <> 45880669")          # <> Male
  women$person_id <- as.integer(women$person_id)
  preg <- women[sample(nrow(women), min(n_pregnancies, nrow(women))), ]

  # --- 3. give each pregnancy a coherent timeline ---------------------------
  dob <- as.Date(sprintf("%d-%02d-%02d", preg$year_of_birth,
                         ifelse(is.na(preg$month_of_birth), 1, preg$month_of_birth),
                         ifelse(is.na(preg$day_of_birth), 1, preg$day_of_birth)))
  # conceive at age 20-38
  conception <- dob + sample(20:38, nrow(preg), TRUE) * 365L + sample.int(364L, nrow(preg), TRUE)
  outcome_cat <- sample(names(term_days), nrow(preg), TRUE,
                        prob = c(.45, .2, .03, .12, .15, .05))
  outcome_date <- conception + term_days[outcome_cat]

  # --- 4. insert the events with mock_add_occurrences() ---------------------
  # (a) one outcome event per pregnancy, in condition_occurrence. We pick a
  #     concept_id of the chosen outcome category for each pregnancy. (sample.int
  #     on the index avoids base sample()'s length-1 trap and keeps types clean.)
  pick_concept <- function(cat) {
    pool <- hip$concept_id[hip$category == cat]
    as.integer(pool[sample.int(length(pool), 1)])
  }
  outcome_concept <- vapply(outcome_cat, pick_concept, integer(1))
  mock_add_occurrences(con, "condition",
    person_id = preg$person_id, concept_id = outcome_concept,
    date = outcome_date, source = "ehr")

  # (b) two gestation markers per pregnancy, in observation, placed at
  #     conception + (gest_value weeks). Because mock_add_occurrences() inserts
  #     one row per person_id element, we expand to two rows per person here.
  gm <- map_dfr(seq_len(nrow(preg)), function(i) {
    g <- gestation_markers[sample(nrow(gestation_markers), 2), ]
    tibble(person_id = preg$person_id[i],
           concept_id = g$concept_id,
           date = conception[i] + as.integer(g$gest_value) * 7L,
           value = as.numeric(g$gest_value))
  })
  mock_add_occurrences(con, "observation",
    person_id = gm$person_id, concept_id = gm$concept_id,
    date = gm$date, value = gm$value, source = "ehr")

  # (c) one PPS marker per pregnancy, in measurement, at the midpoint of its
  #     typical gestational-month window.
  pm <- map_dfr(seq_len(nrow(preg)), function(i) {
    p <- pps[sample(nrow(pps), 1), ]
    tibble(person_id = preg$person_id[i],
           concept_id = p$domain_concept_id,
           date = conception[i] + as.integer((p$min_month + p$max_month) / 2 * 30))
  })
  mock_add_occurrences(con, "measurement",
    person_id = pm$person_id, concept_id = pm$concept_id,
    date = pm$date, source = "ehr")

  invisible(nrow(preg))
}

# (2) seed synthetic pregnancies
seed_mock_pregnancies(con)
```

### Running the algorithm

From here the code is identical to `01_run-hipps.qmd` — the same
[`tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) references,
the same
[`aou_create_temp_table()`](https://rdrr.io/pkg/allofus/man/aou_create_temp_table.html)
/ [`aou_compute()`](https://rdrr.io/pkg/allofus/man/aou_compute.html)
calls, and the same sourced algorithm functions.

``` r

person_tbl               <- tbl(con, "person")
concept_tbl              <- tbl(con, "concept")
observation_tbl          <- tbl(con, "observation")
measurement_tbl          <- tbl(con, "measurement")
condition_occurrence_tbl <- tbl(con, "condition_occurrence")
procedure_occurrence_tbl <- tbl(con, "procedure_occurrence")
visit_occurrence_tbl     <- tbl(con, "visit_occurrence")

HIP_concepts <- read_repo_xlsx("data/HIP_concepts.xlsx") |> aou_create_temp_table()
PPS_concepts <- read_repo_xlsx("data/PPS_concepts.xlsx") |>
  mutate(domain_concept_id = as.integer(domain_concept_id)) |> aou_create_temp_table()
Matcho_outcome_limits <- read_repo_xlsx("data/Matcho_outcome_limits.xlsx")
Matcho_term_durations <- read_repo_xlsx("data/Matcho_term_durations.xlsx") |> aou_create_temp_table()

# outcome-based (HIP) episodes
source_repo("code/algorithm/HIP_algorithm_functions.R")
initial_pregnant_cohort_df <- initial_pregnant_cohort(
  procedure_occurrence_tbl, measurement_tbl, observation_tbl,
  condition_occurrence_tbl, person_tbl, HIP_concepts) |> aou_compute()

final_abortion_visits_df   <- final_visits(initial_pregnant_cohort_df, Matcho_outcome_limits, c("AB", "SA")) |> aou_compute()
final_delivery_visits_df   <- final_visits(initial_pregnant_cohort_df, Matcho_outcome_limits, "DELIV") |> aou_compute()
final_ectopic_visits_df    <- final_visits(initial_pregnant_cohort_df, Matcho_outcome_limits, "ECT") |> aou_compute()
final_stillbirth_visits_df <- final_visits(initial_pregnant_cohort_df, Matcho_outcome_limits, "SB") |> aou_compute()
final_livebirth_visits_df  <- final_visits(initial_pregnant_cohort_df, Matcho_outcome_limits, "LB") |> aou_compute()

add_stillbirth_df <- add_stillbirth(final_stillbirth_visits_df, final_livebirth_visits_df, Matcho_outcome_limits)
add_ectopic_df    <- add_ectopic(add_stillbirth_df, Matcho_outcome_limits, final_ectopic_visits_df)
add_abortion_df   <- add_abortion(add_ectopic_df, Matcho_outcome_limits, final_abortion_visits_df)
add_delivery_df   <- add_delivery(add_abortion_df, Matcho_outcome_limits, final_delivery_visits_df)
calculate_start_df <- calculate_start(add_delivery_df, Matcho_term_durations) |> aou_compute()

gestation_visits_df     <- gestation_visits(initial_pregnant_cohort_df)
gestation_episodes_df   <- gestation_episodes(gestation_visits_df)
get_min_max_gestation_df <- get_min_max_gestation(gestation_episodes_df)
add_gestation_df  <- add_gestation(calculate_start_df, get_min_max_gestation_df)
clean_episodes_df <- clean_episodes(add_gestation_df)
remove_overlaps_df <- remove_overlaps(clean_episodes_df)
final_episodes_df <- final_episodes(remove_overlaps_df)
HIP_episodes_df   <- final_episodes_with_length(final_episodes_df, gestation_visits_df) |> aou_compute()

# gestation-progression (PPS) episodes
source_repo("code/algorithm/PPS_algorithm_functions.R")
input_GT_concepts_df <- input_GT_concepts(condition_occurrence_tbl, procedure_occurrence_tbl,
  observation_tbl, measurement_tbl, visit_occurrence_tbl, PPS_concepts)
get_PPS_episodes_df <- get_PPS_episodes(input_GT_concepts_df, PPS_concepts, person_tbl)
PPS_episodes_df     <- get_episode_max_min_dates(get_PPS_episodes_df)

# merge HIP + PPS
source_repo("code/algorithm/Merge_HIPPS_episodes.R")
outcomes_per_episode_df        <- outcomes_per_episode(PPS_episodes_df, get_PPS_episodes_df, initial_pregnant_cohort_df)
PPS_episodes_with_outcomes_df  <- add_outcomes(outcomes_per_episode_df, PPS_episodes_df)
HIP_episodes_local_df          <- collect(HIP_episodes_df)
final_merged_episodes_df       <- final_merged_episodes(HIP_episodes_local_df, PPS_episodes_with_outcomes_df)
final_merged_no_dup_df         <- final_merged_episodes_no_duplicates(final_merged_episodes_df)
final_merged_episode_detailed_df <- final_merged_episode_detailed(final_merged_no_dup_df)

# estimated start date (ESD) metadata
source_repo("code/algorithm/ESD_algorithm_functions.R")
get_timing_concepts_df <- get_timing_concepts(concept_tbl, condition_occurrence_tbl, observation_tbl,
  measurement_tbl, procedure_occurrence_tbl, final_merged_episode_detailed_df, PPS_concepts)
episodes_with_gestational_timing_info_df <- episodes_with_gestational_timing_info(get_timing_concepts_df)
merged_episodes_with_metadata_df <- merged_episodes_with_metadata(
  episodes_with_gestational_timing_info_df, final_merged_episode_detailed_df, Matcho_term_durations)

nrow(merged_episodes_with_metadata_df)  # synthetic pregnancy episodes

# (3) on the Workbench you would aou_workspace_to_bucket() here; locally, just
#     save to disk:
# write_rds(merged_episodes_with_metadata_df, "merged_episodes_with_metadata_df.rds")

mock_aou_disconnect(con)
```

## What this exercises

Running this end-to-end touches most of what a complex All of Us
analysis needs, all of which works locally:
[`tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) +
dplyr/dbplyr,
[`aou_create_temp_table()`](https://rdrr.io/pkg/allofus/man/aou_create_temp_table.html),
[`aou_compute()`](https://rdrr.io/pkg/allofus/man/aou_compute.html), and
BigQuery idioms such as the three-argument
`date_diff(a, b, sql("day"))`. The only Workbench-specific piece is the
final bucket upload, which has no local equivalent.
