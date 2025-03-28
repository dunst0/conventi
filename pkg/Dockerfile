FROM alpine:3.21

RUN apk --no-cache add \
    git \
    jq

COPY conventi.sh /usr/local/bin/

VOLUME /conventi
WORKDIR /conventi

ENTRYPOINT ["conventi.sh"]
CMD [""]
