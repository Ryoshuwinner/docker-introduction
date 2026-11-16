# Commandes — TP Docker Sécurisation

Toutes les commandes sont copiables directement dans un terminal.  
Prérequis : Docker installé, depuis le répertoire `tp-docker-securisation/`.

---

## 0. Variables communes

```bash
export GH_USER="lcgregorio93"
export DH_USER="lcgregorio93"
export IMG="quiz-docker"
export REPO="tp-docker-securisation"
```

---

## Mission 1 — Audit de l'image initiale

### Build

```bash
docker build \
  -t quiz-docker:initial \
  -f initial/Dockerfile \
  app/
```

### Taille de l'image

```bash
docker images quiz-docker \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
```

### Couches (historique)

```bash
docker history quiz-docker:initial
```

### Utilisateur du processus

```bash
# Démarrer le conteneur
docker run -d --name audit-initial -p 8080:8080 quiz-docker:initial

# Vérifier l'utilisateur
docker exec audit-initial id
docker exec audit-initial whoami
docker inspect audit-initial --format '{{.Config.User}}'

# Arrêter
docker stop audit-initial && docker rm audit-initial
```

### Test fonctionnel

```bash
docker run -d --name test-initial -p 8080:8080 quiz-docker:initial
curl -I http://localhost:8080/
docker stop test-initial && docker rm test-initial
```

### Scan de vulnérabilités (Trivy via Docker)

```bash
# Résumé HIGH et CRITICAL
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image quiz-docker:initial \
  --severity HIGH,CRITICAL \
  --no-progress

# Export JSON (pour comparaison automatique)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image quiz-docker:initial \
  --format json \
  --no-progress \
  --quiet > scans/initial.json
```

---

## Mission 2 — Build et run de l'image sécurisée

### Build sécurisé

```bash
# Prépare le contexte (nginx.conf doit être avec les sources)
BUILD_CTX=$(mktemp -d)
cp -r app/. "$BUILD_CTX/"
cp secure/nginx.conf "$BUILD_CTX/"

docker build \
  -f secure/Dockerfile \
  -t quiz-docker:secure \
  "$BUILD_CTX"

rm -rf "$BUILD_CTX"
```

### Run avec toutes les restrictions de sécurité

```bash
docker run -d \
  --name quiz-secure \
  -p 8081:8080 \
  --memory=64m \
  --cpus=0.5 \
  --pids-limit=50 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /var/cache/nginx:uid=1001,gid=1001,mode=755 \
  --tmpfs /run:uid=1001,gid=1001,mode=755 \
  --tmpfs /tmp \
  --user 1001:1001 \
  quiz-docker:secure
```

### Vérifications de durcissement

```bash
# Test HTTP 200
curl -I http://localhost:8081/

# En-têtes de sécurité
curl -sI http://localhost:8081/ | grep -E "X-Frame|X-Content|X-XSS|Referrer|Permissions|Server"

# Utilisateur
docker exec quiz-secure id

# Configuration runtime (Memory, CPU, CapDrop, ReadOnly)
docker inspect quiz-secure --format \
  'Memory: {{.HostConfig.Memory}}
NanoCpus: {{.HostConfig.NanoCpus}}
PidsLimit: {{.HostConfig.PidsLimit}}
CapDrop: {{.HostConfig.CapDrop}}
ReadonlyRootfs: {{.HostConfig.ReadonlyRootfs}}
SecurityOpt: {{.HostConfig.SecurityOpt}}'

# Tentative d'écriture (doit échouer)
docker exec quiz-secure sh -c 'echo test > /usr/share/nginx/html/hack.txt'

# Statistiques de ressources
docker stats --no-stream quiz-secure

# Vérification absence docker.sock
docker inspect quiz-secure \
  --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' | grep docker.sock || echo "OK — pas de socket monté"

# Nettoyage
docker stop quiz-secure && docker rm quiz-secure
```

---

## Mission 3 — Comparaison avant/après

### Scan de l'image sécurisée

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image quiz-docker:secure \
  --severity HIGH,CRITICAL \
  --no-progress

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image quiz-docker:secure \
  --format json \
  --no-progress \
  --quiet > scans/secure.json
```

### Comparaison des tailles

```bash
docker images quiz-docker \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
```

### Comparaison des couches

```bash
docker inspect quiz-docker:initial --format '{{len .RootFS.Layers}} couches'
docker inspect quiz-docker:secure  --format '{{len .RootFS.Layers}} couches'
```

---

## Mission 4 — Docker Hardened Image (DHI)

### Pull et inspection de l'image Chainguard nginx

```bash
docker pull cgr.dev/chainguard/nginx:latest

# Taille
docker images cgr.dev/chainguard/nginx:latest \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Couches
docker inspect cgr.dev/chainguard/nginx:latest \
  --format '{{len .RootFS.Layers}} couches'

# Utilisateur
docker inspect cgr.dev/chainguard/nginx:latest \
  --format '{{.Config.User}}'

# Shell disponible ? (distroless = non)
docker run --rm --entrypoint sh cgr.dev/chainguard/nginx:latest -c 'echo ok' || echo "Pas de shell"
```

### Scan CVE de la DHI

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image cgr.dev/chainguard/nginx:latest \
  --severity HIGH,CRITICAL \
  --no-progress
```

### Comparaison des 3 images

```bash
docker images \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" \
  | grep -E "REPOSITORY|quiz-docker|chainguard/nginx"
```

---

## Étape 5 — Publication

### Vérification des secrets avant commit

```bash
git grep -rIiE "(token|password|secret|api_key)" -- ':!commandes.md' ':!README.md'
```

### Initialisation Git

```bash
git init
git branch -M main
git add .
git commit -m "TP Docker : sécurisation image et conteneur"
```

### Publication GitHub (avec gh CLI)

```bash
gh repo create "${GH_USER}/${REPO}" --public --source=. --remote=origin
git push -u origin main
```

### Publication GitHub (sans gh CLI — manuellement)

```bash
# 1. Créer le dépôt sur https://github.com/new (nom : tp-docker-securisation, public)
# 2. Puis :
git remote add origin "https://github.com/${GH_USER}/${REPO}.git"
git push -u origin main
```

### Tag et push Docker Hub

```bash
# Connexion (utiliser un Personal Access Token, jamais le mot de passe)
echo "$DOCKERHUB_TOKEN" | docker login -u "$DH_USER" --password-stdin

# Tag
docker tag quiz-docker:initial "${DH_USER}/quiz-docker:initial"
docker tag quiz-docker:secure  "${DH_USER}/quiz-docker:secure"

# Push
docker push "${DH_USER}/quiz-docker:initial"
docker push "${DH_USER}/quiz-docker:secure"
```

### Vérification — pull depuis un état propre

```bash
docker logout
docker pull "${DH_USER}/quiz-docker:secure"
docker run --rm -p 8080:8080 "${DH_USER}/quiz-docker:secure"
curl -I http://localhost:8080/
```

### Visibilité du dépôt GitHub

```bash
gh repo view --json visibility -q .visibility
# Doit retourner : PUBLIC
```
