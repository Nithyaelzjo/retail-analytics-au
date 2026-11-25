# Australian Retail & Consumer Spending Analytics

End to end AWS data pipeline analysing ABS retail trade and RBA cash rate / CPI data.

## Architecture
ABS + RBA data → Dockerised Python ETL (ECR, ECS Fargate) → S3 (raw / processed) → RDS Postgres → Power BI dashboard
EventBridge runs the ETL monthly. All infrastructure is provisioned with Terraform.

## Stack
AWS (S3, ECR, ECS Fargate, RDS Postgres, EventBridge, IAM), Terraform, Docker, Python, Power BI

## Results
- 17,496 retail trade rows, 3,942 RBA cash rate rows, 420 CPI rows loaded
- Power BI KPIs: latest turnover, MoM % change, cash rate, CPI YoY

## Structure
- `etl/` Dockerfile and Python ETL script
- `terraform/` infrastructure as code

## Run it


    cd terraform
    terraform init
    terraform apply
    cd ../etl
    docker build -t retail-etl .
