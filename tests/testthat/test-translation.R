# BigQuery-compatibility dbplyr translations attached to mock connections.

test_that("BigQuery 3-arg date_diff translates with correct semantics", {
  con <- local_mock_con()
  out <- dplyr::tbl(con, "person") |>
    dplyr::mutate(d = date_diff(as.Date("2020-01-01"), as.Date("1990-01-01"), dplyr::sql("day"))) |>
    head(1) |>
    dplyr::pull(d)
  expect_equal(as.numeric(out), 10957) # days from 1990-01-01 to 2020-01-01
})

test_that("date_diff works in a windowed (lag) context", {
  con <- local_mock_con()
  res <- dplyr::tbl(con, "measurement") |>
    dplyr::group_by(person_id) |>
    dbplyr::window_order(measurement_date) |>
    dplyr::mutate(gap = date_diff(measurement_date, lag(measurement_date), dplyr::sql("day"))) |>
    head(20) |>
    dplyr::collect()
  expect_true("gap" %in% names(res))
})

test_that("DATE_ADD with a (negative) INTERVAL literal works and returns a Date", {
  con <- local_mock_con()
  res <- dplyr::tbl(con, "person") |>
    dplyr::mutate(
      d0 = as.Date("2020-06-01"),
      back1y = DATE_ADD(as.Date("2020-06-01"), dplyr::sql(paste("INTERVAL", -1, "year")))
    ) |>
    head(1) |>
    dplyr::collect()
  expect_s3_class(res$back1y, "Date")
  expect_equal(res$back1y, as.Date("2019-06-01"))
})

test_that("BigQuery idiom translations are case-insensitive", {
  con <- local_mock_con()
  res <- dplyr::tbl(con, "person") |>
    dplyr::mutate(
      lo_diff = date_diff(as.Date("2020-01-01"), as.Date("1990-01-01"), dplyr::sql("day")),
      up_diff = DATE_DIFF(as.Date("2020-01-01"), as.Date("1990-01-01"), dplyr::sql("day")),
      lo_add = date_add(as.Date("2020-01-01"), dplyr::sql("INTERVAL 1 year")),
      up_add = DATE_ADD(as.Date("2020-01-01"), dplyr::sql("INTERVAL 1 year"))
    ) |>
    head(1) |>
    dplyr::collect()
  expect_equal(as.numeric(res$lo_diff), as.numeric(res$up_diff))
  expect_equal(res$lo_add, res$up_add)
  expect_equal(res$lo_add, as.Date("2021-01-01"))
})

test_that("as.Date tolerates float-valued concatenated components", {
  con <- local_mock_con()
  # mirrors the All of Us date-of-birth construction, where if_else(is.na(x), 1, x)
  # promotes integer parts to double -> "1994-5.0-28.0"
  res <- dplyr::tbl(con, "person") |>
    dplyr::mutate(dob = as.Date(paste0(
      year_of_birth, "-",
      dplyr::if_else(is.na(month_of_birth), 1, month_of_birth), "-",
      dplyr::if_else(is.na(day_of_birth), 1, day_of_birth)
    ))) |>
    dplyr::select(person_id, dob) |>
    head(5) |>
    dplyr::collect()
  expect_s3_class(res$dob, "Date")
  expect_false(any(is.na(res$dob)))
})

test_that("collect() tolerates the BigQuery-only page_size argument", {
  con <- local_mock_con()
  res <- dplyr::tbl(con, "person") |> dplyr::collect(page_size = 50000)
  expect_equal(nrow(res), 300)
})
