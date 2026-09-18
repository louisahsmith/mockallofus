# Internal helpers: schema parsing, type inference, row assembly, concept pools.

#' Parse the comma-separated column list for a table from `aou_table_info`
#' @return a data.frame with `col` (sanitized column name) and `type` (DuckDB type)
#' @keywords internal
#' @noRd
table_spec <- function(table_name) {
  cols_raw <- aou_table_info$columns[aou_table_info$table_name == table_name]
  if (length(cols_raw) == 0) {
    cli::cli_abort("Table {.val {table_name}} not found in the schema dictionary.")
  }
  cols <- strsplit(cols_raw, ",")[[1]]
  cols <- gsub("\\s+", "", cols) # fixes upstream typos like "sex_at_ birth"
  cols <- cols[nzchar(cols)]
  cols <- cols[!duplicated(cols)] # some dictionary entries repeat columns
  tibble::tibble(col = cols, type = vapply(cols, duckdb_type, character(1)))
}

#' Infer a DuckDB column type from an OMOP/AoU column name
#' @keywords internal
#' @noRd
duckdb_type <- function(col) {
  col <- tolower(col)
  # explicit overrides where the name-based heuristic would be wrong:
  # OMOP vocabulary keys end in "_id" but are strings, not numeric surrogate keys
  if (col %in% c("src_id", "domain_id", "vocabulary_id", "concept_class_id", "relationship_id")) {
    return("VARCHAR")
  }
  if (col %in% c("year_of_birth", "month_of_birth", "day_of_birth")) return("INTEGER")
  if (col %in% c("age_at_consent", "age_at_cdr", "survey_version_number", "refills", "days_supply", "quantity")) return("INTEGER")
  if (col %in% c("value_as_number", "range_low", "range_high")) return("DOUBLE")
  # cb_search_person$dob is a DATE in the CDR but the name matches no pattern.
  # Left as VARCHAR it forced an as.Date() cast that is a no-op on BigQuery,
  # so local code needed a line the Workbench did not.
  if (col == "dob") return("DATE")
  if (grepl("_datetime$", col)) return("TIMESTAMP")
  if (grepl("_date$", col)) return("DATE")
  if (grepl("^has_|^is_", col)) return("INTEGER") # boolean-ish flags; vignette uses == 1
  if (grepl("(^|_)id$", col)) return("BIGINT") # *_id and *_concept_id
  "VARCHAR"
}

#' Assemble a full-width data frame for a table from partial generated columns
#'
#' Builds a data frame containing every column in `spec`, in order, filling any
#' column not present in `values` with a correctly-typed `NA`. This lets the
#' generators populate only the columns they care about while still matching the
#' table's full schema for `DBI::dbAppendTable()`.
#' @keywords internal
#' @noRd
assemble_rows <- function(spec, n, values = list()) {
  na_for <- function(type) {
    switch(type,
      VARCHAR = NA_character_,
      DATE = as.Date(NA),
      TIMESTAMP = as.POSIXct(NA),
      DOUBLE = NA_real_,
      BIGINT = NA_integer_,
      INTEGER = NA_integer_,
      NA
    )
  }
  out <- purrr::map2(spec$col, spec$type, function(col, type) {
    if (!is.null(values[[col]])) values[[col]] else rep(na_for(type), n)
  })
  names(out) <- spec$col
  tibble::as_tibble(out)
}

# ---- Concept pools -----------------------------------------------------------
# Fully synthetic concept_ids/names. The clinical ids match those used in the
# allofus vignettes so the documented workflows return non-empty results; none
# of this reflects real All of Us data.

#' Clinical + survey concepts referenced by the allofus vignettes
#' @keywords internal
#' @noRd
vignette_concepts <- function() {
  tibble::tribble(
    ~concept_id, ~concept_name,                                   ~domain_id,     ~vocabulary_id, ~concept_class_id,
    201826L,     "Type 2 diabetes mellitus",                      "Condition",    "SNOMED",       "Clinical Finding",
    4193704L,    "Type 2 diabetes mellitus without complication", "Condition",    "SNOMED",       "Clinical Finding",
    40164929L,   "metformin 500 MG Oral Tablet",                  "Drug",         "RxNorm",       "Clinical Drug",
    40164897L,   "metformin hydrochloride 850 MG Oral Tablet",    "Drug",         "RxNorm",       "Clinical Drug",
    3004410L,    "Hemoglobin A1c/Hemoglobin.total in Blood",      "Measurement",  "LOINC",        "Lab Test",
    3005673L,    "Hemoglobin A1c measurement",                    "Measurement",  "LOINC",        "Lab Test"
  )
}

#' Domain event concept pools (clinical), keyed by domain
#' @keywords internal
#' @noRd
domain_concept_pool <- function(domain) {
  vc <- vignette_concepts()
  base <- switch(domain,
    condition = c(stats::setNames(vc$concept_name[vc$domain_id == "Condition"], vc$concept_id[vc$domain_id == "Condition"]),
                  c("320128" = "Essential hypertension", "4329847" = "Myocardial infarction",
                    "317009" = "Asthma", "255848" = "Pneumonia", "440383" = "Depressive disorder")),
    drug = c(stats::setNames(vc$concept_name[vc$domain_id == "Drug"], vc$concept_id[vc$domain_id == "Drug"]),
             c("1308216" = "lisinopril 10 MG Oral Tablet", "1545958" = "atorvastatin 20 MG Oral Tablet",
               "19019066" = "ibuprofen 200 MG Oral Tablet")),
    measurement = c(stats::setNames(vc$concept_name[vc$domain_id == "Measurement"], vc$concept_id[vc$domain_id == "Measurement"]),
                    c("3000963" = "Hemoglobin", "3023314" = "Hematocrit", "3013682" = "Urea nitrogen",
                      "3004249" = "Systolic blood pressure", "3012888" = "Diastolic blood pressure")),
    procedure = c("4163872" = "Plain chest X-ray", "2211359" = "Office visit procedure",
                  "4143984" = "Electrocardiographic procedure"),
    device = c("4206863" = "Wheelchair", "4074815" = "Walking aid"),
    visit = c("9202" = "Outpatient Visit", "9201" = "Inpatient Visit", "9203" = "Emergency Room Visit"),
    stop("unknown domain")
  )
  tibble::tibble(concept_id = as.integer(names(base)), concept_name = unname(base))
}

#' Demographic vocabulary concepts used in `person`
#' @keywords internal
#' @noRd
demographic_concepts <- function() {
  tibble::tribble(
    ~concept_id, ~concept_name,             ~domain_id,
    45878463L,   "Female",                  "Gender",
    45880669L,   "Male",                    "Gender",
    8516L,       "Black or African American","Race",
    8527L,       "White",                   "Race",
    8515L,       "Asian",                   "Race",
    38003563L,   "Hispanic or Latino",      "Ethnicity",
    38003564L,   "Not Hispanic or Latino",  "Ethnicity"
  )
}

#' Sample `n` values from `x` with replacement, safe for length-1 `x`
#'
#' Base `sample()` treats a single positive number as `sample.int()`, which is a
#' frequent source of bugs when a pool happens to have one element. This always
#' resamples the elements of `x`.
#' @keywords internal
#' @noRd
resample <- function(x, n) {
  x[sample.int(length(x), n, replace = TRUE)]
}

#' Parse a codebook `choices` string ("Code, Label | Code2, Label2") into codes
#' @keywords internal
#' @noRd
parse_choice_codes <- function(choices) {
  if (is.na(choices) || !nzchar(choices)) return(character(0))
  pieces <- strsplit(choices, "\\|")[[1]]
  codes <- vapply(pieces, function(p) trimws(strsplit(p, ",")[[1]][1]), character(1))
  unname(codes[nzchar(codes)])
}

# Source concept ids for synthetic clinical rows.
#
# All of Us records both a standard `*_concept_id` and the contributing site's
# own `*_source_concept_id`, and several important properties of the real CDR
# are visible only in the source column -- most notably the controlled tier's
# row suppression, which is keyed on source concepts rather than standard ones.
# Leaving the column NULL made any such analysis silently return nothing
# locally while working on the Workbench.
#
# The synthetic mapping is deliberately simple: most rows carry the standard
# concept as their source, and a minority carry 0, All of Us's marker for a
# site code that did not map. That is enough to exercise code that groups or
# filters on the source column; it is not a model of real source vocabularies.
mock_source_concepts <- function(concept_id, unmapped_frac = 0.12) {
  ifelse(stats::runif(length(concept_id)) < unmapped_frac, 0L, as.integer(concept_id))
}

mock_source_values <- function(source_concept_id) {
  ifelse(source_concept_id == 0L, NA_character_, paste0("SRC", source_concept_id))
}

# Add source columns to a values list, when the table has them.
add_source_columns <- function(vals, spec, concept_col, concept_id,
                               unmapped_frac = 0.12) {
  src_concept_col <- sub("_concept_id$", "_source_concept_id", concept_col)
  src_value_col <- sub("_concept_id$", "_source_value", concept_col)
  if (src_concept_col %in% spec$col) {
    src <- mock_source_concepts(concept_id, unmapped_frac)
    vals[[src_concept_col]] <- src
    if (src_value_col %in% spec$col) vals[[src_value_col]] <- mock_source_values(src)
  }
  vals
}
