ARG KIND
FROM ${KIND}
LABEL devops-quests="true" org.opencontainers.image.version="0.1.0"
COPY images/kind-entrypoint.sh /usr/local/bin/dq-kind-entrypoint
RUN chmod 755 /usr/local/bin/dq-kind-entrypoint
ENTRYPOINT ["/usr/local/bin/dq-kind-entrypoint", "/sbin/init"]
