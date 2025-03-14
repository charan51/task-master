# CloudSecure

A cloud-based security solution using AI for threat detection.

## Setup Instructions

1. Deploy the infrastructure using Terraform:
   ```bash
   terraform init
   terraform apply
   ```

2. Configure the GitHub connection:
   - Go to the AWS Console
   - Navigate to Developer Tools > Settings > Connections
   - Find the connection named "github-connection"
   - Click on "Update pending connection"
   - Follow the prompts to authorize AWS to access your GitHub repository

3. After the connection is established, the CodePipeline will automatically start building and deploying the application.

## Architecture

- AWS CodePipeline for CI/CD
- AWS CodeBuild for building Docker containers
- EC2 instance for running the AI threat detection service
- S3 bucket for artifact storage

## Security

This project implements:
- IAM roles with least privilege access
- S3 bucket versioning
- Secure Docker container configuration