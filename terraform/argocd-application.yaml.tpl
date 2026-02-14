apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tasky
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/name: tasky
    app.kubernetes.io/part-of: wiz-exercise
spec:
  project: default
  source:
    repoURL: ${repo_url}
    targetRevision: ${git_revision}
    path: kubernetes
    kustomize:
      images:
        - tasky:latest=${tasky_image}
  destination:
    server: https://kubernetes.default.svc
    namespace: tasky
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: ""
      kind: Secret
      jsonPointers:
        - /data
