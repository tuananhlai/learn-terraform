provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "query_results" {
  bucket_prefix = "simple-athena-query-results-"
  force_destroy = true
}

resource "aws_athena_database" "default" {
  name          = "simple_athena"
  bucket        = aws_s3_bucket.query_results.id
  force_destroy = true

  acl_configuration {
    s3_acl_option = "BUCKET_OWNER_FULL_CONTROL"
  }
}

resource "aws_athena_named_query" "create_database" {
  name  = "create_database"
  query = "CREATE DATABASE A4L;"

  database = aws_athena_database.default.id
}

resource "aws_athena_named_query" "create_table" {
  name     = "create_table"
  database = aws_athena_database.default.id
  query    = <<EOF
CREATE EXTERNAL TABLE planet (
  id BIGINT,
  type STRING,
  tags MAP<STRING,STRING>,
  lat DECIMAL(9,7),
  lon DECIMAL(10,7),
  nds ARRAY<STRUCT<ref: BIGINT>>,
  members ARRAY<STRUCT<type: STRING, ref: BIGINT, role: STRING>>,
  changeset BIGINT,
  timestamp TIMESTAMP,
  uid BIGINT,
  user STRING,
  version BIGINT
)
STORED AS ORCFILE
LOCATION 's3://osm-pds/planet/';
  EOF
}

resource "aws_athena_named_query" "get_first_100" {
  name     = "get_first_100"
  database = aws_athena_database.default.id
  query    = "Select * from planet LIMIT 100;"
}

resource "aws_athena_named_query" "locate_pet_hospitals" {
  name     = "locate_pet_hospitals"
  database = aws_athena_database.default.id
  query    = <<EOF
SELECT * from planet
WHERE type = 'node'
  AND tags['amenity'] IN ('veterinary')
  AND lat BETWEEN -27.8 AND -27.3
  AND lon BETWEEN 152.2 AND 153.5;
  EOF
}
