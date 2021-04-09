FROM hsldevcom/azure-ansible:1.2.1

# install some missing packages to azure-ansible image
USER root
RUN set -x \
  && apt-get update \
  && apt-get install --no-install-recommends -y postgresql-client=12+214ubuntu0.1 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER ansible
