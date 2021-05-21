# Original notebook created by the Jupyter Development Team
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
FROM debian:buster-slim@sha256:f077cd32bfea6c4fa8ddeea05c53b27e90c7fad097e2011c9f5f11a8668f8db4 AS base

ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
WORKDIR /tmp

# ---- Miniforge installer ----
# default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
# check https://github.com/conda-forge/miniforge/releases

# conda version
ARG conda_version="4.10.0"

# miniforge installer patch version
ARG miniforge_patch_number="0"

# miniforge installer architecture
ARG miniforge_arch="x86_64"

# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
ARG miniforge_python="Mambaforge"

# miniforge archive to install
ARG miniforge_version="${conda_version}-${miniforge_patch_number}"

# miniforge installer
ARG miniforge_installer="${miniforge_python}-${miniforge_version}-Linux-${miniforge_arch}.sh"

# miniforge checksum
ARG miniforge_checksum="c56cc2da96043688c6bdb521d825de27754de0a342d5228ba3155cd94532ff75"

# install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -q update \
 && apt-get install -yq --no-install-recommends curl wget ca-certificates sudo locales fonts-liberation fonts-dejavu gfortran gcc \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# configure locales
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER \
    CONDA_VERSION="${conda_version}" \
    MINIFORGE_VERSION="${miniforge_version}"

# copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

# create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -l -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

USER $NB_UID
ARG PYTHON_VERSION=3.7

# setup work directory for backward-compatibility
RUN mkdir "/home/$NB_USER/work" && \
    fix-permissions "/home/$NB_USER"

# install conda as jovyan and check the sha256 sum provided on the download site
# prerequisites installation: conda, mamba, pip, tini
RUN wget --quiet "https://github.com/conda-forge/miniforge/releases/download/${miniforge_version}/${miniforge_installer}" && \
    echo "${miniforge_checksum} *${miniforge_installer}" | sha256sum --check && \
    /bin/bash "${miniforge_installer}" -f -b -p $CONDA_DIR && \
    rm "${miniforge_installer}" && \
    # conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes "conda=${CONDA_VERSION}" "pip" "tini=0.18.0" && \
    conda update --all --quiet --yes && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# install Jupyter Notebook, Lab, and Hub
# generate a notebook server config
# cleanup temporary files
# correct permissions
RUN conda install --quiet --yes "notebook=6.3.0" "jupyterhub=1.4.1" "jupyterlab=3.0.15" && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

EXPOSE 8888

# configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# copy local files as late as possible to avoid cache busting
COPY run-one run-one-constantly start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_notebook_config.py /etc/jupyter/

# fix permissions on /etc/jupyter as root
USER root

RUN fix-permissions /etc/jupyter/

# install all OS dependencies for fully functional notebook server
RUN apt-get update && apt-get install -yq --no-install-recommends \
      build-essential nano vim vim-scripts bash zsh git git-lfs psmisc tzdata zip unzip bzip2 gzrt jq make less sqlite3 patch \
      apt-transport-https gnupg-agent gnupg software-properties-common openssh-client \
      inkscape libsm6 libxext-dev libxrender1 lmodern netcat socat \
      # ---- nbconvert dependencies ----
      texlive-xetex texlive-fonts-recommended texlive-plain-generic \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# install base software that is present on the bastion host
RUN apt-get update && apt-get install -yq --no-install-recommends \
      procps psmisc htop screen \
      python3-dev python3-venv python3-wheel python3-pip python3-setuptools python3-tenacity python3-ujson python3-tabulate python3-tk pycodestyle \
      r-base r-base-dev r-cran-rpostgresql r-cran-data.table r-cran-lubridate r-cran-rmarkdown r-cran-tidyverse r-cran-rcurl r-cran-repr \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# add postgres libraries
RUN add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
    apt-get update && apt-get install -yq --no-install-recommends \
      postgresql-client-13 libpq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# create the data directory for shared data to exist
RUN mkdir -p /data \
 && ln -sf /mnt/nfs/jupiter/shared /data/shared \
 && ln -sf /home /data/home \
 && true

# do not let the container start as root
USER $NB_UID

FROM base AS builder

# going to clone our things from uwcip
# this happens in this side-container to avoid leaking credentials
ARG GIT_USERNAME
ENV GIT_USERNAME=$GIT_USERNAME
ARG GIT_PASSWORD
ENV GIT_PASSWORD=$GIT_PASSWORD
RUN mkdir -p /tmp/uwcip && \
    git config --global credential.helper '!f() { sleep 1; echo "username=${GIT_USERNAME}"; echo "password=${GIT_PASSWORD}"; }; f' && \
    git clone --depth 1 --recurse-submodules --shallow-submodules --branch v1.2.1 https://github.com/uwcip/ciptools.git /tmp/uwcip/ciptools

FROM base AS final

COPY --from=builder --chown=$NB_UID:$NB_GID /tmp/uwcip /tmp/uwcip

# install cip dependencies
RUN pip install --no-cache-dir \
      /tmp/uwcip/ciptools \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NB_USER}" \
    && rm -rf /tmp/uwcip

RUN pip install --no-cache-dir \
    # install a little adventure
    "adventure==1.6" \
    # enable interactive SQL in the notebook
    "ipython-sql==0.4.0" \
    # put a little thing in the upper right corner telling you how much memory you're using
    "jupyter-resource-usage==0.6.0" "jupyterlab-system-monitor==0.8.0" \
    # add notebook diff support
    "nbdime==3.0.0" \
    # add git support
    "jupyterlab-git==0.30.1" \
    # add support to show variables
    "lckr-jupyterlab-variableinspector==3.0.9" \
    && jupyter lab build \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NB_USER}" \
    && true

# install the adventure script
USER root
COPY adventure /usr/local/bin/adventure
RUN chmod a+rx /usr/local/bin/adventure

# make sure the notebook starts as the notebook user
USER $NB_UID
WORKDIR $HOME