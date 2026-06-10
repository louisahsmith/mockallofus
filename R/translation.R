# BigQuery -> DuckDB dbplyr translations.
#
# Some allofus / All of Us analysis code calls BigQuery SQL functions inside
# dbplyr pipelines (passed through verbatim by dbplyr). The most common is
# BigQuery's three-argument DATE_DIFF:
#
#     date_diff(date_a, date_b, sql("day"))   # BigQuery: date_a - date_b, in days
#
# DuckDB's date_diff has a different signature, date_diff(part, start, end), and
# the bare `day` identifier cannot be handled by a SQL macro. We instead add a
# dbplyr translation so the function is rewritten correctly before SQL is
# generated. To attach the translation without corrupting the (S4) DuckDB
# connection object, we use an S4 subclass of duckdb_connection.

# The S4 class `mock_aou_connection` (contains "duckdb_connection") is defined in
# .onLoad() (see zzz.R), so the duckdb S4 class is available when it is created.

# Rewrite BigQuery DATE_DIFF(a, b, unit) -> DuckDB date_diff('unit', b, a).
# Both have the semantics "a - b", so the operands are swapped and the unit,
# which arrives as sql("day"), is turned into a quoted string literal.
bq_date_diff <- function(a, b, units) {
  u <- tolower(trimws(gsub("[\"']", "", as.character(units))))
  dbplyr::build_sql(
    dbplyr::sql(paste0("date_diff('", u, "', ")), b, dbplyr::sql(", "), a, dbplyr::sql(")")
  )
}

# Tolerant as.Date(). All of Us algorithm code commonly builds dates by
# concatenating year/month/day, e.g.
#     as.Date(paste0(year_of_birth, "-", month_of_birth, "-", day_of_birth))
# where if_else(is.na(x), 1, x) promotes the integer parts to double, producing
# strings like "1994-5.0-28.0". BigQuery tolerates this; DuckDB's strict CAST AS
# DATE does not. Strip any ".0" fragments before casting (a no-op for clean date
# or timestamp strings). DuckDB accepts non-zero-padded components ("1994-5-28").
bq_as_date <- function(x) {
  dbplyr::build_sql(
    dbplyr::sql("CAST(replace(CAST("), x,
    dbplyr::sql(" AS VARCHAR), '.0', '') AS DATE)")
  )
}

# BigQuery DATE_ADD(date, INTERVAL n unit) (as written in All of Us code, e.g.
#   DATE_ADD(first_survey, sql(paste("INTERVAL", -1, "year")))
# ). DuckDB rejects a bare negative interval literal ("INTERVAL -1 year"), so
# rewrite to `CAST(date + to_<unit>s(n) AS DATE)`, which handles negatives and
# returns a DATE (matching BigQuery's DATE_ADD return type).
bq_date_add <- function(x, interval) {
  s <- as.character(interval)
  m <- regmatches(s, regexec("INTERVAL\\s+\\(?(-?[0-9]+)\\)?\\s+([A-Za-z]+)", s, perl = TRUE))[[1]]
  unit_fn <- if (length(m) == 3) {
    switch(tolower(m[3]),
      year = , years = "to_years",
      month = , months = "to_months",
      week = , weeks = "to_weeks",
      day = , days = "to_days",
      hour = , hours = "to_hours",
      minute = , minutes = "to_minutes",
      second = , seconds = "to_seconds",
      NA_character_
    )
  } else {
    NA_character_
  }
  if (!is.na(unit_fn)) {
    return(dbplyr::build_sql(
      dbplyr::sql("CAST("), x, dbplyr::sql(paste0(" + ", unit_fn, "(", m[2], ")")),
      dbplyr::sql(" AS DATE)")
    ))
  }
  # fallback: just parenthesize the number so DuckDB can parse the literal
  s2 <- gsub("(INTERVAL\\s+)(-?[0-9]+)", "\\1(\\2)", s, perl = TRUE)
  dbplyr::build_sql(dbplyr::sql("DATE_ADD("), x, dbplyr::sql(paste0(", ", s2, ")")))
}

#' Collect method that tolerates BigQuery-only download arguments
#'
#' All of Us code often calls `collect(page_size = ...)`, where `page_size` is a
#' `bigrquery` download argument. DuckDB's `collect()` rejects unknown `...`
#' arguments, so drop the BigQuery-specific ones before collecting.
#'
#' @param con A `mock_aou_connection`.
#' @param sql,n,warn_incomplete,... Passed to the underlying DBI collect method.
#' @return A data frame.
#' @exportS3Method dbplyr::db_collect
#' @keywords internal
db_collect.mock_aou_connection <- function(con, sql, n = -1, warn_incomplete = TRUE, ...) {
  dots <- list(...)
  dots[c("page_size", "billing", "bigint", "max_connections")] <- NULL
  parent <- utils::getS3method("db_collect", "DBIConnection", envir = asNamespace("dbplyr"))
  do.call(parent, c(list(con, sql, n = n, warn_incomplete = warn_incomplete), dots))
}

#' dbplyr SQL translation for mock All of Us (DuckDB) connections
#'
#' Extends DuckDB's dbplyr translation with BigQuery-compatible functions
#' (currently `date_diff()`/`DATE_DIFF()`) used by All of Us analysis code.
#' Not called directly.
#'
#' @param con A `mock_aou_connection`.
#' @return A `dbplyr` `sql_variant`.
#' @exportS3Method dbplyr::sql_translation
#' @keywords internal
sql_translation.mock_aou_connection <- function(con) {
  base <- utils::getS3method("sql_translation", "duckdb_connection", envir = asNamespace("dbplyr"))(con)
  dbplyr::sql_variant(
    scalar = dbplyr::sql_translator(
      .parent = base$scalar,
      date_diff = bq_date_diff,
      DATE_DIFF = bq_date_diff,
      date_add = bq_date_add,
      DATE_ADD = bq_date_add,
      as.Date = bq_as_date
    ),
    aggregate = base$aggregate,
    window = base$window
  )
}
