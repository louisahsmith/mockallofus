# Load a full OMOP vocabulary into the mock database

By default the mock database ships only a tiny placeholder `concept`
table and empty vocabulary tables — enough to run analyses, but not
enough to explore concept relationships. If your workflow needs the real
vocabulary (for example, finding descendants or ancestors via
`concept_ancestor`), download the vocabulary files from the OHDSI
[Athena](https://athena.ohdsi.org) repository and load them with this
function. You can then develop and test ancestor/descendant queries
locally instead of on the (metered) Workbench.

## Usage

``` r
mock_load_vocabulary(con, dir, tables = NULL, delim = "\t", quiet = FALSE)
```

## Arguments

- con:

  A connection from
  [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md).

- dir:

  Directory containing the Athena vocabulary CSV files.

- tables:

  Which vocabulary tables to load. Defaults to all of those found among
  `concept`, `concept_ancestor`, `concept_relationship`,
  `concept_synonym`, `vocabulary`, `domain`, `concept_class`,
  `relationship`, and `drug_strength`.

- delim:

  Field delimiter in the files (Athena uses tab, the default).

- quiet:

  Suppress the summary message.

## Value

The names of the tables loaded, invisibly.

## Details

Each requested table is **replaced** with the contents of the matching
file, so call this before seeding any custom (non-real) concepts. The
files are the tab-delimited CSVs Athena provides (`CONCEPT.csv`,
`CONCEPT_ANCESTOR.csv`, ...); matching is case-insensitive.

Athena vocabulary files are large; loading is done by DuckDB directly
from disk, which is fast, but the resulting database file will grow
accordingly.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- mock_aou_connect()
# after downloading + unzipping an Athena vocabulary bundle:
mock_load_vocabulary(con, "~/Downloads/athena-vocab")

# now descendant/ancestor queries work locally
library(dplyr)
tbl(con, "concept_ancestor") |>
  filter(ancestor_concept_id == 201826L) |>
  inner_join(tbl(con, "concept"),
             by = c("descendant_concept_id" = "concept_id"))
} # }
```
