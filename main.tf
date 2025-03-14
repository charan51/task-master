provider "aws" {
  region = "us-west-2"  # Change this to your desired region
}

resource "aws_instance" "security_ai" {
  ami           = "ami-0735c191cf914754d" # Update with correct AMI ID
  instance_type = "t2.medium"

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              docker run -d -p 5000:5000 ai-threat-detection
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

