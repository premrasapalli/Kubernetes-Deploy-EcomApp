# Issue #3 — HTTPRoute లో containerPort ఇచ్చాం, Service port కాదు

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #3.
> ఇది డిప్లాయ్‌కు ముందు manifest review లో పట్టుబడింది (apply చేయలేదు).

## 1. ఏం జరిగింది (Symptom)

`04-platform/gateway-api/httproute.yaml` లో frontend backend:

```yaml
backendRefs:
  - name: frontend
    port: 8080
```

కానీ frontend Service:

```yaml
ports:
  - name: http
    port: 80
    targetPort: http   # pod లో 8080
```

అంటే Route `frontend:8080` అని వెతుకుతుంది. అలాంటి Service port లేదు →
Gateway నుంచి `503` / connection refused వచ్చేది.

## 2. అసలు కారణం (Root cause)

Gateway API లో `backendRefs[].port` అంటే **Service port**, pod `containerPort` కాదు.
మనం `frontend.yaml` లోని `containerPort: 8080` ను చూసి ఇక్కడ పెట్టేశాం.
Service మాత్రం `port: 80` మాత్రమే బయటకు చూపుతుంది.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
kubectl kustomize 03-k8s-manifests/overlays/dev | grep -A10 'name: frontend'
# Service: port 80, targetPort http
grep -n 'port:' 04-platform/gateway-api/httproute.yaml
# frontend backendRef: 8080  ← జత కలవలేదు
```

## 4. పరిష్కారం (Resolution)

```yaml
backendRefs:
  - name: frontend
    port: 80
```

మిగిలిన మూడు (product 8081, cart 8082, order 8083) సరిగ్గా ఉన్నాయి —
ఎందుకంటే వాటి Service port = container port.

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

- Envoy ట్రాఫిక్ పంపేది `<service>.<namespace>.svc:<port>` కి.
- Cilium/kube-proxy **Service port** ను మాత్రమే `targetPort` కి మారుస్తుంది;
  `containerPort` ను నేరుగా చూడదు.
- frontend Service `80` మాత్రమే publish చేస్తుంది, కాబట్టి `80` ఇవ్వడమే ఒకే సరైన మార్గం.
- `targetPort: http` అనే పేరు ద్వారా pod లో 8080 కి చేరుతుంది — ఆ పని Service చేస్తుంది, Route కాదు.

## 6. ధృవీకరణ (Verification)

```text
Gateway -> /  → 200, server: envoy
HTTPRoute conditions: Accepted=True, ResolvedRefs=True
```

## 7. మళ్లీ రాకుండా (Prevention)

- నియమం: `backendRefs.port` ఎప్పుడూ `Service.spec.ports[].port` కి సమానం అయ్యుండాలి.
- CI లో Kustomize render చేసి, HTTPRoute backend ports ను Service ports తో ఆటోమేటిక్‌గా పోల్చండి.
- Service port != containerPort ఉన్నప్పుడు పేరు (`name`) ద్వారా reference ఇవ్వడం మంచిది.
