# ArgoCD — cluster longvan-test

ArgoCD instance riêng, cài bằng Helm, quản lý app `lab2` (namespace `argocd-thanhlam`).
Tách biệt khỏi ArgoCD dùng chung khác trong cluster (namespace `argocd`).

## Cài mới / tái tạo lại từ đầu

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd-thanhlam

helm install argocd argo/argo-cd \
  -n argocd-thanhlam \
  -f argocd/values.yaml \
  --set crds.install=false \
  --set nameOverride=argocd-thanhlam
```

Lưu ý:
- `crds.install=false` — CRD `applications.argoproj.io` đã tồn tại sẵn trong cluster (do 1 ArgoCD khác cài trước), tránh giành quyền sở hữu CRD dùng chung.
- `nameOverride=argocd-thanhlam` — bắt buộc phải khác `argocd` (giá trị mặc định của Chart), tránh trùng tên `ClusterRole`/`ClusterRoleBinding` với ArgoCD khác đã có trong cluster.
- `configs.params."server.insecure"=true` (trong `argocd/values.yaml`) — để ArgoCD server chạy HTTP thuần nội bộ, vì HTTPS thật được xử lý ở tầng Cloudflare Tunnel/Edge phía trước, không phải ở chính ArgoCD.

## Upgrade khi cần đổi values

```bash
helm upgrade argocd argo/argo-cd \
  -n argocd-thanhlam \
  -f argocd/values.yaml \
  --set crds.install=false \
  --set nameOverride=argocd-thanhlam
```

## Lấy mật khẩu admin lần đầu

```bash
kubectl -n argocd-thanhlam get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
