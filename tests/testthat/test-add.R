test_that("mock_person_ids returns the participant ids", {
  con <- local_mock_con(n_persons = 300L)
  ids <- mock_person_ids(con)
  expect_length(ids, 300)
  expect_type(ids, "integer")
})

test_that("mock_add_concepts inserts only new concepts, with given names", {
  con <- local_mock_con()
  n <- mock_add_concepts(con, c(99999001, 99999002), c("Custom A", "Custom B"),
                         domain_id = "Condition")
  expect_equal(n, 2)
  res <- DBI::dbGetQuery(con, "SELECT concept_name FROM concept WHERE concept_id = 99999001")
  expect_equal(res$concept_name, "Custom A")
  # calling again is a no-op (already present)
  expect_equal(mock_add_concepts(con, 99999001, "Custom A"), 0)
})

test_that("mock_add_occurrences inserts events plus matching EHR _ext rows", {
  con <- local_mock_con(n_persons = 200L)
  people <- mock_person_ids(con)[1:30]
  mock_add_concepts(con, 88888001, "Seeded condition", domain_id = "Condition")
  ids <- mock_add_occurrences(con, "condition", person_id = people,
                              concept_id = 88888001, date = as.Date("2021-06-01"))
  expect_length(ids, 30)
  n_main <- DBI::dbGetQuery(con,
    "SELECT count(*) n FROM condition_occurrence WHERE condition_concept_id = 88888001")$n
  expect_equal(as.numeric(n_main), 30)
  # matching _ext rows tagged as EHR
  n_ehr <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*) n FROM condition_occurrence_ext WHERE condition_occurrence_id IN (%s) AND LOWER(src_id) LIKE 'ehr site%%'",
    paste(ids, collapse = ",")))$n
  expect_equal(as.numeric(n_ehr), 30)
})

test_that("mock_add_occurrences writes value_as_number for measurements", {
  con <- local_mock_con(n_persons = 100L)
  people <- mock_person_ids(con)[1:10]
  mock_add_concepts(con, 77777001, "Seeded lab", domain_id = "Measurement")
  mock_add_occurrences(con, "measurement", person_id = people, concept_id = 77777001,
                       date = as.Date("2020-01-01"), value = 6.5)
  vals <- DBI::dbGetQuery(con,
    "SELECT DISTINCT value_as_number FROM measurement WHERE measurement_concept_id = 77777001")
  expect_equal(as.numeric(vals$value_as_number), 6.5)
})

test_that("mock_add_occurrences records end_date for spanning events", {
  con <- local_mock_con(n_persons = 50L)
  people <- mock_person_ids(con)[1:10]
  mock_add_concepts(con, 755695L, "fluoxetine", domain_id = "Drug")
  mock_add_occurrences(con, "drug", person_id = people, concept_id = 755695L,
                       date = as.Date("2021-01-01"), end_date = as.Date("2021-03-31"))
  res <- DBI::dbGetQuery(con,
    "SELECT DISTINCT drug_exposure_start_date, drug_exposure_end_date
     FROM drug_exposure WHERE drug_concept_id = 755695")
  expect_equal(as.Date(res$drug_exposure_start_date), as.Date("2021-01-01"))
  expect_equal(as.Date(res$drug_exposure_end_date), as.Date("2021-03-31"))
})

test_that("mock_add_occurrences errors on an unknown domain", {
  con <- local_mock_con(n_persons = 50L)
  expect_error(
    mock_add_occurrences(con, "nonsense", person_id = 1L, concept_id = 1L, date = Sys.Date()),
    "domain"
  )
})
