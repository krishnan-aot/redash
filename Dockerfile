FROM node:12 as frontend-builder

# Controls whether to build the frontend assets
ARG skip_frontend_build

ENV CYPRESS_INSTALL_BINARY=0
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

RUN useradd -m -d /frontend redash
USER redash

WORKDIR /frontend
COPY --chown=redash package.json package-lock.json /frontend/
COPY --chown=redash viz-lib /frontend/viz-lib

# Controls whether to instrument code for coverage information
ARG code_coverage
ENV BABEL_ENV=${code_coverage:+test}

RUN if [ "x$skip_frontend_build" = "x" ] ; then npm ci --unsafe-perm; fi

COPY --chown=redash client /frontend/client
COPY --chown=redash webpack.config.js /frontend/
RUN if [ "x$skip_frontend_build" = "x" ] ; then npm run build; else mkdir -p /frontend/client/dist && touch /frontend/client/dist/multi_org.html && touch /frontend/client/dist/index.html; fi
FROM python:3.7-slim

EXPOSE 5000

# Controls whether to install extra dependencies needed for all data sources.
ARG skip_ds_deps
# Controls whether to install dev dependencies.
ARG skip_dev_deps

RUN useradd --create-home redash

# Ubuntu packages
FROM ubuntu:18.04
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y gnupg
RUN apt-get install -y build-essential
RUN apt-get install -y pwgen
RUN apt-get install -y libffi-dev
RUN apt-get install -y sudo
RUN apt-get install -y git-core
RUN apt-get install -y wget
RUN apt-get install -y # Postgres client
RUN apt-get install -y libpq-dev
RUN apt-get install -y # ODBC support:
RUN apt-get install -y g++ unixodbc-dev
RUN apt-get install -y # for SAML
RUN apt-get install -y xmlsec1
RUN apt-get install -y # Additional packages required for data sources:
RUN apt-get install -y libssl-dev
RUN apt-get install -y default-libmysqlclient-dev
RUN apt-get install -y freetds-dev
RUN apt-get install -y libsasl2-dev
RUN apt-get install -y unzip
RUN apt-get install -y libsasl2-modules-gssapi-microsoft
RUN apt-get install -y curl && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN apt-get install -y curl && curl https://packages.microsoft.com/config/debian/10/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
  ACCEPT_EULA=Y apt-get install -y msodbcsql17 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ARG databricks_odbc_driver_url=https://databricks.com/wp-content/uploads/2.6.10.1010-2/SimbaSparkODBC-2.6.10.1010-2-Debian-64bit.zip
ADD $databricks_odbc_driver_url /tmp/simba_odbc.zip
RUN unzip /tmp/simba_odbc.zip -d /tmp/ \
  && dpkg -i /tmp/SimbaSparkODBC-*/*.deb \
  && echo "[Simba]\nDriver = /opt/simba/spark/lib/64/libsparkodbc_sb64.so" >> /etc/odbcinst.ini \
  && rm /tmp/simba_odbc.zip \
  && rm -rf /tmp/SimbaSparkODBC*

WORKDIR /app

# Disalbe PIP Cache and Version Check
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1

# Use legacy resolver to work around broken build due to resolver changes in pip
ENV PIP_USE_DEPRECATED=legacy-resolver

# We first copy only the requirements file, to avoid rebuilding on every file
# change.
COPY requirements.txt requirements_bundles.txt requirements_dev.txt requirements_all_ds.txt ./
RUN if [ "x$skip_dev_deps" = "x" ] ; then pip install -r requirements.txt -r requirements_dev.txt; else pip install -r requirements.txt; fi
RUN if [ "x$skip_ds_deps" = "x" ] ; then pip install -r requirements_all_ds.txt ; else echo "Skipping pip install -r requirements_all_ds.txt" ; fi

COPY . /app
COPY --from=frontend-builder /frontend/client/dist /app/client/dist
RUN chown -R redash /app
USER redash

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["server"]
