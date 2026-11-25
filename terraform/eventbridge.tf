# Runs the ETL on the 1st of each month at 06:00 UTC — adjust to match
# ABS Retail Trade release schedule once you confirm it.
resource "aws_cloudwatch_event_rule" "monthly_etl" {
  name                = "${var.project_name}-monthly-etl"
  schedule_expression = "cron(0 6 1 * ? *)"
}

resource "aws_iam_role" "eventbridge_ecs" {
  name = "${var.project_name}-eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "${var.project_name}-eventbridge-run-task"
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ecs:RunTask"
      Resource = aws_ecs_task_definition.etl.arn
    }, {
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
    }]
  })
}

resource "aws_cloudwatch_event_target" "run_etl_task" {
  rule     = aws_cloudwatch_event_rule.monthly_etl.name
  arn      = aws_ecs_cluster.this.arn
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.etl.arn
    task_count           = 1
    launch_type           = "FARGATE"

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [aws_security_group.ecs_task.id]
      assign_public_ip = true # needed since task calls external ABS/RBA APIs
    }
  }
}
