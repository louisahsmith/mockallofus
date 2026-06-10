# Seeding API: guarantee that the concepts / survey questions a given study
# queries exist in the mock database, at a controllable prevalence, so
# eligibility filters and joins return non-empty (but partial) results. Seeded
# rows attach to participants already in `person`, preserving referential
# integrity, and generation is deterministic for a given `seed`.
#
# These build on the lower-level primitives in mock_add.R
# (mock_add_concepts(), mock_add_occurrences(), mock_person_ids()).

#' Seed a concept set into the mock database
#'
#' Guarantees that the given concepts exist (in `concept` and as occurrences in
#' the appropriate domain table, with matching EHR `_ext` rows) for a fraction
#' of participants. Use this so that [allofus::aou_concept_set()] queries for
#' your study's concepts return non-empty, develop-able results. Call with the
#' same `concepts`/`domain` you pass to `aou_concept_set()`.
#'
#' For finer control (specific participants, specific dates), use the lower-level
#' [mock_add_occurrences()] / [mock_add_concepts()] directly.
#'
#' @param con A connection from [mock_aou_connect()].
#' @param concepts Integer vector of concept ids to seed.
#' @param domain One of "condition", "drug", "measurement", "observation",
#'   "procedure", "device", "visit".
#' @param prevalence Fraction of participants (0-1) who should have at least one
#'   occurrence. Values below 1 make eligibility joins return partial cohorts.
#' @param max_per_person Maximum occurrences generated per selected participant.
#' @param values For `domain = "measurement"`, a length-2 numeric range for
#'   `value_as_number`. Ignored for other domains.
#' @param seed Optional random seed for reproducible seeding.
#' @param quiet Suppress the summary message.
#' @return The number of occurrence rows inserted, invisibly.
#' @export
mock_seed_concept_set <- function(con, concepts, domain = "condition",
                                  prevalence = 0.3, max_per_person = 3L,
                                  values = c(0, 100), seed = NULL, quiet = FALSE) {
  if (!is.null(seed)) withr::local_seed(seed)
  if (!domain %in% names(domain_map())) {
    cli::cli_abort("{.arg domain} must be one of {.val {names(domain_map())}}.")
  }
  concepts <- as.integer(concepts)
  mock_add_concepts(con, concepts, domain_id = stringr::str_to_title(domain))

  persons <- mock_person_ids(con)
  chosen <- persons[stats::runif(length(persons)) < prevalence]
  if (length(chosen) == 0) {
    if (!quiet) cli::cli_warn("No participants selected at {.arg prevalence} = {prevalence}.")
    return(invisible(0L))
  }
  # a random number of occurrences per chosen participant
  n_ev <- sample.int(max_per_person, length(chosen), replace = TRUE)
  pid <- rep(chosen, n_ev)
  N <- length(pid)
  day0 <- as.Date("2008-01-01")
  dates <- day0 + sample.int(as.integer(as.Date("2023-01-01") - day0), N, replace = TRUE)
  value <- if (domain == "measurement") round(stats::runif(N, values[1], values[2]), 1) else NULL

  mock_add_occurrences(con, domain, person_id = pid, concept_id = resample(concepts, N),
                       date = dates, value = value, source = "ehr")

  if (!quiet) {
    cli::cli_inform(c("v" = "Seeded {N} {domain} occurrence{?s} for {length(chosen)} participant{?s} (prevalence {prevalence})."))
  }
  invisible(N)
}

#' Seed survey responses into the mock database
#'
#' Inserts `observation` rows (with PPI `_ext` rows) for the given survey
#' question concept ids, so [allofus::aou_survey()] returns data for them. Answer
#' codes are taken from `allofus::aou_codebook` when available, or supplied via
#' `answers`. Call with the same question concept ids you pass to `aou_survey()`.
#'
#' @param con A connection from [mock_aou_connect()].
#' @param concept_ids Integer vector of survey question concept ids.
#' @param answers Optional character vector of answer codes (value_source_value)
#'   to sample from. If `NULL`, uses the codebook `choices` for each question.
#' @param prevalence Fraction of participants (0-1) who respond to each question.
#' @param seed Optional random seed.
#' @param quiet Suppress the summary message.
#' @return The number of observation rows inserted, invisibly.
#' @export
mock_seed_survey <- function(con, concept_ids, answers = NULL, prevalence = 0.8,
                             seed = NULL, quiet = FALSE) {
  if (!is.null(seed)) withr::local_seed(seed)
  concept_ids <- as.integer(concept_ids)
  mock_add_concepts(con, concept_ids, domain_id = "Observation")
  persons <- mock_person_ids(con)

  spec <- table_spec("observation")
  spec_ext <- table_spec("observation_ext")
  next_obs_id <- next_id(con, "observation", "observation_id")
  day0 <- as.Date("2017-05-01")
  mains <- list()
  exts <- list()
  for (q in concept_ids) {
    cb_row <- aou_codebook[as.integer(aou_codebook$concept_id) == q, ]
    code <- if (nrow(cb_row)) cb_row$concept_code[1] else paste0("mock_", q)
    ans <- answers
    if (is.null(ans)) ans <- if (nrow(cb_row)) parse_choice_codes(cb_row$choices[1]) else character(0)
    if (length(ans) == 0) ans <- "PMI_Skip"
    responders <- persons[stats::runif(length(persons)) < prevalence]
    if (length(responders) == 0) next
    N <- length(responders)
    ids <- next_obs_id + seq_len(N)
    next_obs_id <- next_obs_id + N
    vals <- list(
      person_id = responders, observation_id = ids,
      observation_concept_id = rep(q, N), observation_source_concept_id = rep(q, N),
      observation_source_value = rep(code, N),
      observation_date = day0 + sample.int(2000L, N, replace = TRUE),
      value_source_value = resample(ans, N), value_source_concept_id = 0L
    )
    mains[[length(mains) + 1]] <- assemble_rows(spec, N, vals)
    exts[[length(exts) + 1]] <- assemble_rows(spec_ext, N, list(observation_id = ids, src_id = rep("PPI/PM", N)))
  }
  if (length(mains) == 0) return(invisible(0L))
  DBI::dbAppendTable(con, "observation", dplyr::bind_rows(mains))
  DBI::dbAppendTable(con, "observation_ext", dplyr::bind_rows(exts))
  total <- sum(purrr::map_int(mains, nrow))
  if (!quiet) cli::cli_inform(c("v" = "Seeded {total} survey response{?s} for {length(concept_ids)} question{?s}."))
  invisible(total)
}
