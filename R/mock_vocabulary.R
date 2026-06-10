#' Load a full OMOP vocabulary into the mock database
#'
#' By default the mock database ships only a tiny placeholder `concept` table and
#' empty vocabulary tables --- enough to run analyses, but not enough to explore
#' concept relationships. If your workflow needs the real vocabulary (for
#' example, finding descendants or ancestors via `concept_ancestor`), download
#' the vocabulary files from the OHDSI [Athena](https://athena.ohdsi.org)
#' repository and load them with this function. You can then develop and test
#' ancestor/descendant queries locally instead of on the (metered) Workbench.
#'
#' Each requested table is **replaced** with the contents of the matching file,
#' so call this before seeding any custom (non-real) concepts. The files are the
#' tab-delimited CSVs Athena provides (`CONCEPT.csv`, `CONCEPT_ANCESTOR.csv`,
#' ...); matching is case-insensitive.
#'
#' Athena vocabulary files are large; loading is done by DuckDB directly from
#' disk, which is fast, but the resulting database file will grow accordingly.
#'
#' @param con A connection from [mock_aou_connect()].
#' @param dir Directory containing the Athena vocabulary CSV files.
#' @param tables Which vocabulary tables to load. Defaults to all of those found
#'   among `concept`, `concept_ancestor`, `concept_relationship`,
#'   `concept_synonym`, `vocabulary`, `domain`, `concept_class`, `relationship`,
#'   and `drug_strength`.
#' @param delim Field delimiter in the files (Athena uses tab, the default).
#' @param quiet Suppress the summary message.
#' @return The names of the tables loaded, invisibly.
#' @export
#' @examples
#' \dontrun{
#' con <- mock_aou_connect()
#' # after downloading + unzipping an Athena vocabulary bundle:
#' mock_load_vocabulary(con, "~/Downloads/athena-vocab")
#'
#' # now descendant/ancestor queries work locally
#' library(dplyr)
#' tbl(con, "concept_ancestor") |>
#'   filter(ancestor_concept_id == 201826L) |>
#'   inner_join(tbl(con, "concept"),
#'              by = c("descendant_concept_id" = "concept_id"))
#' }
mock_load_vocabulary <- function(con, dir, tables = NULL, delim = "\t", quiet = FALSE) {
  if (!dir.exists(dir)) {
    cli::cli_abort("Directory {.path {dir}} does not exist.")
  }
  known <- c(
    "concept", "concept_ancestor", "concept_relationship", "concept_synonym",
    "vocabulary", "domain", "concept_class", "relationship", "drug_strength"
  )
  tables <- if (is.null(tables)) known else intersect(tolower(tables), known)

  files <- list.files(dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  base_lower <- tolower(basename(files))

  loaded <- character(0)
  for (tb in tables) {
    idx <- which(base_lower == paste0(tb, ".csv"))
    if (length(idx) == 0) next
    f <- normalizePath(files[idx[1]])
    DBI::dbExecute(con, paste0("DROP TABLE IF EXISTS ", tb))
    DBI::dbExecute(con, sprintf(
      "CREATE TABLE %s AS SELECT * FROM read_csv(%s, delim = %s, header = true, quote = '', sample_size = -1)",
      tb, DBI::dbQuoteString(con, f), DBI::dbQuoteString(con, delim)
    ))
    loaded <- c(loaded, tb)
  }

  if (length(loaded) == 0) {
    cli::cli_warn(c(
      "!" = "No vocabulary CSV files found in {.path {dir}}.",
      "i" = "Expected Athena files such as {.file CONCEPT.csv}, {.file CONCEPT_ANCESTOR.csv}."
    ))
  } else if (!quiet) {
    cli::cli_inform(c("v" = "Loaded {length(loaded)} vocabulary table{?s}: {.val {loaded}}."))
  }
  invisible(loaded)
}
