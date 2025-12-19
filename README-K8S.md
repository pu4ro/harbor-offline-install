# Harbor와 Kubernetes 통합 가이드

이 문서는 K8s 클러스터에서 Harbor를 private registry로 사용하는 방법을 설명합니다.

## K8s에서 Harbor 사용

### 1. imagePullSecret 생성

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<Harbor-Admin-Password> \
  --namespace=default
```

다른 네임스페이스에서 사용하려면:
```bash
# 모든 네임스페이스에 secret 생성
for ns in default kube-system kube-public; do
  kubectl create secret docker-registry harbor-registry \
    --docker-server=192.168.1.100 \
    --docker-username=admin \
    --docker-password=<password> \
    --namespace=$ns
done
```

### 2. Pod에서 Harbor 이미지 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app-container
    image: 192.168.1.100/library/my-app:latest
  imagePullSecrets:
  - name: harbor-registry
```

### 3. Deployment 예제

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: 192.168.1.100/library/my-app:v1.0
        ports:
        - containerPort: 8080
      imagePullSecrets:
      - name: harbor-registry
```

### 4. ServiceAccount에 imagePullSecret 설정

전역으로 사용하려면:

```bash
# default ServiceAccount에 추가
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "harbor-registry"}]}' \
  -n default
```

이제 해당 네임스페이스의 모든 Pod가 자동으로 Harbor를 사용할 수 있습니다.

### 5. 클라이언트 시스템에 CA 인증서 추가

HTTPS를 사용하는 경우, K8s 노드에 Harbor CA 인증서를 추가:

```bash
# 각 K8s 노드에서 실행
sudo ./add-harbor-ca.sh ca.crt 192.168.1.100
```

또는 Makefile 사용:
```bash
sudo make add-ca
```

## 클라이언트 시스템 설정

Harbor를 사용할 모든 시스템에서 CA 인증서를 추가해야 합니다.

### CA 인증서 배포

**Harbor 서버에서 CA 인증서 복사**:
```bash
# Harbor 서버에서
scp harbor-certs/ca.crt user@client-system:/tmp/
```

**클라이언트 시스템에서 CA 추가**:
```bash
# add-harbor-ca.sh 스크립트 사용 (권장)
sudo ./add-harbor-ca.sh /tmp/ca.crt 192.168.1.100
```

또는 수동 설치:

**RHEL/CentOS**:
```bash
sudo cp /tmp/ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt
sudo update-ca-trust
```

**Ubuntu/Debian**:
```bash
sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
sudo update-ca-certificates
```

**nerdctl/containerd 사용 시**:
```bash
# CA 인증서를 시스템에 추가한 후
sudo systemctl restart containerd
```

### 연결 테스트

```bash
# Harbor 로그인 테스트
docker login 192.168.1.100
# 또는
nerdctl login 192.168.1.100

# 이미지 Push/Pull 테스트
docker pull nginx:latest
docker tag nginx:latest 192.168.1.100/library/nginx:latest
docker push 192.168.1.100/library/nginx:latest
```

## 자동화된 CA 배포

여러 클라이언트 시스템에 CA를 배포하려면:

```bash
# hosts.txt 파일 생성 (한 줄에 하나씩 호스트 입력)
cat > hosts.txt << 'HOSTS_EOF'
node1.example.com
node2.example.com
node3.example.com
HOSTS_EOF

# 모든 호스트에 CA 배포
while read host; do
  echo "Deploying CA to $host..."
  scp harbor-certs/ca.crt add-harbor-ca.sh root@$host:/tmp/
  ssh root@$host "chmod +x /tmp/add-harbor-ca.sh && /tmp/add-harbor-ca.sh /tmp/ca.crt 192.168.1.100"
done < hosts.txt
```

## containerd 런타임 설정 (K8s 노드)

K8s 노드에서 containerd를 사용하는 경우:

### 1. Harbor를 insecure registry로 설정 (HTTP 사용 시)

```bash
sudo vi /etc/containerd/config.toml
```

다음 섹션 추가:
```toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100".tls]
    insecure_skip_verify = true
```

또는 HTTPS + CA 사용:
```toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100".tls]
    ca_file = "/etc/pki/ca-trust/source/anchors/harbor-ca.crt"
```

```bash
sudo systemctl restart containerd
```

### 2. crictl로 테스트

```bash
# Harbor 이미지 Pull 테스트
sudo crictl pull 192.168.1.100/library/nginx:latest

# 이미지 목록 확인
sudo crictl images | grep 192.168.1.100
```

## Harbor 프로젝트 관리

### 1. 프로젝트 생성

웹 UI 또는 API로 프로젝트 생성:

```bash
# API를 사용한 프로젝트 생성
curl -X POST "http://192.168.1.100/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:<password>" \
  -d '{
    "project_name": "myproject",
    "metadata": {
      "public": "false"
    }
  }'
```

### 2. 사용자 추가

```bash
# 사용자 생성
curl -X POST "http://192.168.1.100/api/v2.0/users" \
  -H "Content-Type: application/json" \
  -u "admin:<password>" \
  -d '{
    "username": "developer",
    "email": "dev@example.com",
    "password": "DevPassword123!",
    "realname": "Developer User"
  }'
```

### 3. 프로젝트에 사용자 추가

```bash
# 프로젝트 멤버 추가
curl -X POST "http://192.168.1.100/api/v2.0/projects/myproject/members" \
  -H "Content-Type: application/json" \
  -u "admin:<password>" \
  -d '{
    "role_id": 2,
    "member_user": {
      "username": "developer"
    }
  }'
```

역할 ID:
- 1: Project Admin
- 2: Developer
- 3: Guest
- 4: Maintainer

## Harbor Replication (이미지 복제)

다른 Harbor 인스턴스나 Docker Hub와 이미지 동기화:

### 1. Replication Endpoint 생성

웹 UI: Administration → Registries → New Endpoint

### 2. Replication Rule 생성

웹 UI: Administration → Replications → New Replication Rule

### 3. 수동 복제 실행

웹 UI에서 또는 API로:

```bash
curl -X POST "http://192.168.1.100/api/v2.0/replication/executions" \
  -H "Content-Type: application/json" \
  -u "admin:<password>" \
  -d '{
    "policy_id": 1
  }'
```

## Harbor 백업 및 복원 (K8s 고려사항)

K8s에서 Harbor를 사용할 때 백업 전략:

### 1. Harbor 데이터 백업

```bash
cd /opt/harbor
sudo docker-compose down
sudo tar -czf harbor-backup-$(date +%Y%m%d).tar.gz /data
sudo docker-compose up -d
```

### 2. K8s imagePullSecrets 백업

```bash
# 모든 네임스페이스의 secrets 백업
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get secret harbor-registry -n $ns -o yaml > harbor-secret-$ns.yaml 2>/dev/null || true
done
```

### 3. 복원 시 imagePullSecrets 재생성

```bash
# 백업된 secrets 복원
for file in harbor-secret-*.yaml; do
  kubectl apply -f $file
done
```

## 모니터링 및 로깅

### 1. Harbor 메트릭 수집 (Prometheus)

`.env` 파일에서:
```bash
ENABLE_METRICS=true
```

Prometheus scrape 설정:
```yaml
scrape_configs:
  - job_name: 'harbor'
    static_configs:
      - targets: ['192.168.1.100:9090']
```

### 2. Harbor 로그 확인

```bash
# 모든 컨테이너 로그
cd /opt/harbor
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f harbor-core
docker-compose logs -f harbor-jobservice
```

### 3. K8s에서 Harbor 사용 모니터링

```bash
# ImagePull 오류 확인
kubectl get events --all-namespaces | grep -i "failed to pull"

# Pod 상태 확인
kubectl get pods --all-namespaces | grep ImagePullBackOff
```

## 문제 해결

### Harbor에서 이미지를 Pull할 수 없는 경우

1. **imagePullSecret 확인**:
   ```bash
   kubectl get secret harbor-registry -n <namespace>
   ```

2. **CA 인증서 확인** (HTTPS 사용 시):
   ```bash
   # 노드에서 CA 확인
   trust list | grep -i harbor
   ```

3. **containerd 설정 확인**:
   ```bash
   sudo cat /etc/containerd/config.toml | grep -A5 "192.168.1.100"
   ```

4. **노드에서 직접 테스트**:
   ```bash
   sudo crictl pull 192.168.1.100/library/nginx:latest
   ```

### 인증 오류

```bash
# imagePullSecret 재생성
kubectl delete secret harbor-registry -n <namespace>
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<correct-password> \
  --namespace=<namespace>
```

## 참고 자료

- Harbor 공식 문서: https://goharbor.io/docs/
- Kubernetes 문서: https://kubernetes.io/docs/
- Harbor API 문서: http://192.168.1.100/devcenter-api-2.0
