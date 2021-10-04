# Original notebook created by the Jupyter Development Team
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
FROM debian:bullseye@sha256:86dddd82dddf445aea3d2ea26af46cebd727bf2f47ed810fa1450a0d79722d55

# github metadata
LABEL org.opencontainers.image.source=https://github.com/uwcip/jupyterhub-base-notebook

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
ARG conda_version="4.10.3"

# miniforge installer patch version
ARG miniforge_patch_number="6"

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
# comes from this page: https://github.com/conda-forge/miniforge/releases
# look for the *-Linux-*.sh.sha256 file
ARG miniforge_checksum="c63907ba0971d2ca9a8775bd7ea48b635b2bdce4838b2f2d3a8e751876849595"

# create the data directory and add symlinks for our NFS mounts
RUN mkdir -p /data && ln -sf /mnt/nfs/jupiter/shared /data/shared && ln -sf /mnt/nfs/neptune/archived /data/archived

RUN apt-get -q update && apt-get -y upgrade && \
    apt-get install -yq --no-install-recommends \
      # ---- cip bastion host equivalencies
      procps psmisc htop screen socat file man manpages \
      nano vim vim-scripts bash zsh git git-lfs psmisc tzdata zip unzip bzip2 gzrt jq make less sqlite3 patch \
      apt-transport-https gnupg-agent gnupg software-properties-common openssh-client \
      python3-dev python3-venv python3-wheel python3-pip python3-setuptools python3-tenacity python3-ujson python3-tabulate python3-tk pycodestyle python3-requests \
      r-base r-base-dev r-cran-rpostgresql r-cran-data.table r-cran-lubridate r-cran-rmarkdown r-cran-tidyverse r-cran-rcurl r-cran-repr \
      # ---- OS dependencies for notebook server that starts but lacks all features ----
      tini cron ssmtp curl wget ca-certificates sudo locales fonts-liberation fonts-dejavu gfortran gcc \
      # ---- OS dependencies for fully functional notebook server ----
      inkscape libsm6 libxext-dev libxrender1 lmodern netcat \
      # ---- nbconvert dependencies ----
      texlive-xetex texlive-fonts-recommended texlive-latex-recommended \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# add postgres libraries
RUN add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql-archive-buster.gpg && \
    apt-get update && apt-get install -yq --no-install-recommends postgresql-client-13 libpq-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
    MINIFORGE_VERSION="${miniforge_version}" \
    JUPYTER_ENABLE_LAB=yes \
    RUN_CRON=yes

# copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# enable prompt color in the skeleton .bashrc before creating the default NB_USER
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

# create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -l -m -s /bin/bash -N -u "${NB_UID}" "${NB_USER}" && \
    mkdir -p "${CONDA_DIR}" && \
    chown "${NB_USER}:${NB_GID}" "${CONDA_DIR}" && \
    chmod g+w /etc/passwd && \
    fix-permissions "${HOME}" && \
    fix-permissions "${CONDA_DIR}"

USER ${NB_UID}
ARG PYTHON_VERSION=3.9

# setup work directory for backward-compatibility
RUN mkdir "/home/${NB_USER}/work" && \
    fix-permissions "/home/${NB_USER}"

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
    if [[ "${PYTHON_VERSION}" != "default" ]]; then conda install --yes python="${PYTHON_VERSION}"; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    conda install --quiet --yes "conda=${CONDA_VERSION}" 'pip' && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# install Jupyter Notebook, Lab, and Hub
# generate a notebook server config
# cleanup temporary files
# correct permissions
RUN conda install --quiet --yes "notebook=6.4.4" "jupyterhub=1.4.2" "jupyterlab=3.1.14" && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    jupyter lab clean && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

EXPOSE 8888

# configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# install cip dependencies
ARG ciptools_version="1.1.0"
RUN pip install --no-cache-dir https://github.com/uwcip/python-ciptools/releases/download/v${ciptools_version}/ciptools-${ciptools_version}.tar.gz \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NB_USER}"

RUN pip install --no-cache-dir \
    # install a little adventure
    "adventure==1.6" \
    # enable interactive SQL in the notebook
    "ipython-sql==0.4.0" \
    # put a little thing in the upper right corner telling you how much memory you're using
    "jupyter-resource-usage==0.6.0" "jupyterlab-system-monitor==0.8.0" \
    # add notebook diff support
    "nbdime==3.1.0" \
    # add git support
    "jupyterlab-git==0.32.4" \
    # add support to show variables
    "lckr-jupyterlab-variableinspector==3.0.9" \
    # share links to running notebooks
    "jupyterlab-link-share==0.2.1" \
    # allow favoriting folders
    "jupyterlab-favorites==3.0.0" \
    # show recent files and folders
    "jupyterlab-recents==3.0.1" \
    # generically build jupyterlab
    && jupyter lab build \
    && rm -rf /home/${NB_USER}/.cache \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NB_USER}" \
    && true

# final cleanups
USER root

# install the adventure script
COPY adventure /usr/local/bin/adventure
RUN chmod a+rx /usr/local/bin/adventure

# copy the ssmtp script
COPY ssmtp.conf /etc/ssmtp/ssmtp.conf

# copy local files as late as possible to avoid cache busting
COPY run-one run-one-constantly start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_notebook_config.py /etc/jupyter/

# fix permissions on /etc/jupyter as root
RUN fix-permissions /etc/jupyter/

# make sure the notebook starts as the notebook user
USER ${NB_UID}
WORKDIR ${HOME}
