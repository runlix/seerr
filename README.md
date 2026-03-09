# Seerr

Kubernetes-native distroless Docker image for [Seerr](https://github.com/seerr-team/seerr) - a media request manager that integrates with Sonarr and Radarr.

## Purpose

Provides a minimal, secure Docker image for running Seerr in Kubernetes environments. Built on the `distroless-runtime` base image with only the dependencies required for Seerr to run.

## Features

- Distroless base (no shell, minimal attack surface)
- Kubernetes-native permissions (no s6-overlay)
- Read-only root filesystem support
- Non-root execution (`20030:20030`)
- Official Seerr runtime contract (`/app/config`, port `5055`, `/api/v1/status`)

## Usage

### Docker

```bash
docker run -d \
  --name seerr \
  -e TZ=UTC \
  -e PORT=5055 \
  -p 5055:5055 \
  -v /path/to/config:/app/config \
  ghcr.io/runlix/seerr:release-latest
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seerr
spec:
  template:
    spec:
      containers:
      - name: seerr
        image: ghcr.io/runlix/seerr:release-latest
        env:
        - name: PORT
          value: "5055"
        ports:
        - containerPort: 5055
        volumeMounts:
        - name: config
          mountPath: /app/config
        securityContext:
          runAsUser: 20030
          runAsGroup: 20030
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: seerr-config
      securityContext:
        fsGroup: 20030
```

## Tags

See [tags.json](tags.json) for available tags.

## Environment Variables

- `PORT`: HTTP listen port (default: `5055`)
- `TZ`: Time zone database value (example: `UTC`)
- `LOG_LEVEL`: Logging level

## Health Check

- `GET /api/v1/status`

## License

MIT (upstream Seerr license)
