# [TELUGU EXPLANATION]
# PURPOSE      : అన్ని issues ని log చేయడానికి master file
# WHAT IT DOES : Issue #1, #2,... అన్నీ strict format లో record చేస్తుంది
# WHY ENTERPRISE: RCA, Fix, Why-only-this-works document చేయడం enterprise culture
# HOW TO USE   : ప్రతీ issue ఎదురైనప్పుడు ఈ format లో fill చేసి append చేయాలి
# NOTES        : ఏ issue ను కొట్టిపారేయకూడదు. Break-Fix mindset కి ఇది బాగా ఉపయోగపడుతుంది

# ISSUES.md - retailx Issue Tracker (Strict Format)

> **Rule:** ప్రతీ real blocker కి క్రింది format తప్పనిసరిగా follow చేయాలి. "Fixed" అనడం మాత్రమే సరిపోదు. **Why this only works** explain చేయాలి.

## Template (Copy this for new issue)

```markdown
## Issue #<N>: <Short Descriptive Name>

### Environment
- Cluster: AWS EKS 1.36
- Region: us-east-1
- CNI: Cilium
- Account Type: AWS Free Tier (Learning)
- Date: YYYY-MM-DD
- Context: Phase X - <File/Step Name>

### Issue
<Error message / Symptom (kubectl describe/get/events/logs) in Telugu+English>

### Root Cause
<సాంకేతిక కారణం స్పష్టంగా రాయండి>

### Investigation
<Commands used | Observations | Initial assumption vs Actual>

### Resolution
<Step by step commands/manifests. ప్రతి command కి Telugu explanation if needed>

### Why this only works
<Enterprise angle. ఎందుకు ఈ పరిష్కారం మాత్రమే పని చేస్తుంది? Dependency ఏంటి?>

### Verification
<Proof: kubectl outputs, curl, hubble observe, logs>

### Prevention
<మళ్ళీ ఇలా జరగకూడదంటే future లో ఏమి గుర్తుంచుకోవాలి?>

### Cost Impact (If any)
<Free-Tier కి impact ఉందా? (Yes/No + వివరాలు)>
```

## Issues Log

*(Phase 0 నుండి issues start అవుతాయి. ఇక్కడ ఒక్కొక్క issue ని append చేస్తూ పోతాము)*
