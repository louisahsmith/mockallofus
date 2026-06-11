# Low-level building blocks for putting custom synthetic data into the mock
# database. These are the reusable primitives that the higher-level seeding
# functions (mock_seed_concept_set / mock_seed_survey) and study-specific
# seeding code (see the vignettes) are built on.

# domain -> table/column mapping for the OMOP clinical-event tables
domain_map <- function() {
  list(
    condition   = list(table = "condition_occurrence",   id = "condition_occurrence_id", concept = "condition_concept_id",   start = "condition_start_date",       end = "condition_end_date"),
    drug        = list(table = "drug_exposure",           id = "drug_exposure_id",        concept = "drug_concept_id",        start = "drug_exposure_start_date",    end = "drug_exposure_end_date"),
    measurement = list(table = "measurement",             id = "measurement_id",          concept = "measurement_concept_id", start = "measurement_date",           end = NULL),
    observation = list(table = "observation",             id = "observation_id",          concept = "observation_concept_id", start = "observation_date",           end = NULL),
    procedure   = list(table = "procedure_occurrence",    id = "procedure_occurrence_id", concept = "procedure_concept_id",   start = "procedure_date",             end = NULL),
    device      = list(table = "device_exposure",         id = "device_exposure_id",      concept = "device_concept_id",      start = "device_exposure_start_date", end = "device_exposure_end_date"),
    visit       = list(table = "visit_occurrence",        id = "visit_occurrence_id",     concept = "visit_concept_id",       start = "visit_start_date",           end = "visit_end_date")
  )
}

# next available surrogate-key value for a table (so generated ids don't clash)
next_id <- function(con, table, id_col) {
  as.numeric(DBI::dbGetQuery(con, sprintf("SELECT COALESCE(MAX(%s), 0) AS m FROM %s", id_col, table))$m)
}

#' Participant ids in the mock database
#'
#' @param con A connection from [mock_aou_connect()].
#' @return An integer vector of `person_id`s.
#' @export
mock_person_ids <- function(con) {
  as.integer(DBI::dbGetQuery(con, "SELECT person_id FROM person ORDER BY person_id")$person_id)
}

#' Add concept definitions to the mock database
#'
#' Inserts rows into the `concept` table for any `concept_id`s not already
#' present. Use this so that concept-name lookups (e.g. searching `concept_name`)
#' and joins on `concept_id` find your study's concepts. Concepts already present
#' are skipped, so it is safe to call repeatedly.
#'
#' @param con A connection from [mock_aou_connect()].
#' @param concept_id Integer vector of concept ids.
#' @param concept_name Optional character vector of names (parallel to
#'   `concept_id`). If `NULL`, generic placeholder names are used. Supply real
#'   names when your code searches `concept_name` (e.g. by `str_detect()`).
#' @param domain_id Value for the `domain_id` column (e.g. "Condition", "Drug").
#' @return The number of concept rows inserted, invisibly.
#' @export
#' @examples
#' \dontrun{
#' con <- mock_aou_connect()
#' mock_add_concepts(con, c(201826, 4193704),
#'                   c("Type 2 diabetes mellitus", "T2DM without complication"),
#'                   domain_id = "Condition")
#' }
mock_add_concepts <- function(con, concept_id, concept_name = NULL, domain_id = "Observation") {
  df <- tibble::tibble(
    concept_id = as.integer(concept_id),
    concept_name = if (is.null(concept_name)) paste("Mock concept", concept_id) else as.character(concept_name)
  )
  df <- df[!is.na(df$concept_id) & !duplicated(df$concept_id), ]
  existing <- as.integer(DBI::dbGetQuery(con, "SELECT concept_id FROM concept")$concept_id)
  df <- df[!(df$concept_id %in% existing), ]
  if (nrow(df) == 0) return(invisible(0L))
  vals <- list(
    concept_id = df$concept_id, concept_name = df$concept_name, domain_id = domain_id,
    vocabulary_id = "Mock", concept_class_id = "Mock", standard_concept = "S",
    concept_code = paste0("MOCK_", df$concept_id),
    valid_start_date = as.Date("1970-01-01"), valid_end_date = as.Date("2099-12-31")
  )
  DBI::dbAppendTable(con, "concept", assemble_rows(table_spec("concept"), nrow(df), vals))
  invisible(nrow(df))
}

#' Add clinical-event occurrences to the mock database
#'
#' Inserts rows into one of the OMOP clinical-event domain tables, generating
#' surrogate keys automatically and writing the matching `_ext` row (which All of
#' Us uses to record data source: EHR vs survey/physical-measurement). This is
#' the primitive for putting custom events into the mock database — e.g. giving a
#' specific set of participants a specific concept on specific dates.
#'
#' `person_id`, `concept_id`, and `date` are treated row-wise (recycled to a
#' common length), so one call inserts one occurrence per `person_id` element.
#'
#' @param con A connection from [mock_aou_connect()].
#' @param domain One of "condition", "drug", "measurement", "observation",
#'   "procedure", "device", "visit".
#' @param person_id Integer vector of participant ids (one per occurrence).
#' @param concept_id Integer concept id(s); recycled to `length(person_id)`.
#' @param date Event date(s) (Date or coercible); recycled to `length(person_id)`.
#'   Used for the domain's start date (and, unless `end_date` is given, its end
#'   date too).
#' @param end_date Optional end date(s) for domains that have an end column
#'   (e.g. `drug_exposure`, `condition_occurrence`, `visit_occurrence`). Recycled
#'   to `length(person_id)`. Defaults to `date` (a single-day event). Use this to
#'   give exposures a realistic duration.
#' @param value Optional numeric value(s) written to `value_as_number` where the
#'   table has that column (e.g. measurements, observations).
#' @param source `"ehr"` tags the `_ext` row as EHR-sourced (`src_id` like
#'   "EHR site 105", which EHR-based functions such as
#'   [allofus::aou_observation_period()] look for); `"ppi"` tags it as
#'   survey/physical-measurement ("PPI/PM").
#' @return The generated surrogate ids, invisibly.
#' @export
#' @examples
#' \dontrun{
#' con <- mock_aou_connect()
#' ids <- mock_person_ids(con)[1:50]
#' mock_add_concepts(con, 201826, "Type 2 diabetes mellitus", domain_id = "Condition")
#' mock_add_occurrences(con, "condition", person_id = ids, concept_id = 201826,
#'                      date = as.Date("2021-03-15"))
#' }
mock_add_occurrences <- function(con, domain, person_id, concept_id, date,
                                 end_date = NULL, value = NULL,
                                 source = c("ehr", "ppi")) {
  source <- match.arg(source)
  dm <- domain_map()
  if (!domain %in% names(dm)) {
    cli::cli_abort("{.arg domain} must be one of {.val {names(dm)}}.")
  }
  cn <- dm[[domain]]
  n <- length(person_id)
  if (n == 0) return(invisible(integer(0)))
  concept_id <- rep_len(as.integer(concept_id), n)
  date <- rep_len(as.Date(date), n)
  end <- if (is.null(end_date)) date else rep_len(as.Date(end_date), n)
  ids <- next_id(con, cn$table, cn$id) + seq_len(n)

  spec <- table_spec(cn$table)
  vals <- list()
  vals[["person_id"]] <- as.integer(person_id)
  vals[[cn$id]] <- ids
  vals[[cn$concept]] <- concept_id
  vals[[cn$start]] <- date
  if (!is.null(cn$end)) vals[[cn$end]] <- end
  if (!is.null(value) && "value_as_number" %in% spec$col) {
    vals[["value_as_number"]] <- rep_len(as.numeric(value), n)
  }
  DBI::dbAppendTable(con, cn$table, assemble_rows(spec, n, vals))

  ext <- paste0(cn$table, "_ext")
  src <- if (source == "ehr") paste("EHR site", sample(100:120, n, replace = TRUE)) else rep("PPI/PM", n)
  DBI::dbAppendTable(con, ext, assemble_rows(table_spec(ext), n, stats::setNames(list(ids, src), c(cn$id, "src_id"))))
  invisible(ids)
}
