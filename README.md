# Seerr

Kubernetes-native distroless Docker image for [Seerr](https://github.com/seerr-team/seerr), built and published through the shared CI v3 workflow stack in [`runlix/build-workflow`](https://github.com/runlix/build-workflow).

## Published Image

- Image: `ghcr.io/runlix/seerr`
- Current stable tag example: `ghcr.io/runlix/seerr:3.1.0-stable`
- Current debug tag example: `ghcr.io/runlix/seerr:3.1.0-debug`

The authoritative published tags, digests, and source revision are recorded in [release.json](release.json).

## Branch Layout

- `main`: documentation, release metadata, and automation configuration
- `release`: Dockerfiles, CI wrappers, smoke tests, and build inputs

Normal release flow:
1. changes land on `release`
2. `Publish Release` builds and publishes the images
3. the workflow opens a sync PR back to `main`
4. `main` records the published result in `release.json`

## Usage

### Docker

```bash
docker run -d \
  --name seerr \
  -e TZ=UTC \
  -e PORT=5055 \
  -p 5055:5055 \
  -v /path/to/config:/app/config \
  ghcr.io/runlix/seerr:3.1.0-stable
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
          image: ghcr.io/runlix/seerr:3.1.0-stable
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

## Environment Variables

- `PORT`: HTTP listen port (default: `5055`)
- `TZ`: time zone database value
- `LOG_LEVEL`: application log level

## Health Check

- `GET /api/v1/status`

## License

MIT
