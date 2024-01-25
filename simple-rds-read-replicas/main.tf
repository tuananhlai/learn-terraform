provider "aws" {
  region = "us-east-1"
}

resource "random_password" "db_password" {
  length  = 16
  special = true
  upper   = true
  numeric = true
}

module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name            = "DbSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::0/0"
    }
  ]
}

resource "aws_db_instance" "primary" {
  identifier_prefix      = "primary"
  instance_class         = "db.t3.micro"
  skip_final_snapshot    = true
  allocated_storage      = 20
  engine                 = "postgres"
  db_name                = "tftest"
  username               = "andy"
  password               = random_password.db_password.result
  publicly_accessible    = true
  vpc_security_group_ids = [module.db_sg.security_group_id]
  # The source database must have automated backup enabled in order to avoid the error below.
  # Error: creating RDS DB Instance (read replica) (replica20240122230903220800000001): InvalidDBInstanceState: Automated backups are not enabled for this database instance. To enable automated backups, use ModifyDBInstance to set the backup retention period to a non-zero value.
  backup_retention_period = 1
  apply_immediately       = true
}

provider "aws" {
  alias  = "secondary"
  region = "us-west-2"
}

module "replica_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  providers = {
    aws = aws.secondary
  }

  name            = "DbSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::0/0"
    }
  ]
}

resource "aws_db_instance" "read_replica" {
  provider               = aws.secondary
  instance_class         = "db.t3.micro"
  identifier_prefix      = "replica"
  replicate_source_db    = aws_db_instance.primary.arn
  skip_final_snapshot    = true
  publicly_accessible    = true
  apply_immediately      = true
  vpc_security_group_ids = [module.replica_sg.security_group_id]
}

output "primary" {
  value = {
    password = nonsensitive(random_password.db_password.result),
    username = aws_db_instance.primary.username
    address  = aws_db_instance.primary.address
  }
}

output "read_replica" {
  value = {
    address = aws_db_instance.read_replica.address
    message = "The read replica DB instance use the same username and password as the primary instance."
  }
}

# TEST:
# - Create a new table and insert some records into the primary instance. This data should
#   be replicated to the read replica.
# - Try creating a new table in the replica instance. This operation should failed because
#   the instance is read-only.
# - Promote the read replica to a full instance by remove `replicate_source_db` field. Now,
#   you should be able to create a new table in the replica instance. Note that promoting
#   replicas is irreversible.