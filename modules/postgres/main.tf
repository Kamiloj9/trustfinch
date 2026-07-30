resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-step-ca"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-step-ca" })
}

resource "aws_security_group" "database" {
  name_prefix = "${var.name}-postgres-"
  description = "PostgreSQL from step-ca nodes only."
  vpc_id      = var.vpc_id

  ingress {
    description     = "step-ca nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.client_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-postgres" })
}

resource "aws_db_instance" "this" {
  identifier                      = "${var.name}-step-ca"
  engine                          = "postgres"
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  db_name                         = var.database_name
  username                        = var.username
  manage_master_user_password     = true
  allocated_storage               = 50
  max_allocated_storage           = 200
  storage_type                    = "gp3"
  storage_encrypted               = true
  multi_az                        = true
  publicly_accessible             = false
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  backup_retention_period         = var.backup_retention_days
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-step-ca-final"
  auto_minor_version_upgrade      = true
  apply_immediately               = false
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(var.tags, { Name = "${var.name}-step-ca" })
}
