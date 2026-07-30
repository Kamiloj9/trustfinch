FROM golang@sha256:2d40d4fc278dad38be0777d5e2a88a2c6dee51b0b29c97a764fc6c6a11ca893c AS build

ARG TARGETOS=linux
ARG TARGETARCH=arm64

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -tags lambda.norpc -ldflags='-s -w' -o /out/bootstrap ./cmd/iam-enrollment-broker

FROM public.ecr.aws/lambda/provided@sha256:2fcf0536e6073a518343a84b52690f648df43a1c5d262d8e09f2ed33b29df179

COPY --from=build /out/bootstrap ${LAMBDA_TASK_ROOT}/bootstrap
