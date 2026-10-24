# Documentation Index

Read in this order when learning, or jump by phase when building.

| Doc | When to read |
|---|---|
| `ARCHITECTURE.md` | Before building — understand components and why they exist |
| `ISSUES.md` | Every time something breaks — and study past issues |
| `RUNBOOK.md` | During debugging — copy/paste commands and decision trees |
| `LEARNINGS.md` | After each phase — capture your own notes |
| `te/` | Telugu explanations, one file per phase |

## Conventions

- **English docs**: canonical technical truth.
- **`te/` docs**: same content explained in Telugu with analogies; keep them in sync.
- **Issue IDs**: `Issue #1`, `#2`, ... never reuse. Reference them from commits and docs.

## Telugu explanation standard (mandatory)

Every file we create gets a companion doc in `docs/te/` following `_TEMPLATE.md`:

1. Purpose of the file (and which team owns it)
2. Full file contents
3. **Line-by-line Telugu explanation** (field -> meaning -> what breaks if wrong)
4. Why these exact values (trade-offs)
5. Common mistakes
6. Verification commands + expected output
7. Related issues

Example entry for an HTTPRoute:

```text
parentRefs  -> ఏ Gateway కి attach అవ్వాలో; app team Gateway మార్చకుండా reference మాత్రమే.
hostnames   -> ఏ domain కి route; production లో నిజమైన domain.
matches     -> PathPrefix "/" అంటే అన్ని paths.
backendRefs -> ఏ Service కి, ఏ port కి పంపాలి.
```

Short Telugu block comments are still allowed at the top of manifests, but the
full explanation lives in `docs/te/` so manifests stay clean.

## తెలుగు

- ముందుగా `ARCHITECTURE.md` చదవండి — ఏ కాంపోనెంట్ ఎందుకు ఉందో తెలుస్తుంది.
- ఏదైనా పని చేయకపోతే `ISSUES.md` చూడండి; కొత్త సమస్య వచ్చినప్పుడు అదే ఫార్మాట్‌లో నమోదు చేయండి.
- డీబగ్ చేసేటప్పుడు `RUNBOOK.md` లోని కమాండ్లు వాడండి.
- తెలుగు వివరణలు `docs/te/` లో ఫేజ్ ప్రకారం ఉంటాయి.
