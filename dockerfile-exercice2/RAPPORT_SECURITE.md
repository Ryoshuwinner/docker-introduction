# Rapport de sécurité — TP Docker : Audit et durcissement d'image

**Application :** quiz-docker (application web statique Vite + nginx)  
**Date :** 2026-11-16  
**Outil de scan :** Trivy 0.76 (aquasec/trivy via Docker)

---

## Mission 1 — Audit de l'image initiale

### 1.1 État initial (`quiz-docker:initial`)

| Critère | Valeur |
|---|---|
| **Image de base** | `nginx:stable-alpine` (nginx 1.30.6, Alpine 3.24.4) |
| **Taille de l'image** | 62,4 MB |
| **Utilisateur runtime** | `appuser` (uid=100, gid=102) |
| **Port exposé** | 8080 (non-privilégié) |
| **Couches réelles** | 12 (27 entrées dans `docker history`) |
| **CVE CRITICAL** | 0 |
| **CVE HIGH** | 3 |
| **Digest épinglé** | ✗ (tag flottant `nginx:stable-alpine`) |
| **HEALTHCHECK** | ✗ |
| **Headers de sécurité HTTP** | ✗ |
| **Multi-stage build** | ✓ |
| **npm ci** | ✓ |
| **.dockerignore** | ✓ (partiel) |

### 1.2 Résultats bruts du scan Trivy (quiz-docker:initial)

```
quiz-docker:initial (alpine 3.24.4)
====================================
Total: 3 (HIGH: 3, CRITICAL: 0)

Library  Vulnerability    Severity  Status  Installed  Fixed      Title
libxslt  CVE-2026-125350  HIGH      fixed   1.1.43-r3  1.1.43-r4  Use after free in XML
libxslt  CVE-2026-87636   HIGH      fixed   1.1.43-r3  1.1.43-r4  Type confusion in XML
libxslt  CVE-2026-9947    HIGH      fixed   1.1.43-r3  1.1.43-r4  Use after free in XML
```

### 1.3 Couches (`docker history quiz-docker:initial`)

```
IMAGE          CREATED     CREATED BY                                            SIZE
11b2f938e217   ~1h ago     CMD ["nginx" "-g" "daemon off;"]                      0B
<missing>      ~1h ago     USER appuser                                          0B
<missing>      ~1h ago     EXPOSE [8080/tcp]                                     0B
<missing>      ~1h ago     RUN mkdir -p /var/cache/nginx/... && chown ...        18.7kB
<missing>      ~1h ago     RUN sed -i ... && ln -sf ...                          1.07kB
<missing>      ~1h ago     COPY /app/dist /usr/share/nginx/html                 17.1kB
<missing>      ~1h ago     RUN addgroup ... && adduser ...                       3.25kB
<missing>      10d ago     RUN apkArch... (installation nginx officielle)        49.6MB
<missing>      10d ago     ENV ACME_VERSION / NJS_VERSION / NGINX_VERSION        0B
<missing>      10d ago     ENTRYPOINT + COPY scripts entrypoint nginx            11.8kB
<missing>      10d ago     RUN addgroup -g 101 nginx...                          4.3MB
<missing>      10d ago     ADD alpine-minirootfs-3.24.4...                       8.43MB
```

### 1.4 L'image est-elle prête pour la production ?

**Non, pas telle quelle.** Les 3 CVE HIGH dans `libxslt` ont un correctif disponible et non appliqué. Les tags ne sont pas épinglés par digest, ce qui rend les builds non reproductibles. Il manque un healthcheck et des en-têtes de sécurité HTTP.

### 1.5 Composants nécessaires à l'exécution

L'application est un **site statique** (HTML + CSS + JS compilés par Vite). En production, seuls trois éléments sont requis :

1. Les fichiers `dist/` issus du build Vite (< 25 KB)
2. Un serveur HTTP pour les servir (nginx suffit)
3. L'OS minimal fourni par Alpine Linux

Node.js, npm, `node_modules` et le code source **ne sont pas nécessaires** dans l'image finale. Le multi-stage build existant s'en charge déjà.

### 1.6 Risques de sécurité identifiés

| # | Risque | Sévérité | Description |
|---|---|---|---|
| 1 | **CVE dans libxslt** | HIGH | 3 vulnérabilités (use-after-free, type confusion) dans libxslt 1.1.43-r3. Exploitables via traitement de XML/XSLT malicieux. Correctif disponible : r4. |
| 2 | **Tags flottants** | MOYENNE | `nginx:stable-alpine` sans digest SHA256 : un attaquant contrôlant le registry peut substituer une image malveillante. Les builds ne sont pas reproductibles. |
| 3 | **Pas de HEALTHCHECK** | FAIBLE | Docker ne peut pas détecter automatiquement une application bloquée pour la redémarrer. |
| 4 | **Pas d'en-têtes HTTP de sécurité** | FAIBLE | Absence de `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, etc. Facilite le clickjacking et le sniffing de contenu. |
| 5 | **Version nginx exposée** | FAIBLE | `server_tokens` non désactivé : nginx révèle sa version dans les réponses HTTP (`Server: nginx/1.30.6`), aide la reconnaissance d'attaquants. |
| 6 | **.dockerignore incomplet** | FAIBLE | Les fichiers `.env`, `*.pem`, `*.key` ne sont pas explicitement exclus. Un fichier de secrets ajouté par inadvertance serait copié dans l'image. |
| 7 | **Pas de limites runtime** | VARIABLE | Sans `--memory`, `--cpus`, `--cap-drop`, `--read-only`, un conteneur compromis peut consommer toutes les ressources de l'hôte ou escalader ses privilèges. |

### 1.7 Améliorations prioritaires

1. **Patcher libxslt** (risque immédiat avec CVE connues et fixées)
2. **Épingler les images par digest SHA256** (reproductibilité et intégrité de la supply chain)
3. **Appliquer des limites runtime** (`--cap-drop ALL`, `--read-only`, `--memory`, `--cpus`)
4. **Ajouter un HEALTHCHECK** (résilience opérationnelle)
5. **Ajouter les en-têtes HTTP de sécurité** et désactiver `server_tokens`

---

## Mission 2 — Durcissement appliqué

### 2.1 Mesures implémentées dans `Dockerfile.secure`

| Mesure | Avant | Après | Fichier modifié |
|---|---|---|---|
| **Image de base épinglée** | `nginx:stable-alpine` (tag) | `nginx:stable-alpine@sha256:901e59…` (digest) | `Dockerfile.secure` |
| **Image builder épinglée** | `node:20-alpine` (tag) | `node:20-alpine@sha256:fb4cd1…` (digest) | `Dockerfile.secure` |
| **Patch libxslt** | r3 (3 CVE HIGH) | r4 via `apk upgrade --no-cache` | `Dockerfile.secure` |
| **UID/GID fixes** | uid=100 (alloué dynamiquement) | uid=1001, gid=1001 (explicites) | `Dockerfile.secure` |
| **Pas de shell ni home** | `-S appuser` (shell par défaut) | `-H -s /sbin/nologin appuser` | `Dockerfile.secure` |
| **npm --ignore-scripts** | absent | `npm ci --ignore-scripts` | `Dockerfile.secure` |
| **HEALTHCHECK** | absent | `wget -qO- http://localhost:8080/` | `Dockerfile.secure` |
| **Config nginx dédiée** | sed en place | Fichier `nginx.conf` copié via COPY | `nginx.conf` |
| **En-têtes HTTP sécurité** | absents | X-Frame-Options, X-Content-Type-Options, XSS-Protection, Referrer-Policy, Permissions-Policy | `nginx.conf` |
| **server_tokens off** | on (version exposée) | off | `nginx.conf` |
| **.dockerignore étendu** | 4 règles | 20+ règles (env, pem, key, IDE, logs, Dockerfile) | `.dockerignore` |

### 2.2 Commande `docker run` avec limites runtime

```bash
docker run -d \
  --name quiz-secure \
  -p 8080:8080 \
  --memory=64m \
  --cpus=0.5 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /var/cache/nginx:uid=1001,gid=1001 \
  --tmpfs /run:uid=1001,gid=1001 \
  --tmpfs /tmp \
  quiz-docker:secure
```

| Option | Rôle |
|---|---|
| `--memory=64m` | Plafonne la RAM à 64 Mo ; empêche un DoS par épuisement mémoire |
| `--cpus=0.5` | Limite à 0,5 cœur CPU |
| `--cap-drop ALL` | Supprime toutes les capabilities Linux (y compris `SETUID`, `SETGID`, `NET_BIND_SERVICE`) |
| `--security-opt no-new-privileges:true` | Empêche le processus d'acquérir de nouveaux privilèges via setuid/setgid |
| `--read-only` | Monte le système de fichiers du conteneur en lecture seule |
| `--tmpfs /var/cache/nginx` | nginx a besoin d'écrire ses fichiers temporaires ; on lui donne un tmpfs dédié |
| `--tmpfs /run` | nginx écrit son PID dans `/run/nginx.pid` |
| `--tmpfs /tmp` | Répertoire temporaire générique en RAM |

> **Règle d'or :** ne jamais monter `/var/run/docker.sock` dans un conteneur — cela revient à donner un accès root à l'hôte.

---

## Mission 3 — Comparaison avant / après

### 3.1 Tableau de comparaison

| Critère | `quiz-docker:initial` | `quiz-docker:secure` | Évolution |
|---|---|---|---|
| **Taille** | 62,4 MB | 62,8 MB | +0,4 MB (patch libxslt) |
| **Couches réelles** | 12 | 13 | +1 (apk upgrade) |
| **CVE CRITICAL** | 0 | 0 | = |
| **CVE HIGH** | 3 | **0** | ✅ −3 |
| **Image épinglée (digest)** | ✗ | ✓ | ✅ |
| **UID/GID fixes** | uid=100 | uid=1001 | ✅ |
| **Shell utilisateur** | `/bin/sh` (défaut) | `/sbin/nologin` | ✅ |
| **npm --ignore-scripts** | ✗ | ✓ | ✅ |
| **HEALTHCHECK** | ✗ | ✓ | ✅ |
| **En-têtes HTTP sécurité** | ✗ | ✓ (5 en-têtes) | ✅ |
| **server_tokens** | on | off | ✅ |
| **.dockerignore** | 4 règles | 20+ règles | ✅ |
| **Limites runtime** | aucune | memory/CPU/cap/ro/no-new-privs | ✅ |

### 3.2 Vérification fonctionnelle

Les deux images répondent `HTTP 200` sur `http://localhost:8080/` avec le même contenu applicatif. L'image `:secure` ajoute en plus les en-têtes de sécurité dans chaque réponse HTTP.

```
HTTP/1.1 200 OK
Server: nginx                        ← version masquée (server_tokens off)
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: no-referrer
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

### 3.3 Résultats Trivy après durcissement

```
quiz-docker:secure (alpine 3.24.4)
====================================
Total: 0 (HIGH: 0, CRITICAL: 0)   ← 0 vulnérabilité
```

### 3.4 Push vers Docker Hub

```bash
# Se connecter
docker login

# Taguer l'image avec votre nom d'utilisateur Docker Hub
docker tag quiz-docker:secure <VOTRE_USERNAME>/quiz-docker:secure

# Pousser
docker push <VOTRE_USERNAME>/quiz-docker:secure
```

> Remplacez `<VOTRE_USERNAME>` par votre identifiant Docker Hub.  
> Fournissez-le à Kiro pour exécuter le push automatiquement.

---

## Récapitulatif des fichiers produits

| Fichier | Description |
|---|---|
| `Dockerfile.secure` | Dockerfile durci avec digests épinglés, patch CVE, UID fixe, HEALTHCHECK |
| `nginx.conf` | Configuration nginx minimaliste avec en-têtes de sécurité, server_tokens off |
| `.dockerignore` | Liste d'exclusions étendue (secrets, IDE, logs, Dockerfiles) |
| `RAPPORT_SECURITE.md` | Ce rapport (audit + comparaison + notes de durcissement) |
