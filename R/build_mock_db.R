#' Build a local mock All of Us DuckDB database
#'
#' Creates a DuckDB database file whose tables and columns mirror the All of Us
#' Curated Data Repository (OMOP CDM core tables plus All of Us extension and
#' cohort-builder tables), populated with fully synthetic, randomly generated
#' data. The data does **not** reflect real All of Us data and results are not
#' meant to be realistic; the purpose is to let `allofus` analysis code run and
#' be developed locally.
#'
#' All tables in the All of Us data dictionary are created (so table references
#' resolve); a core subset is populated with data:
#' `person`, `concept`, the clinical domain tables and their `_ext` tables,
#' survey rows in `observation`, `observation_period`, `cb_search_person`,
#' `ds_survey`, and `survey_conduct`. The clinical concept ids used in the
#' `allofus` vignettes are included so the documented workflows return data.
#'
#' Use [mock_seed_concept_set()] / [mock_seed_survey()] afterwards to guarantee
#' coverage of the specific concepts your own study queries.
#'
#' @param path File path for the DuckDB database. Defaults to a cached location
#'   under [tools::R_user_dir()].
#' @param n_persons Number of synthetic participants to generate. Default 2000.
#' @param seed Random seed for reproducible generation. Default 20240101.
#' @param survey_questions Optional integer vector of survey question concept
#'   ids (from `allofus::aou_codebook`) to populate in `observation`. Defaults
#'   to a sample that includes the vignette questions (gender `1585838`,
#'   birthplace `1586135`).
#' @param overwrite Overwrite an existing database file. Default `FALSE`
#'   (an existing file at `path` is left untouched and its path returned).
#' @param quiet Suppress progress messages.
#'
#' @return The `path` to the built database, invisibly.
#' @export
build_mock_db <- function(path = default_mock_db_path(),
                          n_persons = 2000L,
                          seed = 20240101L,
                          survey_questions = NULL,
                          overwrite = FALSE,
                          quiet = FALSE) {
  if (file.exists(path) && !overwrite) {
    if (!quiet) cli::cli_inform(c("i" = "Using existing mock database at {.path {path}}."))
    return(invisible(path))
  }
  if (file.exists(path) && overwrite) unlink(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  withr::local_seed(seed)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  if (!quiet) cli::cli_inform(c(">" = "Creating {nrow(aou_table_info)} tables..."))
  create_all_tables(con)

  if (!quiet) cli::cli_inform(c(">" = "Generating {n_persons} synthetic participants..."))
  person_ids <- 1000000L + seq_len(n_persons)
  populate_person(con, person_ids)
  populate_concept(con)

  # clinical domains (+ matching _ext src_id rows)
  populate_domain(con, "condition_occurrence", "condition_occurrence_id", "condition_concept_id",
                  "condition_start_date", "condition_end_date", person_ids,
                  domain_concept_pool("condition"), max_events = 6L, id_start = 10e6)
  populate_domain(con, "drug_exposure", "drug_exposure_id", "drug_concept_id",
                  "drug_exposure_start_date", "drug_exposure_end_date", person_ids,
                  domain_concept_pool("drug"), max_events = 8L, id_start = 20e6)
  populate_domain(con, "procedure_occurrence", "procedure_occurrence_id", "procedure_concept_id",
                  "procedure_date", NULL, person_ids,
                  domain_concept_pool("procedure"), max_events = 4L, id_start = 30e6)
  populate_domain(con, "device_exposure", "device_exposure_id", "device_concept_id",
                  "device_exposure_start_date", "device_exposure_end_date", person_ids,
                  domain_concept_pool("device"), max_events = 2L, id_start = 40e6)
  populate_domain(con, "visit_occurrence", "visit_occurrence_id", "visit_concept_id",
                  "visit_start_date", "visit_end_date", person_ids,
                  domain_concept_pool("visit"), max_events = 10L, id_start = 50e6)
  populate_measurement(con, person_ids, id_start = 60e6)
  populate_clinical_observation(con, person_ids, id_start = 70e6)

  # survey data (observation rows + ds_survey + survey_conduct)
  if (!quiet) cli::cli_inform(c(">" = "Generating survey responses..."))
  if (is.null(survey_questions)) survey_questions <- default_survey_questions()
  populate_survey_observations(con, person_ids, survey_questions, id_start = 80e6)
  populate_ds_survey(con, person_ids)
  populate_survey_conduct(con, person_ids)

  populate_observation_period(con, person_ids)
  populate_cb_search_person(con, person_ids)

  if (!quiet) cli::cli_inform(c("v" = "Mock database built at {.path {path}}."))
  invisible(path)
}

#' Default location for the mock database
#'
#' By default the mock database lives in the current **project directory**, as
#' `mock_aou.duckdb`, so each project gets its own database rather than sharing a
#' single global file. The project directory is found by looking upward from the
#' working directory for an RStudio project (`.Rproj`), a git repository, a
#' `.here` file, or an R package `DESCRIPTION`; if none is found, the working
#' directory is used.
#'
#' Override the location by setting `options(mockallofus.path = "...")` (a full
#' path to the `.duckdb` file), or pass `path` to [mock_aou_connect()] /
#' [build_mock_db()] directly.
#'
#' The database file is generated data --- add `mock_aou.duckdb` to your
#' `.gitignore`.
#'
#' @return A path to the `.duckdb` file.
#' @export
default_mock_db_path <- function() {
  getOption("mockallofus.path", file.path(find_project_dir(), "mock_aou.duckdb"))
}

# Walk up from `start` to find the project root, by common project markers.
# Returns `start` if none are found.
find_project_dir <- function(start = getwd()) {
  dir <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    has_marker <- length(list.files(dir, pattern = "\\.Rproj$")) > 0 ||
      any(file.exists(file.path(dir, c(".here", ".git", "DESCRIPTION"))))
    if (has_marker) return(dir)
    parent <- dirname(dir)
    if (identical(parent, dir)) break # reached the filesystem root
    dir <- parent
  }
  normalizePath(start, winslash = "/", mustWork = FALSE)
}

# ---- table creation ----------------------------------------------------------

create_all_tables <- function(con) {
  for (tname in aou_table_info$table_name) {
    spec <- table_spec(tname)
    cols_sql <- paste(sprintf('"%s" %s', spec$col, spec$type), collapse = ",\n  ")
    DBI::dbExecute(con, sprintf('CREATE TABLE "%s" (\n  %s\n)', tname, cols_sql))
  }
}

# ---- populators --------------------------------------------------------------

populate_person <- function(con, person_ids) {
  n <- length(person_ids)
  spec <- table_spec("person")
  gender <- sample(c(45878463L, 45880669L), n, replace = TRUE)
  # month_of_birth, day_of_birth and birth_datetime are deliberately left NULL:
  # All of Us suppresses all three in the controlled tier (see the "Field
  # (Column) Suppressions" tab of the data dictionary). Populating them here
  # would let code that derives an age from them work locally and return
  # nothing on the Workbench. Birth date comes from cb_search_person$dob.
  vals <- list(
    person_id = person_ids,
    year_of_birth = sample(1930:2005, n, replace = TRUE),
    gender_concept_id = gender,
    sex_at_birth_concept_id = gender,
    race_concept_id = sample(c(8516L, 8527L, 8515L), n, replace = TRUE),
    ethnicity_concept_id = sample(c(38003563L, 38003564L), n, replace = TRUE),
    person_source_value = paste0("P", person_ids)
  )
  DBI::dbAppendTable(con, "person", assemble_rows(spec, n, vals))
}

populate_concept <- function(con) {
  spec <- table_spec("concept")
  # gather every concept id we reference, plus filler
  clinical <- dplyr::bind_rows(lapply(c("condition", "drug", "measurement", "procedure", "device", "visit"),
                                      domain_concept_pool))
  clinical$domain_id <- NA_character_
  demo <- demographic_concepts()
  vc <- vignette_concepts()[c("concept_id", "concept_name", "domain_id")]
  # survey question concepts from the codebook
  cb <- tibble::tibble(
    concept_id = as.integer(aou_codebook$concept_id),
    concept_name = aou_codebook$concept_name,
    domain_id = "Observation"
  )
  # skip / special PPI concepts
  skips <- tibble::tibble(
    concept_id = c(903096L, 903079L, 903087L, 903076L),
    concept_name = c("PMI: Skip", "PMI: Prefer Not To Answer", "PMI: Dont Know", "PPI"),
    domain_id = "Observation"
  )
  concepts <- dplyr::bind_rows(
    vc, clinical[c("concept_id", "concept_name")], demo[c("concept_id", "concept_name", "domain_id")],
    cb, skips
  )
  concepts <- concepts[!duplicated(concepts$concept_id) & !is.na(concepts$concept_id), ]
  n <- nrow(concepts)
  vals <- list(
    concept_id = as.integer(concepts$concept_id),
    concept_name = concepts$concept_name,
    domain_id = ifelse(is.na(concepts$domain_id), "Observation", concepts$domain_id),
    vocabulary_id = "Mock",
    concept_class_id = "Mock",
    standard_concept = "S",
    concept_code = paste0("MOCK_", concepts$concept_id),
    valid_start_date = as.Date("1970-01-01"),
    valid_end_date = as.Date("2099-12-31")
  )
  DBI::dbAppendTable(con, "concept", assemble_rows(spec, n, vals))
}

# generic clinical-domain generator (main table + _ext src_id)
populate_domain <- function(con, table, id_col, concept_col, start_col, end_col,
                            person_ids, pool, max_events, id_start, ehr_frac = 0.9,
                            extra = list()) {
  n_ev <- sample(0:max_events, length(person_ids), replace = TRUE)
  pid <- rep(person_ids, n_ev)
  N <- length(pid)
  if (N == 0) return(invisible(0L))
  ids <- as.integer(id_start) + seq_len(N)
  day0 <- as.Date("2008-01-01")
  start <- day0 + sample.int(as.integer(as.Date("2023-01-01") - day0), N, replace = TRUE)

  spec <- table_spec(table)
  cids <- resample(pool$concept_id, N)
  vals <- c(list(), extra)
  vals[["person_id"]] <- pid
  vals[[id_col]] <- ids
  vals[[concept_col]] <- cids
  vals[[start_col]] <- start
  if (!is.null(end_col)) vals[[end_col]] <- start + sample(0:30, N, replace = TRUE)
  vals <- add_source_columns(vals, spec, concept_col, cids)
  DBI::dbAppendTable(con, table, assemble_rows(spec, N, vals))

  ext <- paste0(table, "_ext")
  spec_ext <- table_spec(ext)
  src <- ifelse(stats::runif(N) < ehr_frac,
                paste("EHR site", sample(100:120, N, replace = TRUE)), "PPI/PM")
  ext_vals <- list(); ext_vals[[id_col]] <- ids; ext_vals[["src_id"]] <- src
  DBI::dbAppendTable(con, ext, assemble_rows(spec_ext, N, ext_vals))
  invisible(N)
}

populate_measurement <- function(con, person_ids, id_start) {
  pool <- domain_concept_pool("measurement")
  n_ev <- sample(0:10, length(person_ids), replace = TRUE)
  pid <- rep(person_ids, n_ev)
  N <- length(pid)
  if (N == 0) return(invisible(0L))
  ids <- as.integer(id_start) + seq_len(N)
  cids <- resample(pool$concept_id, N)
  day0 <- as.Date("2008-01-01")
  mdate <- day0 + sample.int(as.integer(as.Date("2023-01-01") - day0), N, replace = TRUE)
  # A1c (3004410 / 3005673) get plausible-ish values; others generic
  is_a1c <- cids %in% c(3004410L, 3005673L)
  value <- ifelse(is_a1c, round(stats::runif(N, 4.5, 11), 1), round(stats::runif(N, 0, 200), 1))
  spec <- table_spec("measurement")
  vals <- list(person_id = pid, measurement_id = ids, measurement_concept_id = cids,
               measurement_date = mdate, value_as_number = value, unit_concept_id = 8554L)
  vals <- add_source_columns(vals, spec, "measurement_concept_id", cids)
  DBI::dbAppendTable(con, "measurement", assemble_rows(spec, N, vals))
  spec_ext <- table_spec("measurement_ext")
  src <- ifelse(stats::runif(N) < 0.9, paste("EHR site", sample(100:120, N, replace = TRUE)), "PPI/PM")
  DBI::dbAppendTable(con, "measurement_ext",
                     assemble_rows(spec_ext, N, list(measurement_id = ids, src_id = src)))
  invisible(N)
}

populate_clinical_observation <- function(con, person_ids, id_start) {
  # a small number of non-survey clinical observations with EHR src_id
  n_ev <- sample(0:3, length(person_ids), replace = TRUE)
  pid <- rep(person_ids, n_ev)
  N <- length(pid)
  if (N == 0) return(invisible(0L))
  ids <- as.integer(id_start) + seq_len(N)
  day0 <- as.Date("2008-01-01")
  odate <- day0 + sample.int(as.integer(as.Date("2023-01-01") - day0), N, replace = TRUE)
  spec <- table_spec("observation")
  ocids <- sample(c(4275495L, 4058243L), N, replace = TRUE)
  vals <- list(person_id = pid, observation_id = ids,
               observation_concept_id = ocids,
               observation_date = odate)
  vals <- add_source_columns(vals, spec, "observation_concept_id", ocids)
  DBI::dbAppendTable(con, "observation", assemble_rows(spec, N, vals))
  spec_ext <- table_spec("observation_ext")
  src <- paste("EHR site", sample(100:120, N, replace = TRUE))
  DBI::dbAppendTable(con, "observation_ext",
                     assemble_rows(spec_ext, N, list(observation_id = ids, src_id = src)))
  invisible(N)
}

default_survey_questions <- function() {
  cb <- aou_codebook[aou_codebook$field_type %in% c("radio", "checkbox") & !is.na(aou_codebook$choices), ]
  ids <- unique(as.integer(cb$concept_id))
  ids <- utils::head(ids, 25L)
  union(c(1585838L, 1586135L), ids) # ensure vignette questions present
}

populate_survey_observations <- function(con, person_ids, survey_questions, id_start,
                                         prevalence = 0.8) {
  spec <- table_spec("observation")
  spec_ext <- table_spec("observation_ext")
  cb <- aou_codebook
  rows <- list()
  next_id <- as.integer(id_start)
  day0 <- as.Date("2017-05-01")
  for (q in survey_questions) {
    cb_row <- cb[as.integer(cb$concept_id) == q, ]
    if (nrow(cb_row) == 0) next
    code <- cb_row$concept_code[1]
    answers <- parse_choice_codes(cb_row$choices[1])
    responders <- person_ids[stats::runif(length(person_ids)) < prevalence]
    if (length(responders) == 0) next
    if (length(answers) == 0) answers <- c("PMI_Skip")
    # checkbox questions may have multiple selections per person
    multi <- identical(cb_row$field_type[1], "checkbox")
    ans <- if (multi) {
      purrr::map(responders, ~ answers[sample.int(length(answers), sample.int(min(2, length(answers)), 1))])
    } else {
      as.list(resample(answers, length(responders)))
    }
    pid <- rep(responders, lengths(ans))
    val <- unlist(ans)
    N <- length(pid)
    ids <- next_id + seq_len(N)
    next_id <- next_id + N
    odate <- day0 + sample.int(2000L, N, replace = TRUE)
    vals <- list(
      person_id = pid, observation_id = ids,
      observation_concept_id = rep(q, N),
      observation_source_concept_id = rep(q, N),
      observation_source_value = rep(code, N),
      observation_date = odate,
      value_source_value = val,
      value_source_concept_id = 0L
    )
    rows[[length(rows) + 1]] <- list(
      main = assemble_rows(spec, N, vals),
      ext = assemble_rows(spec_ext, N, list(observation_id = ids, src_id = rep("PPI/PM", N)))
    )
  }
  if (length(rows) == 0) return(invisible(0L))
  DBI::dbAppendTable(con, "observation", dplyr::bind_rows(purrr::map(rows, "main")))
  DBI::dbAppendTable(con, "observation_ext", dplyr::bind_rows(purrr::map(rows, "ext")))
  invisible(sum(purrr::map_int(rows, ~ nrow(.x$main))))
}

populate_ds_survey <- function(con, person_ids) {
  spec <- table_spec("ds_survey")
  n <- length(person_ids)
  base <- as.POSIXct("2017-05-01", tz = "UTC")
  dt <- base + sample.int(2000L, n, replace = TRUE) * 86400
  vals <- list(person_id = person_ids, survey_datetime = dt,
               survey = "The Basics", question = "Mock survey question",
               answer = "Mock answer")
  DBI::dbAppendTable(con, "ds_survey", assemble_rows(spec, n, vals))
}

populate_survey_conduct <- function(con, person_ids) {
  spec <- table_spec("survey_conduct")
  n <- length(person_ids)
  ids <- 90000000L + seq_len(n)
  sdate <- as.Date("2017-05-01") + sample.int(2000L, n, replace = TRUE)
  vals <- list(survey_conduct_id = ids, person_id = person_ids,
               survey_concept_id = 1333342L, survey_start_date = sdate,
               survey_source_value = "The Basics")
  DBI::dbAppendTable(con, "survey_conduct", assemble_rows(spec, n, vals))
}

populate_observation_period <- function(con, person_ids) {
  # derive a single period per person from their actual EHR span where available
  spec <- table_spec("observation_period")
  n <- length(person_ids)
  start <- as.Date("2008-01-01") + sample.int(2500L, n, replace = TRUE)
  end <- start + sample(365:5000, n, replace = TRUE)
  vals <- list(observation_period_id = seq_len(n),
               person_id = person_ids,
               observation_period_start_date = start,
               observation_period_end_date = end,
               period_type_concept_id = 44814724L)
  DBI::dbAppendTable(con, "observation_period", assemble_rows(spec, n, vals))
}

populate_cb_search_person <- function(con, person_ids) {
  spec <- table_spec("cb_search_person")
  n <- length(person_ids)

  # Read back the person table rather than re-drawing, so the two agree. Code
  # that filters cb_search_person and then joins person must not see one sex at
  # birth here and another there.
  ppl <- DBI::dbGetQuery(
    con, "SELECT person_id, year_of_birth, sex_at_birth_concept_id FROM person"
  )
  ppl <- ppl[match(person_ids, ppl$person_id), ]
  sex <- ifelse(ppl$sex_at_birth_concept_id == 45880669L, "Male", "Female")

  # `dob` is the only usable birth date in the controlled tier, since
  # person.birth_datetime is suppressed. All of Us generalizes it to the year
  # of birth, defaulting the rest to mid-year, so the mock does the same.
  dob <- as.Date(paste0(ppl$year_of_birth, "-06-15"))
  cdr_date <- as.Date("2023-07-01")

  vals <- list(
    person_id = person_ids,
    dob = dob,
    gender = sex,
    sex_at_birth = sex,
    race = sample(c("White", "Black or African American", "Asian"), n, replace = TRUE),
    ethnicity = sample(c("Hispanic or Latino", "Not Hispanic or Latino"), n, replace = TRUE),
    age_at_consent = sample(18:90, n, replace = TRUE),
    age_at_cdr = as.integer(floor(as.numeric(cdr_date - dob) / 365.25)),
    state_of_residence = sample(datasets::state.name, n, replace = TRUE),
    is_deceased = sample(c(0L, 1L), n, replace = TRUE, prob = c(0.97, 0.03)),
    has_ehr_data = sample(c(0L, 1L), n, replace = TRUE, prob = c(0.2, 0.8)),
    has_ppi_survey_data = sample(c(0L, 1L), n, replace = TRUE, prob = c(0.1, 0.9)),
    has_physical_measurement_data = sample(c(0L, 1L), n, replace = TRUE, prob = c(0.3, 0.7))
  )

  # the availability flags are all the same shape; fill whichever this CDR
  # version's dictionary actually lists
  flags <- grep("^has_(fitbit|whole_genome|array|lr_whole_genome|structural)",
                spec$col, value = TRUE)
  for (f in flags) {
    vals[[f]] <- sample(c(0L, 1L), n, replace = TRUE, prob = c(0.8, 0.2))
  }

  DBI::dbAppendTable(con, "cb_search_person", assemble_rows(spec, n, vals))
}
