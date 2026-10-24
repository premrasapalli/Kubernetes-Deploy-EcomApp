# Issue #2 — `kustomize` బైనరీ లేదు, కానీ kubectl లో ఉంది

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #2.

## 1. ఏం జరిగింది (Symptom)

```text
zsh:1: command not found: kustomize
```

డిప్లాయ్ స్క్రిప్ట్ `kustomize build` అని పిలిచింది, కానీ మెషీన్‌లో ఆ బైనరీ లేదు.

## 2. అసలు కారణం (Root cause)

`kubectl` లో Kustomize ఇప్పటికే లోపల built-in గా ఉంది (ఇక్కడ v5.7.1).
కానీ విడిగా `kustomize` CLI ఇన్‌స్టాల్ చేయలేదు. స్క్రిప్ట్ విడి బైనరీని
అనుకున్నది.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
kubectl version --client
# Client Version: v1.35.0
# Kustomize Version: v5.7.1

command -v kustomize        # ఏమీ రాలేదు
kubectl kustomize 03-k8s-manifests/overlays/dev | wc -l   # పనిచేసింది
```

## 4. పరిష్కారం (Resolution)

- `05-scripts/03-deploy-app.sh` లో `kustomize build` → `kubectl kustomize` గా మార్చాం.
- `00-preflight.sh` required tools నుండి `kustomize` తీసేశాం.
- Teardown లో `kubectl delete -k` అలాగే ఉంచాం (అది కూడా built-in నే వాడుతుంది).

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

`kubectl kustomize` అనేది kubectl లో **compile అయిన అదే Kustomize engine** ను
నడుపుతుంది. అదే వెర్షన్‌ను `kubectl delete -k` కూడా వాడుతుంది. దీనివల్ల:

- రెండో బైనరీ అవసరం లేదు.
- kubectl వెర్షన్ కి, kustomize వెర్షన్ కి మధ్య version skew రాదు.
- వేరే `kustomize` ఇన్‌స్టాల్ చేస్తే అది kubectl కంటే వేరు వెర్షన్ అయ్యి,
  build చేసిన YAML కి delete చేసే YAML కి తేడా వచ్చే ప్రమాదం ఉంది.

## 6. ధృవీకరణ (Verification)

```text
kubectl kustomize 03-k8s-manifests/overlays/dev
→ 45 resources, 1312 lines, errors లేవు
```

## 7. మళ్లీ రాకుండా (Prevention)

- అన్ని స్క్రిప్ట్‌లలో `kubectl kustomize` నే వాడండి.
- Preflight లో మనం నిజంగా పిలిచే బైనరీలను మాత్రమే check చేయండి.
