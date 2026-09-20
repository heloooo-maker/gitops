# ArgoCD — cluster longvan-test

ArgoCD instance riêng, cài bằng Helm, quản lý app `lab-thanhlam` (namespace `argocd-thanhlam`).
Tách biệt khỏi ArgoCD dùng chung khác trong cluster (namespace `argocd`).

## Cài mới / tái tạo lại từ đầu (bootstrap, chỉ 1 lần)

Chicken-and-egg: chưa có ArgoCD nào chạy thì không có gì tự sync được cả, nên bước
đầu tiên bắt buộc làm tay:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd-thanhlam

helm install argocd argo/argo-cd \
  -n argocd-thanhlam \
  --version 10.9.2 \
  -f values.yaml
```

Lưu ý (đều đã nằm sẵn trong `values.yaml`, không cần `--set` tay nữa):
- `crds.install: false` — CRD `applications.argoproj.io` đã tồn tại sẵn trong cluster (do 1 ArgoCD khác cài trước), tránh giành quyền sở hữu CRD dùng chung.
- `nameOverride: argocd-thanhlam` — bắt buộc phải khác `argocd` (giá trị mặc định của Chart), tránh trùng tên `ClusterRole`/`ClusterRoleBinding` với ArgoCD khác đã có trong cluster.
- `configs.params."server.insecure"=true` — để ArgoCD server chạy HTTP thuần nội bộ, vì HTTPS thật được xử lý ở tầng Cloudflare Tunnel/Edge phía trước, không phải ở chính ArgoCD.
- `server.ingress.*` — Ingress cho chính ArgoCD server, do chart tự render (không còn file `ingress.yaml` viết tay riêng nữa).

Sau bước cài tay này, apply tiếp `platform/bootstrap/root-application.yaml` (nếu
chưa có) rồi tới AppProject/ApplicationSet trong `platform/bootstrap/` — lúc đó
`platform-repo-appset.yaml` sẽ nhận diện `platform/argocd/chart.yaml` và tạo ra
Application `argocd` quản lý chính release Helm này.

## Upgrade khi cần đổi values

**Không cần `helm upgrade` tay nữa** — sau bước cài lần đầu ở trên, ArgoCD tự quản lý
chính nó (self-management) qua Application `argocd` (sinh ra từ `platform-repo-appset.yaml`
+ `platform/argocd/chart.yaml` + `values.yaml`). Sửa `values.yaml` hoặc đổi
`targetRevision` trong `chart.yaml` rồi push lên `main`, ArgoCD sẽ tự sync/upgrade
chính nó.

**Cẩn thận:** đây là control plane quản lý toàn bộ cluster này — sửa sai
`targetRevision` hoặc `values.yaml` ở đây có thể ảnh hưởng luôn cả ArgoCD lẫn mọi
Application khác nó đang quản lý.

## Lấy mật khẩu admin lần đầu

```bash
kubectl -n argocd-thanhlam get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
