# Open WebUI --- AWS Multi-Region Terraform Architecture

> **Infrastructure-as-Code portfolio project:** highly available Open
> WebUI deployed across **us-east-1 (primary)** and **us-east-2
> (secondary)** using Terraform and AWS managed services.

![Architecture](https://img.shields.io/badge/AWS-Multi--Region-orange)
![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-7B42BC)
![Open%20WebUI](https://img.shields.io/badge/Open%20WebUI-v0.6.5-blue)
![Architecture](https://img.shields.io/badge/Architecture-HA%20%2B%20DR-success)

------------------------------------------------------------------------

## 1. Project Overview

This project provisions a production-style AWS architecture for **Open
WebUI** with:

-   Multi-AZ application capacity in two AWS regions
-   Aurora PostgreSQL Global Database for cross-region database
    replication
-   ElastiCache Serverless Redis for application caching / WebSocket
    coordination
-   Application Load Balancers in both regions
-   Route 53 weighted routing for regional traffic control
-   CloudFront as the global entry point
-   AWS WAF for common web attacks, known bad inputs, SQL injection
    protection, and IP-based rate limiting
-   S3 for Open WebUI object storage
-   AWS Secrets Manager for Aurora credentials
-   KMS encryption for Aurora/secrets
-   VPC endpoints for private AWS-service access
-   NAT Gateway for private application subnet outbound access
-   IAM roles instead of static AWS credentials on EC2
-   Systems Manager Session Manager for administration without SSH
-   CloudWatch logs, metrics, alarms, and dashboard
-   CloudTrail for multi-region API auditing
-   GuardDuty support
-   Network ACLs and security groups separating public, application, and
    data tiers

The infrastructure is implemented as reusable Terraform modules and is
intended to demonstrate **cloud architecture, infrastructure automation,
high availability, disaster recovery, security controls, observability,
and operational troubleshooting**.

------------------------------------------------------------------------

# 2. Architecture

## High-Level Flow

``` text
                         Internet
                            |
                            v
                    +----------------+
                    |    Route 53    |
                    |   DNS / ALIAS  |
                    +-------+--------+
                            |
                            v
                    +----------------+
                    |   CloudFront   |
                    | Global Edge CDN |
                    +-------+--------+
                            |
                            v
                  alb.portfolio-domain
                            |
                +-----------+-----------+
                |                       |
                v                       v
       +----------------+      +----------------+
       |  us-east-1     |      |  us-east-2     |
       | PRIMARY        |      | SECONDARY / DR |
       +-------+--------+      +-------+--------+
               |                       |
          +----v----+             +----v----+
          |   ALB   |             |   ALB   |
          +----+----+             +----+----+
               |                       |
        +------+-------+        +------+-------+
        |              |        |              |
        v              v        v              v
     EC2 #1         EC2 #2    EC2 #1         EC2 #2
   Open WebUI      Open WebUI  Open WebUI     Open WebUI
        |              |        |              |
        +-------+------+        +------+-------+
                |                       |
                +-----------+-----------+
                            |
              +-------------+-------------+
              |                           |
              v                           v
      Aurora PostgreSQL            Redis Serverless
      Global Database              (regional cache)
              |
              +----------------------------+
              | Cross-region replication   |
              v                            |
        us-east-2 Aurora <----------------+
        secondary cluster

          S3 object storage is regional
          and is NOT currently CRR-replicated.
```

### Important routing behavior

The current Terraform configuration creates:

-   `alb.<domain>` weighted Route 53 record for **us-east-1 = weight
    100**
-   `alb.<domain>` weighted Route 53 record for **us-east-2 = weight 0**
-   Both records use `evaluate_target_health = true`

The secondary region is therefore provisioned as a DR environment but is
intentionally kept at **desired capacity = 0** for the application Auto
Scaling Group.

> **Important:** this is not an automatic zero-touch regional failover
> design. Regional disaster recovery currently requires an operator to
> activate the secondary application capacity and change routing
> weights.

------------------------------------------------------------------------

# 3. Network Architecture

Each region contains a VPC:

``` text
VPC: 10.0.0.0/16

+---------------------------------------------------------+
|                      AWS VPC                            |
|                                                         |
|  Public Subnets                                         |
|  10.0.1.0/24     10.0.2.0/24                          |
|       |                |                                |
|       +------- Internet Gateway --------+               |
|                         |                              |
|                    ALB / NAT Gateway                   |
|                                                         |
|  Private App Subnets                                    |
|  10.0.10.0/24    10.0.11.0/24                         |
|       |                |                                |
|       +------- EC2 / Open WebUI ----------------+       |
|                                                 |       |
|  Data Subnets                                   |       |
|  10.0.20.0/24    10.0.21.0/24                  |       |
|       |                |                         |       |
|       +---- Aurora PostgreSQL                   |       |
|       +---- Redis Serverless <------------------+       |
|                                                         |
+---------------------------------------------------------+
```

### Subnet roles

  Tier          Subnets                          Purpose
  ------------- -------------------------------- ---------------------
  Public        `10.0.1.0/24`, `10.0.2.0/24`     ALB and NAT Gateway
  Application   `10.0.10.0/24`, `10.0.11.0/24`   EC2/Open WebUI
  Data          `10.0.20.0/24`, `10.0.21.0/24`   Aurora + Redis

The data subnets have **no default Internet route**.

------------------------------------------------------------------------

# 4. Application Layer

## Application Load Balancer

The ALB:

-   Is internet-facing
-   Listens on TCP/HTTP port `80`
-   Forwards to the application target group on port `8080`
-   Performs health checks against `/`
-   Uses a 30-second health-check interval
-   Requires 2 healthy checks before marking a target healthy
-   Requires 5 failed checks before marking a target unhealthy

Open WebUI runs inside Docker:

``` text
ALB :80
   |
   v
Target Group :8080
   |
   v
EC2
   |
   v
Docker
   |
   v
Open WebUI :8080
```

## Auto Scaling

The primary region is configured as:

``` text
min     = 2
desired = 2
max     = 3
```

The secondary region is configured with:

``` text
desired = 0
max     = 3
```

This keeps the DR region available at the infrastructure/data layer
without continuously running the full application fleet.

------------------------------------------------------------------------

# 5. Open WebUI Bootstrap

EC2 instances use a Launch Template and `user_data.sh.tftpl`.

At boot:

1.  Amazon Linux 2023 starts.
2.  Docker and `jq` are installed.
3.  EC2 retrieves the Aurora credentials from Secrets Manager.
4.  The database connection string is constructed at runtime.
5.  Redis configuration is injected.
6.  S3 configuration is injected.
7.  Open WebUI is started as a Docker container.
8.  Docker uses the `awslogs` logging driver for CloudWatch.

The application image is:

``` text
ghcr.io/open-webui/open-webui:v0.6.5
```

No static AWS access key is placed on the EC2 instance. The instance
receives an IAM role and uses AWS APIs through temporary credentials.

------------------------------------------------------------------------

# 6. Database Architecture

## Aurora PostgreSQL Global Database

The primary region creates:

``` text
Aurora PostgreSQL
        |
        v
Aurora Global Database
        |
        +----------------------+
        |                      |
        v                      v
   us-east-1              us-east-2
   PRIMARY                 SECONDARY
```

Configuration includes:

-   Aurora PostgreSQL
-   Engine version `15.10`
-   Storage encryption enabled
-   Two DB instances per region
-   Instances spread across availability zones
-   7-day backup retention
-   PostgreSQL CloudWatch log export
-   Performance Insights
-   Cross-region Global Database replication

The database password is generated by Terraform's `random_password`
resource and stored in AWS Secrets Manager.

### Database security

EC2 can reach Aurora on:

``` text
TCP/5432
```

Aurora does not accept public Internet traffic.

------------------------------------------------------------------------

# 7. Redis Architecture

The project uses:

``` text
Amazon ElastiCache Serverless
Engine: Redis 7
```

Redis is placed in the data subnets and is reachable only from the
application security group.

The configuration includes:

-   TLS connection (`rediss://`)
-   Maximum data storage: 5 GB
-   Maximum 5,000 ECPUs/second
-   Daily snapshots
-   3 snapshot retention days

Redis is used for Open WebUI WebSocket/application coordination and
caching.

------------------------------------------------------------------------

# 8. Object Storage

Open WebUI uses an S3 bucket for application assets.

Each region has its own bucket:

``` text
portfolio-assets-<region>-<account-id>
```

The bucket has:

-   Versioning enabled
-   AES-256 server-side encryption
-   S3 Public Access Block
-   VPC Endpoint-only bucket policy

### Critical DR limitation

**Cross-region S3 replication is NOT currently configured.**

Therefore:

> Aurora has cross-region replication, but user-uploaded S3 objects are
> regional.

If the primary region is completely lost, the secondary application may
not have the latest objects stored in the primary region.

For a production-grade DR implementation, add **S3 Cross-Region
Replication (CRR)** before claiming full regional data redundancy.

------------------------------------------------------------------------

# 9. Security Architecture

## Security Groups

Traffic is intentionally separated:

``` text
Internet
   |
   | :80
   v
ALB SG
   |
   | :8080
   v
EC2 SG
   |
   +---- :5432 ----> Aurora SG
   |
   +---- :6379 ----> Redis SG
```

Aurora and Redis are not directly exposed to the Internet.

## IAM

EC2 receives an IAM role with access to:

-   Secrets Manager
-   KMS decrypt where required
-   S3 bucket/object operations
-   CloudWatch Logs
-   Systems Manager

This avoids placing AWS access keys on instances.

## WAF

The WAF contains:

1.  AWS Managed Common Rule Set
2.  AWS Managed Known Bad Inputs Rule Set
3.  AWS Managed SQL Injection Rule Set
4.  Rate-based blocking

Current rate limit:

``` text
1000 requests / 5 minutes / IP
```

## GuardDuty

GuardDuty is supported through the `enable_guardduty` variable and
includes S3 log monitoring and malware protection for EC2 findings where
enabled.

------------------------------------------------------------------------

# 10. Private AWS Service Connectivity

Private application subnets use VPC endpoints for AWS services.

Configured endpoints include:

-   S3 Gateway Endpoint
-   SQS Interface Endpoint
-   Secrets Manager Interface Endpoint
-   KMS Interface Endpoint
-   SSM Interface Endpoint
-   SSMMessages Interface Endpoint
-   EC2Messages Interface Endpoint
-   CloudWatch Logs Interface Endpoint

This reduces unnecessary Internet/NAT dependency for AWS service
communication.

------------------------------------------------------------------------

# 11. Observability

CloudWatch resources include:

### Logs

-   `/portfolio/<region>/app`
-   `/portfolio/<region>/aurora`
-   `aws-waf-logs-portfolio-<region>`

### Alarms

-   ALB 5XX errors
-   ALB target p99 latency
-   Aurora CPU
-   Aurora freeable memory
-   Redis CPU
-   Redis evictions

### Dashboard

The Terraform module creates a dashboard containing:

-   ALB 5XX errors
-   Aurora CPU
-   Redis CPU
-   ALB target response-time p99

------------------------------------------------------------------------

# 12. CloudTrail

A multi-region CloudTrail trail is configured with:

-   Management events
-   Read/write events
-   Global service events
-   S3 object data events
-   Log file validation
-   S3 encrypted log storage
-   Public access blocked

This provides an audit trail for infrastructure/API activity.

------------------------------------------------------------------------

# 13. Disaster Recovery Strategy

## Failure Scenario 1 --- Single EC2 failure

Expected behavior:

``` text
EC2 fails
   |
   v
ALB health check fails
   |
   v
ASG detects unhealthy capacity
   |
   v
Replacement EC2 launched
   |
   v
User-data installs Docker
   |
   v
Open WebUI starts
   |
   v
ALB marks target healthy
```

### Estimated recovery

A realistic estimate for this implementation is approximately:

**5--15 minutes**

The exact time depends on:

-   EC2 launch time
-   AMI availability
-   package installation
-   Docker image pull time
-   Open WebUI startup
-   ALB health-check convergence

This is an engineering estimate, **not a guaranteed SLA**.

------------------------------------------------------------------------

# 14. Aurora Failure Recovery

There are two DB instances per region across AZs.

For an individual Aurora instance failure, Aurora can fail over to
another healthy instance.

Typical expected application recovery is approximately:

**\~1--3 minutes**

Actual failover time depends on:

-   Failure type
-   Current DB load
-   Connection behavior
-   Application retry behavior
-   AWS control-plane convergence

For a regional failure, Aurora Global Database provides the cross-region
data path.

------------------------------------------------------------------------

# 15. Regional Disaster Recovery

### Current DR model

``` text
Primary:
us-east-1
Application desired capacity = 2
Route53 weight = 100

Secondary:
us-east-2
Application desired capacity = 0
Route53 weight = 0
Aurora secondary = provisioned
```

This is a **warm data / cold application capacity** DR model.

### Estimated regional RTO

For the current implementation:

**Approximately 10--30+ minutes**

A realistic operator-driven sequence is:

1.  Detect primary-region outage.
2.  Promote/fail over Aurora Global Database to us-east-2.
3.  Scale secondary ASG from `0` to `2`.
4.  Wait for EC2 bootstrap and Open WebUI health.
5.  Change Route 53 weighted routing to send traffic to us-east-2.
6.  Allow DNS/CloudFront resolution to converge.
7.  Verify ALB, Open WebUI, database and Redis.
8.  Monitor the secondary region.

The actual RTO can be lower or higher. It must be measured through a
controlled DR test before being presented as an SLA.

### Current RPO

Aurora Global Database replication is asynchronous.

Therefore:

``` text
RPO ≈ Aurora Global Database replication lag
```

There can be a small amount of data loss during an unplanned regional
disaster if transactions have not reached the secondary.

S3 currently has no CRR, so its regional RPO is **not equivalent to
Aurora's RPO**.

------------------------------------------------------------------------

# 16. Important Production Gaps

This project is strong as a cloud/DevOps portfolio architecture, but do
not describe it as a fully automatic production DR platform yet.

### 1. S3 CRR is missing

Primary and secondary S3 buckets are independent.

**Recommendation:** add S3 Cross-Region Replication.

### 2. Secondary application capacity is zero

The secondary ASG is:

``` text
desired_capacity = 0
```

Therefore regional failover is not automatic.

**Recommendation:** automate regional promotion and scaling.

### 3. Route 53 failover is weighted, not explicit failover

The project uses weighted records with health evaluation rather than a
dedicated failover routing policy.

**Recommendation:** evaluate Route 53 Failover Routing with health
checks for a cleaner DR model.

### 4. HTTP is currently used at the ALB/CloudFront edge

The current CloudFront configuration permits HTTP and uses the
CloudFront default certificate.

**Recommendation for production:**

``` text
ACM certificate
      |
      v
CloudFront HTTPS
      |
      v
ALB HTTPS
      |
      v
EC2 :8080
```

Redirect HTTP → HTTPS.

### 5. Destructive Terraform defaults

The current code contains:

``` hcl
force_destroy = true
```

for S3 and:

``` hcl
deletion_protection = false
skip_final_snapshot = true
```

for Aurora.

These settings are convenient for development/testing but are dangerous
for production.

------------------------------------------------------------------------

# 17. Proof of Work

The implementation was tested with real AWS resources rather than being
only a Terraform code exercise.

## Evidence 1 --- Application health / ALB recovery

The captured test shows the ALB health endpoint returning:

``` text
200 STANDBY
```

followed by:

``` text
502 DOWN
```

and then recovery to:

``` text
200 OPEN WEBUI
```

This demonstrates that the ALB was actually routing traffic to the Open
WebUI application and that target failure/recovery was observable
through the load balancer.

![ALB health and recovery
evidence](docs/evidence/alb-health-recovery.png)

## Evidence 2 --- S3 infrastructure

The AWS console shows the regional application asset bucket:

``` text
portfolio-assets-use1-610519500341
```

The bucket has been successfully created and is accessible through the
AWS account.

![S3 bucket evidence](docs/evidence/s3-bucket.png)

## Evidence 3 --- Terraform infrastructure

The Terraform project contains separate modules for:

-   VPC
-   ALB
-   Auto Scaling
-   Aurora
-   Redis
-   S3
-   WAF
-   CloudWatch
-   GuardDuty
-   IAM
-   VPC endpoints
-   Network ACLs
-   Security Groups

The infrastructure is therefore represented as reproducible IaC rather
than manually created console resources.

------------------------------------------------------------------------

# 18. Phase 1 --- Normal Deployment

## Prerequisites

Install:

-   Terraform `>= 1.5`
-   AWS CLI
-   An AWS identity with permissions to create the required resources

Verify AWS authentication:

``` powershell
aws sts get-caller-identity
```

Verify Terraform:

``` powershell
terraform version
```

------------------------------------------------------------------------

## Step 1 --- Clone the repository

``` powershell
git clone https://github.com/Tushryadav/Terraform_openwebUI_multiregion_arch.git
cd Terraform_openwebUI_multiregion_arch
```

------------------------------------------------------------------------

## Step 2 --- Create the local variable file

``` powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Generate a strong Open WebUI signing key:

``` powershell
openssl rand -hex 32
```

Put the generated value into:

``` hcl
webui_secret_key = "YOUR_GENERATED_VALUE"
```

**Never commit `terraform.tfvars`.**

------------------------------------------------------------------------

## Step 3 --- Format and validate

``` powershell
terraform fmt -recursive
terraform init
terraform validate
```

------------------------------------------------------------------------

## Step 4 --- Review the plan

``` powershell
terraform plan -out=tfplan
```

Do not blindly apply a plan. Review:

-   Regions
-   VPCs
-   Aurora
-   NAT Gateway
-   ALBs
-   EC2/ASG
-   S3
-   WAF
-   CloudFront
-   Route 53
-   VPC endpoints

------------------------------------------------------------------------

## Step 5 --- Deploy

``` powershell
terraform apply tfplan
```

------------------------------------------------------------------------

## Step 6 --- Check outputs

``` powershell
terraform output
```

For a single output:

``` powershell
terraform output -raw alb_dns_name
```

------------------------------------------------------------------------

## Step 7 --- Verify AWS resources

Check the ALB:

``` powershell
aws elbv2 describe-load-balancers --region us-east-1
```

Check target health:

``` powershell
aws elbv2 describe-target-health --region us-east-1 --target-group-arn <TARGET_GROUP_ARN>
```

Check Auto Scaling:

``` powershell
aws autoscaling describe-auto-scaling-groups --region us-east-1
```

Check Aurora:

``` powershell
aws rds describe-db-clusters --region us-east-1
```

Check Redis:

``` powershell
aws elasticache describe-serverless-caches --region us-east-1
```

Check CloudFront:

``` powershell
aws cloudfront list-distributions
```

------------------------------------------------------------------------

# 19. Phase 2 --- Troubleshooting

Use this phase only when the normal deployment or application does not
behave correctly.

## A. Terraform fails

First:

``` powershell
terraform validate
terraform plan
```

Then check the state:

``` powershell
terraform state list
```

Do **not** immediately delete the entire infrastructure.

Inspect a specific resource:

``` powershell
terraform state show <resource_address>
```

Example:

``` powershell
terraform state show module.portfolio_primary.aws_lb.web
```

------------------------------------------------------------------------

## B. ALB returns 502

Check target health:

``` powershell
aws elbv2 describe-target-health `
  --region us-east-1 `
  --target-group-arn <TARGET_GROUP_ARN>
```

If targets are unhealthy, check the instance/application.

Use Systems Manager instead of opening SSH:

``` powershell
aws ssm start-session --target <INSTANCE_ID>
```

Inside the instance:

``` bash
docker ps
docker logs --tail 200 owui
curl -I http://localhost:8080/
```

If Open WebUI is not running:

``` bash
docker start owui
```

If the container repeatedly crashes:

``` bash
docker logs owui
```

------------------------------------------------------------------------

## C. EC2 is running but Open WebUI is unavailable

Check Docker:

``` bash
systemctl status docker
docker ps -a
```

Check the application:

``` bash
docker logs --tail 200 owui
curl -v http://127.0.0.1:8080/
```

Check the image:

``` bash
docker images
```

Check disk:

``` bash
df -h
```

------------------------------------------------------------------------

## D. Database connection failure

Do not print the secret value.

First verify that the secret exists:

``` powershell
aws secretsmanager describe-secret `
  --region us-east-1 `
  --secret-id portfolio/aurora/master
```

Check Aurora:

``` powershell
aws rds describe-db-clusters `
  --region us-east-1 `
  --query "DBClusters[].{ID:DBClusterIdentifier,Status:Status,Endpoint:Endpoint,Reader:ReaderEndpoint}"
```

From the EC2 instance, verify DNS resolution:

``` bash
getent hosts <AURORA_ENDPOINT>
```

Verify TCP connectivity:

``` bash
nc -vz <AURORA_ENDPOINT> 5432
```

------------------------------------------------------------------------

## E. Redis connection failure

Check the serverless cache:

``` powershell
aws elasticache describe-serverless-caches `
  --region us-east-1
```

From EC2:

``` bash
nc -vz <REDIS_ENDPOINT> 6379
```

Check Open WebUI logs:

``` bash
docker logs --tail 200 owui
```

------------------------------------------------------------------------

## F. EC2 is not appearing in the target group

Check Auto Scaling:

``` powershell
aws autoscaling describe-auto-scaling-groups `
  --region us-east-1 `
  --query "AutoScalingGroups[].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize}"
```

Check EC2 instances:

``` powershell
aws ec2 describe-instances `
  --region us-east-1 `
  --filters "Name=tag:Name,Values=*" `
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,PrivateIP:PrivateIpAddress}"
```

Then check ALB target health.

------------------------------------------------------------------------

# 20. Regional Disaster Recovery Procedure

If `us-east-1` is unavailable and `us-east-2` must become active:

## Step 1 --- Confirm the failure

Do not fail over because of one unhealthy EC2 instance.

Confirm:

-   ALB health
-   EC2/ASG status
-   Aurora status
-   AWS regional/service status
-   CloudWatch alarms

------------------------------------------------------------------------

## Step 2 --- Check Aurora Global Database

``` powershell
aws rds describe-global-clusters `
  --region us-east-1 `
  --global-cluster-identifier portfolio-aurora-global
```

Confirm the secondary cluster is present in `us-east-2`.

------------------------------------------------------------------------

## Step 3 --- Promote/fail over the secondary Aurora cluster

Use the appropriate Aurora Global Database failover/switchover operation
for the failure mode.

**Do not run a destructive database operation without first confirming
the replication state and whether the event is planned or unplanned.**

------------------------------------------------------------------------

## Step 4 --- Activate the secondary application

Current Terraform sets the secondary ASG desired capacity to zero.

For an emergency activation, scale it to at least two instances:

``` powershell
aws autoscaling update-auto-scaling-group `
  --region us-east-2 `
  --auto-scaling-group-name <SECONDARY_ASG_NAME> `
  --desired-capacity 2
```

Verify:

``` powershell
aws autoscaling describe-auto-scaling-groups `
  --region us-east-2 `
  --auto-scaling-group-name <SECONDARY_ASG_NAME>
```

------------------------------------------------------------------------

## Step 5 --- Wait for healthy targets

``` powershell
aws elbv2 describe-target-health `
  --region us-east-2 `
  --target-group-arn <SECONDARY_TARGET_GROUP_ARN>
```

Do not route production traffic until the targets are healthy.

------------------------------------------------------------------------

## Step 6 --- Shift Route 53 traffic

Current routing is:

``` text
us-east-1 = 100
us-east-2 = 0
```

For DR:

``` text
us-east-1 = 0
us-east-2 = 100
```

Because these values are Terraform-managed, make the change in Terraform
rather than permanently changing them only in the console.

------------------------------------------------------------------------

# 21. Safe State Management

Terraform state can contain sensitive infrastructure information.

Never commit:

``` text
terraform.tfstate
terraform.tfstate.*
terraform.tfvars
*.tfplan
.env
credentials
*.pem
*.key
```

The repository should contain:

``` text
terraform.tfvars.example
```

but not the real:

``` text
terraform.tfvars
```

The S3 backend must remain private and protected with appropriate IAM
permissions.

------------------------------------------------------------------------

# 22. Recommended Repository Structure

``` text
Terraform_openwebUI_multiregion_arch/
│
├── main.tf
├── terraform.tfvars.example
├── .gitignore
├── .terraform.lock.hcl
├── README.md
│
├── modules/
│   └── portfolio/
│       ├── vpc.tf
│       ├── alb.tf
│       ├── asg.tf
│       ├── ec2.tf
│       ├── aurora.tf
│       ├── redis.tf
│       ├── s3.tf
│       ├── waf.tf
│       ├── cloudwatch.tf
│       ├── endpoints.tf
│       ├── guardduty.tf
│       ├── Iam.tf
│       ├── sg.tf
│       ├── sg_rules.tf
│       ├── nacl.tf
│       ├── outputs.tf
│       ├── variables.tf
│       └── user_data.sh.tftpl
│
└── docs/
    └── evidence/
        ├── alb-health-recovery.png
        └── s3-bucket.png
```

------------------------------------------------------------------------

# 23. What This Project Demonstrates

This project demonstrates practical experience with:

### AWS

-   VPC
-   Subnets
-   Route Tables
-   Internet Gateway
-   NAT Gateway
-   ALB
-   EC2
-   Auto Scaling
-   Aurora PostgreSQL
-   Aurora Global Database
-   ElastiCache
-   S3
-   CloudFront
-   Route 53
-   WAF
-   Secrets Manager
-   KMS
-   IAM
-   SSM
-   CloudWatch
-   CloudTrail
-   GuardDuty
-   VPC Endpoints

### DevOps / IaC

-   Terraform modules
-   Remote state
-   Infrastructure lifecycle management
-   Dependency management
-   Immutable-ish EC2 bootstrapping
-   Application health checks
-   Operational troubleshooting
-   Disaster recovery planning

### Security

-   IAM roles instead of static EC2 credentials
-   Private application/data tiers
-   Secrets Manager
-   KMS
-   WAF
-   Network ACLs
-   Security Groups
-   VPC endpoints
-   S3 public-access blocking
-   CloudTrail
-   GuardDuty

------------------------------------------------------------------------

# 24. Final Architecture Assessment

  Area                            Assessment
  ------------------------------- --------------------------------
  Terraform/IaC                   Strong
  Multi-AZ application            Strong
  Database HA                     Strong
  Cross-region DB DR              Strong foundation
  Network segmentation            Strong
  IAM / secret handling           Good
  Observability                   Good
  WAF/security controls           Good
  Regional application failover   Partially automated
  S3 regional DR                  **Missing CRR**
  HTTPS                           **Needs production hardening**
  Destructive DB/S3 settings      **Needs production hardening**

### Bottom line

This is a **real AWS architecture project**, not just a collection of
Terraform resources. The strongest parts are the separation of
application/data tiers, Aurora Global Database, private AWS-service
connectivity, IAM-based access, WAF, observability, and the operational
recovery workflow.

The main thing you should **not overclaim in interviews** is "fully
automatic disaster recovery." The current implementation is better
described as:

> **Multi-region architecture with Aurora Global Database replication
> and operator-driven regional application failover.**

That description is accurate and defensible.

------------------------------------------------------------------------

## License

This project is provided for learning, portfolio demonstration, and
infrastructure experimentation. Review all security, cost, backup,
encryption, and failover settings before using the configuration for
production workloads.
