test_that("build_mock_db creates all dictionary tables", {
  con <- local_mock_con()
  tables <- DBI::dbListTables(con)
  expect_true(all(c("person", "concept", "condition_occurrence", "measurement",
                    "observation", "drug_exposure", "observation_period",
                    "cb_search_person", "ds_survey") %in% tables))
})

test_that("core tables are populated", {
  con <- local_mock_con(n_persons = 300L)
  expect_equal(n_rows(con, "person"), 300)
  expect_gt(n_rows(con, "condition_occurrence"), 0)
  expect_gt(n_rows(con, "measurement"), 0)
  expect_gt(n_rows(con, "observation"), 0)
  # _ext rows align 1:1 with their domain table
  expect_equal(n_rows(con, "condition_occurrence"), n_rows(con, "condition_occurrence_ext"))
  expect_equal(n_rows(con, "measurement"), n_rows(con, "measurement_ext"))
})

test_that("vignette concepts are present so documented workflows return data", {
  con <- local_mock_con()
  q <- function(sql) as.numeric(DBI::dbGetQuery(con, sql)[[1]])
  expect_gt(q("SELECT count(*) FROM condition_occurrence WHERE condition_concept_id IN (201826,4193704)"), 0)
  expect_gt(q("SELECT count(*) FROM drug_exposure WHERE drug_concept_id IN (40164929,40164897)"), 0)
  expect_gt(q("SELECT count(*) FROM measurement WHERE measurement_concept_id IN (3004410,3005673)"), 0)
  expect_gt(q("SELECT count(*) FROM observation WHERE observation_source_concept_id IN (1585838,1586135)"), 0)
})

test_that("EHR rows are tagged so aou_observation_period's filter matches", {
  con <- local_mock_con()
  ehr <- as.numeric(DBI::dbGetQuery(con,
    "SELECT count(*) FROM measurement_ext WHERE LOWER(src_id) LIKE 'ehr site%'")[[1]])
  expect_gt(ehr, 0)
})

test_that("build is deterministic for a fixed seed", {
  p1 <- withr::local_tempfile(fileext = ".duckdb")
  p2 <- withr::local_tempfile(fileext = ".duckdb")
  build_mock_db(p1, n_persons = 200L, seed = 5L, quiet = TRUE)
  build_mock_db(p2, n_persons = 200L, seed = 5L, quiet = TRUE)
  c1 <- DBI::dbConnect(duckdb::duckdb(), p1); on.exit(DBI::dbDisconnect(c1, shutdown = TRUE), add = TRUE)
  c2 <- DBI::dbConnect(duckdb::duckdb(), p2); on.exit(DBI::dbDisconnect(c2, shutdown = TRUE), add = TRUE)
  expect_equal(
    DBI::dbGetQuery(c1, "SELECT count(*) n FROM condition_occurrence")$n,
    DBI::dbGetQuery(c2, "SELECT count(*) n FROM condition_occurrence")$n
  )
})

test_that("cb_search_person carries a usable date of birth", {
  # dob is the only usable birth date in the controlled tier, because
  # person.birth_datetime is suppressed. Leaving it NULL meant any code that
  # aged a cohort returned zero rows locally while working on the Workbench.
  con <- local_mock_con(n_persons = 50L)
  res <- DBI::dbGetQuery(con, "SELECT dob, age_at_cdr FROM cb_search_person")
  expect_false(anyNA(res$dob))
  expect_s3_class(res$dob, "Date")
  expect_false(anyNA(res$age_at_cdr))
})

test_that("cb_search_person has no entirely empty columns", {
  con <- local_mock_con(n_persons = 50L)
  cols <- DBI::dbListFields(con, "cb_search_person")
  counts <- DBI::dbGetQuery(con, sprintf(
    "SELECT %s FROM cb_search_person",
    paste(sprintf('count("%s") AS "%s"', cols, cols), collapse = ", ")
  ))
  empty <- names(counts)[as.numeric(counts[1, ]) == 0]
  expect_equal(empty, character())
})

test_that("person month and day of birth are suppressed, as in the controlled tier", {
  # All of Us nulls month_of_birth, day_of_birth and birth_datetime. The mock
  # matches, so code reading them fails here rather than on the Workbench.
  con <- local_mock_con(n_persons = 50L)
  res <- DBI::dbGetQuery(
    con, "SELECT month_of_birth, day_of_birth, birth_datetime FROM person"
  )
  expect_true(all(is.na(res$month_of_birth)))
  expect_true(all(is.na(res$day_of_birth)))
  expect_true(all(is.na(res$birth_datetime)))
})

test_that("sex at birth agrees between person and cb_search_person", {
  con <- local_mock_con(n_persons = 100L)
  n <- DBI::dbGetQuery(con, "
    SELECT count(*) AS n FROM person p
    JOIN cb_search_person c USING (person_id)
    WHERE (p.sex_at_birth_concept_id = 45880669 AND c.sex_at_birth <> 'Male')
       OR (p.sex_at_birth_concept_id <> 45880669 AND c.sex_at_birth = 'Male')
  ")$n
  expect_equal(as.numeric(n), 0)
})

test_that("clinical rows carry source concepts", {
  # All of Us row suppression is keyed on *_source_concept_id, so an all-NULL
  # source column makes any suppression analysis silently empty locally
  con <- local_mock_con(n_persons = 100L)
  for (tb in c("condition_occurrence", "procedure_occurrence", "measurement")) {
    col <- sub("_occurrence$", "", tb)
    src <- sprintf("%s_source_concept_id", col)
    res <- DBI::dbGetQuery(con, sprintf(
      "SELECT count(*) AS n, count(%s) AS n_src FROM %s", src, tb
    ))
    expect_gt(res$n, 0)
    expect_equal(res$n_src, res$n, info = tb)
  }
})

test_that("some source concepts are unmapped, as in the real CDR", {
  con <- local_mock_con(n_persons = 200L)
  n0 <- DBI::dbGetQuery(con, "
    SELECT count(*) AS n FROM condition_occurrence
    WHERE condition_source_concept_id = 0
  ")$n
  expect_gt(as.numeric(n0), 0)
})
