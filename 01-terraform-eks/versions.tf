# ── తెలుగు వివరణ ─────────────────────────────────────────────
# ఈ ఫైల్ ఏ టెర్రాఫార్మ్ వెర్షన్ మరియు ప్రొవైడర్లు కావాలో చెబుతుంది.
# వెర్షన్ పిన్ చేయడం enterprise లో తప్పనిసరి — అందరికీ ఒకే ఫలితం వస్తుంది.
# ─────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Lab లో local state. Production లో S3 + DynamoDB lock వాడాలి (docs/ARCHITECTURE.md).
}
