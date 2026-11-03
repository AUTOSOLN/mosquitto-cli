To build mosquitto_sub, mosquitto_pub and mosquitto_rr in dist/ per architecture:

$ docker run --privileged --rm tonistiigi/binfmt --install arm,arm64

$ docker buildx build   --platform linux/amd64,linux/arm64,linux/arm/v7 --output type=local,dest=dist .
