class PostgresSourceRecord < ApplicationRecord
  self.abstract_class = true

  # Connect to external PostgreSQL database (read-only data lake)
  # Both writing and reading point to the same connection since we don't have a separate replica
  connects_to database: { writing: :postgres_source, reading: :postgres_source }
end
