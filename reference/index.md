# Package index

## Connecting

Connect to the local mock database. Stores the connection where allofus
looks for it, so allofus functions work against it unchanged.

- [`mock_aou_connect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_connect.md)
  : Connect to the local mock All of Us database
- [`mock_aou_disconnect()`](https://louisahsmith.github.io/mockallofus/reference/mock_aou_disconnect.md)
  : Disconnect from the mock database and clear the stored connection

## Building the mock database

Create or locate the local DuckDB database.

- [`build_mock_db()`](https://louisahsmith.github.io/mockallofus/reference/build_mock_db.md)
  : Build a local mock All of Us DuckDB database
- [`default_mock_db_path()`](https://louisahsmith.github.io/mockallofus/reference/default_mock_db_path.md)
  : Default cache location for the mock database

## OMOP vocabulary

Optionally load the full OMOP vocabulary for concept-relationship work.

- [`mock_load_vocabulary()`](https://louisahsmith.github.io/mockallofus/reference/mock_load_vocabulary.md)
  : Load a full OMOP vocabulary into the mock database

## Seeding your study’s data

Put the concepts and survey questions your analysis looks for into the
database, at a controllable prevalence, so queries return develop-able
data.

- [`mock_seed_concept_set()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_concept_set.md)
  : Seed a concept set into the mock database
- [`mock_seed_survey()`](https://louisahsmith.github.io/mockallofus/reference/mock_seed_survey.md)
  : Seed survey responses into the mock database

## Seeding building blocks

Lower-level primitives for inserting custom synthetic data.

- [`mock_add_concepts()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_concepts.md)
  : Add concept definitions to the mock database
- [`mock_add_occurrences()`](https://louisahsmith.github.io/mockallofus/reference/mock_add_occurrences.md)
  : Add clinical-event occurrences to the mock database
- [`mock_person_ids()`](https://louisahsmith.github.io/mockallofus/reference/mock_person_ids.md)
  : Participant ids in the mock database

## BigQuery compatibility

Register BigQuery-compatible SQL on a connection (used internally).

- [`register_bq_macros()`](https://louisahsmith.github.io/mockallofus/reference/register_bq_macros.md)
  : Register BigQuery-compatibility macros on a DuckDB connection
