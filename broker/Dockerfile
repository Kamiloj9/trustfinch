FROM golang@sha256:2d40d4fc278dad38be0777d5e2a88a2c6dee51b0b29c97a764fc6c6a11ca893c AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/gitlab-enrollment-broker ./cmd/gitlab-enrollment-broker

FROM golang@sha256:2d40d4fc278dad38be0777d5e2a88a2c6dee51b0b29c97a764fc6c6a11ca893c

COPY --from=build /out/gitlab-enrollment-broker /usr/local/bin/gitlab-enrollment-broker
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/gitlab-enrollment-broker"]
