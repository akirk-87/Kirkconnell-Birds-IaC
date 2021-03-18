# Backend.hcl
bucket         = "terraform-kirkconnell-birds-state"
region         = "us-east-2"
dynamodb_table = "terraform-kirkconnel-birds-locks"
encrypt        = true