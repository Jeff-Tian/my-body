terraform {
  required_version = ">= 1.6.0"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
  }

  # Remote state on HCP Terraform (Terraform Cloud) free tier.
  # Create the org + workspace once, then CI only needs TF_API_TOKEN.
  cloud {
    organization = "brickverse"

    workspaces {
      name = "my-body-dns"
    }
  }
}

provider "vercel" {
  # api_token is read from env var VERCEL_API_TOKEN in CI.
  # team     is read from env var VERCEL_TEAM_ID  (optional; leave unset for personal account).
}
