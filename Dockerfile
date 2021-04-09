FROM hsldevcom/azure-ansible:1.2.1

# install some missing ansible packages
RUN set -x \
  && python3 -m pip install --no-cache-dir --upgrade --user psycopg2-binary==2.8.6 \
  && ansible-galaxy collection install community.postgresql
