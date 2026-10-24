# Issue #4 — Helm తెలియని Cilium values ను నిశ్శబ్దంగా వదిలేసింది

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #4.

## 1. ఏం జరిగింది (Symptom)

`04-platform/cilium/values.yaml` లో ఇవి రాశాం:

```yaml
externalIPs:
  enabled: true
loadBalancer:
  IPAM:
    enabled: true
```

`helm template` విజయవంతం అయింది, ఎలాంటి warning రాలేదు. కానీ render అయిన
ConfigMap లో ఆ సెట్టింగ్‌లు లేవు.

## 2. అసలు కారణం (Root cause)

Cilium **1.20** chart లో ఆ keys ఇక లేవు. Helm ఏదైనా values ను తీసుకుంటుంది,
కానీ chart templates లో వాడని keys ను **మౌనంగా throw away** చేస్తుంది.
Schema validation లేదు, warning లేదు. పాత బ్లాగ్/post నుంచి కాపీ చేసిన keys
ఇలా నిజంగా పనిచేయని చోట కూడా "పనిచేస్తోంది" అనే భ్రమ కలిగిస్తాయి.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
helm show values cilium/cilium --version 1.20.2 | grep -i externalIP
# externalIPs block లేదు

helm template ... | grep -i 'external-ips\|enable-lb-ipam'
# enable-lb-ipam: "true" మాత్రమే కనిపించింది (chart default)

grep -rn 'enable-external-ips' /tmp/cilium-chart/cilium/templates
# ఏమీ లేదు → key rename కాదు, పూర్తిగా తీసేశారు
```

## 4. పరిష్కారం (Resolution)

ఆ రెండు బ్లాక్‌లను `values.yaml` నుంచి తీసేశాం:

- LB IPAM 1.20 లో డిఫాల్ట్‌గా ఆన్ (`enableLBIPAM: true`).
- L2 announcements కి `externalIPs` toggle అవసరం లేదు.

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

Cilium agent ఏమి చేయాలో **render అయిన ConfigMap** చూసి నిర్ణయిస్తుంది.
`values.yaml` లో ఉన్నా, render లోకి రాకపోతే దాని ప్రభావం సున్నా.
అందుకే "మనం enable చేశాం" అనుకోవడం కాకుండా, render అయిన ఫైల్‌లో
`enable-lb-ipam: "true"` ఉందా అని check చేయడమే సరైన పద్ధతి.

## 6. ధృవీకరణ (Verification)

```text
helm template ... → exit 0, 37 resources
render లో: enable-lb-ipam: "true", enable-l2-announcements: "true"
Gateway VIP కి externalIPs అవసరం లేదు
```

## 7. మళ్లీ రాకుండా (Prevention)

- Values మార్చిన ప్రతిసారీ `helm template` చేసి, మీరు ఆన్ చేసినట్టు అనుకున్న
  setting render లో ఉందా అని `grep` చేయండి.
- Chart వెర్షన్‌ను pin చేసి, upgrade సమయంలో `helm show values` తో diff చేయండి.
- పాత బ్లాగ్‌ల నుంచి keys కాపీ చేయకండి; chart defaults నే నమ్మండి.
