provider "aws" {
  region = "us-west-2"  # Change this to your desired region
}

variable "aws_region" {
  default = "us-west-2"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_instance" "security_ai" {
  ami           = "ami-0735c191cf914754d" # Update with correct AMI ID
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.security_ai_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              set -e
              set -x

              # Check available disk space
              df -h / || echo "Warning: Could not check disk space"
              
              # Check available memory
              free -h || echo "Warning: Could not check memory"

              # Update and install dependencies
              apt-get update -y
              apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg \
                lsb-release \
                awscli \
                jq

              # Add Docker's official GPG key
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

              # Set up Docker repository
              echo \
                "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

              # Install Docker Engine
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io

              # Start Docker service
              systemctl start docker
              systemctl enable docker

              # Verify Docker is running
              echo "Waiting for Docker to start..."
              for i in {1..30}; do
                if systemctl is-active --quiet docker; then
                  echo "Docker is running"
                  break
                fi
                if [ $i -eq 30 ]; then
                  echo "Docker failed to start"
                  exit 1
                fi
                echo "Waiting for Docker to start (attempt $i/30)..."
                sleep 2
              done

              # Verify Docker works
              docker run --rm hello-world || {
                echo "Docker test failed"
                systemctl status docker
                journalctl -xe --no-pager | tail -n 50
                exit 1
              }

              # Get AWS region and account ID
              AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
              AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | grep -o '"accountId" *: *"[^"]*"' | cut -d'"' -f4)
              REPOSITORY_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/threat-detection"

              # Login to ECR
              echo "Logging into ECR..."
              aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI

              # Pull and run the container
              echo "Pulling container image..."
              docker pull $REPOSITORY_URI:latest

              echo "Running container..."
              docker run -d --name threat-detection \
                --restart always \
                -p 5000:5000 \
                $REPOSITORY_URI:latest

              # Check if container is running
              echo "Verifying container is running..."
              sleep 5  # Give the container a moment to start
              if [ "$(docker ps -q -f name=threat-detection)" ]; then
                  echo "Container started successfully"
                  docker ps
                  docker logs threat-detection
              else
                  echo "Container failed to start"
                  docker ps -a
                  docker logs threat-detection
                  exit 1
              fi
              EOF

  tags = {
    Name = "Security-AI-Instance"
  }
}

resource "aws_codepipeline" "pipeline" {
  name     = "threat-detection-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_store.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "charan51/task-master"
        BranchName      = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner          = "AWS"
      provider       = "CodeBuild"
      input_artifacts = ["source_output"]
      version        = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }
}

resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}

resource "aws_s3_bucket" "artifact_store" {
  bucket = "threat-detection-artifacts"
}

resource "aws_s3_bucket_versioning" "artifact_store" {
  bucket = aws_s3_bucket.artifact_store.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_codebuild_project" "build" {
  name         = "threat-detection-build"
  description  = "Builds threat detection application"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                      = "aws/codebuild/standard:5.0"
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = "us-west-2"  # Change this to your desired region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = "418295714127"  # Replace with your AWS account ID
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "threat-detection"
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_security_group" "security_ai_sg" {
  name        = "security-ai-sg"
  description = "Security group for AI threat detection instance"

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound traffic to AI service"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security-ai-sg"
  }
}

resource "aws_ecr_repository" "threat_detection" {
  name                 = "threat-detection"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "threat-detection-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "threat-detection-ec2-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "threat-detection-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

