# Building the binary of the App
# Phase 1 CI: terraform-validate, container-scan (Trivy), deploy-gate
FROM golang:1.24 AS build

WORKDIR /go/src/tasky
COPY . .
RUN go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/src/tasky/tasky


FROM alpine:3.17.0 AS release

WORKDIR /app
COPY --from=build  /go/src/tasky/tasky .
COPY --from=build  /go/src/tasky/assets ./assets
# Include wizexercise.txt (per Application Build & Deployment ticket)
COPY --from=build  /go/src/tasky/wizexercise.txt ./wizexercise.txt
EXPOSE 8080
ENTRYPOINT ["/app/tasky"]


