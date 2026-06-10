test_that("mock_load_vocabulary loads Athena-style files and enables descendant queries", {
  dir <- withr::local_tempdir()
  writeLines(c(
    "concept_id\tconcept_name\tdomain_id\tvocabulary_id\tconcept_class_id\tstandard_concept\tconcept_code\tvalid_start_date\tvalid_end_date\tinvalid_reason",
    "201826\tType 2 diabetes mellitus\tCondition\tSNOMED\tClinical Finding\tS\t44054006\t20020101\t20991231\t",
    "4193704\tT2DM without complication\tCondition\tSNOMED\tClinical Finding\tS\t111552007\t20020101\t20991231\t",
    "443238\tDisorder of glucose metabolism\tCondition\tSNOMED\tClinical Finding\tS\t111\t20020101\t20991231\t"
  ), file.path(dir, "CONCEPT.csv"))
  writeLines(c(
    "ancestor_concept_id\tdescendant_concept_id\tmin_levels_of_separation\tmax_levels_of_separation",
    "443238\t201826\t1\t1",
    "443238\t4193704\t2\t2"
  ), file.path(dir, "CONCEPT_ANCESTOR.csv"))

  con <- local_mock_con(n_persons = 50L)
  loaded <- mock_load_vocabulary(con, dir, quiet = TRUE)
  expect_setequal(loaded, c("concept", "concept_ancestor"))
  expect_equal(n_rows(con, "concept_ancestor"), 2)

  desc <- dplyr::tbl(con, "concept_ancestor") |>
    dplyr::filter(ancestor_concept_id == 443238L) |>
    dplyr::inner_join(dplyr::tbl(con, "concept"),
                      by = c("descendant_concept_id" = "concept_id")) |>
    dplyr::pull(concept_name)
  expect_length(desc, 2)
  expect_true("Type 2 diabetes mellitus" %in% desc)
})

test_that("mock_load_vocabulary warns when no files are found", {
  con <- local_mock_con(n_persons = 50L)
  expect_warning(mock_load_vocabulary(con, withr::local_tempdir(), quiet = TRUE),
                 "No vocabulary")
})
