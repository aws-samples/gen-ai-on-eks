# Install JupyterHub

## Apply Karpenter provisioner

```bash
kubectl apply -f karpenter-provisioner-jupyter-hub.yaml
```

## Install JupyterHub

```bash
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

helm upgrade --cleanup-on-fail \
  --install jupyterhub-on-karpenter jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --create-namespace \
  --version=2.0.0 \
  --values config.yaml
```

### Get proxy URL

```bash
kubectl --namespace jupyterhub get service proxy-public
```