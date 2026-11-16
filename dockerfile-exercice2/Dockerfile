# ─────────────────────────────────────────────
# STAGE 1 : build
# ─────────────────────────────────────────────
FROM node:20-alpine AS builder


WORKDIR /app

# Cela exploite le cache Docker
COPY package.json package-lock.json ./

# "npm ci" est préféré à "npm install" en CI/CD :
# - installe exactement ce qui est dans package-lock.json
# - échoue si package-lock.json est absent ou incohérent
RUN npm ci

# Copie le reste du code source seulement maintenant
COPY . .

# Compile l'application
RUN npm run build


# ─────────────────────────────────────────────
# STAGE 2 : run
# ─────────────────────────────────────────────
FROM nginx:stable-alpine

# On crée un utilisateur dédié avec UID fixe.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /app/dist /usr/share/nginx/html

# Configure nginx pour écouter sur 8080 (port non-privilégié)
# et redirige les logs vers stdout/stderr.
RUN sed -i 's/listen\s*80;/listen 8080;/g; s/listen\s*\[::\]:80;/listen [::]:8080;/g' \
        /etc/nginx/conf.d/default.conf && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# PERMISSIONS NON-ROOT POUR NGINX
# nginx a besoin d'écrire dans ces répertoires au démarrage.
# On les crée et on les donne à appuser PENDANT le build (en root),
# pour que le processus puisse tourner sans droits élevés à l'exécution.
RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \

    # /run est un symlink vers /var/run sur Alpine.
    # nginx écrit son PID dans /run/nginx.pid par défaut.
    # On lui donne les droits en écriture sur /run.

    chown -R appuser:appgroup \
             /var/cache/nginx \
             /run \
             /var/log/nginx \
             /usr/share/nginx/html \
             /etc/nginx/conf.d && \
    chmod -R 755 /usr/share/nginx/html


# Les ports < 1024 nécessitent les droits root.
EXPOSE 8080

# Bascule sur l'utilisateur non-root pour l'exécution
USER appuser

CMD ["nginx", "-g", "daemon off;"]
