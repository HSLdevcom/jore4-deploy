FROM hsldevcom/azure-ansible:1.2.1

# install some missing ansible packages
RUN set -x \
  && python3 -m pip install --upgrade --user psycopg2-binary \
  && ansible-galaxy collection install community.postgresql
