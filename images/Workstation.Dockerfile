ARG DOCKER_CLI
ARG BASE
FROM ${DOCKER_CLI} AS dockercli
FROM ${BASE}
LABEL devops-quests="true" org.opencontainers.image.version="0.1.0"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends bash bash-completion ca-certificates curl jq vim nano less htop openssh-client openssh-server python3 python3-venv python3-yaml iproute2 iptables procps util-linux git tar gzip busybox && rm -rf /var/lib/apt/lists/*
COPY images/vimrc.local /etc/vim/vimrc.local
RUN python3 -m venv /opt/ansible && /opt/ansible/bin/pip install --no-cache-dir ansible-core==2.21.5
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY bin/kubectl bin/tofu bin/helm /usr/local/bin/
RUN useradd -m -u 1000 -s /bin/bash hacker && mkdir -p /run/sshd /run/dq /srv/site /opt/providers /opt/provider-seed && chown -R 1000:1000 /home/hacker
COPY images/providers.tf /opt/provider-seed/main.tf
RUN cd /opt/provider-seed && tofu providers mirror /opt/providers && rm -rf /opt/provider-seed
COPY images/tofu.tfrc /etc/devops-quests.tfrc
COPY images/entrypoint.sh /usr/local/bin/dq-entrypoint
COPY images/service.py /usr/local/bin/dq-service
COPY images/bashrc /etc/dq-bashrc
COPY images/command-trace.bash /etc/dq-command-trace.bash
COPY images/aliases.json /etc/dq-aliases.json
RUN chmod 755 /usr/local/bin/dq-entrypoint /usr/local/bin/dq-service && printf '\nsource /etc/dq-bashrc\n' >> /home/hacker/.bashrc
RUN python3 -c 'import json,shlex; f=open("/home/hacker/.bashrc","a"); [f.write("alias "+k+"="+shlex.quote(v)+"\n") for k,v in json.load(open("/etc/dq-aliases.json")).items()]'

ENV PATH="/opt/ansible/bin:${PATH}" TF_CLI_CONFIG_FILE=/etc/devops-quests.tfrc LANG=C.UTF-8
WORKDIR /home/hacker
# Each SSH target generates its own host keys at startup.
RUN rm -f /etc/ssh/ssh_host_*
ENTRYPOINT ["/usr/local/bin/dq-entrypoint"]
CMD ["workstation"]
