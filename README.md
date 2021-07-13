# jupyterhub base notebook

This builds a container that can be used as a base for any notebook deployed to
JupyterHub. This container sets up JupyterHub and installs an environment that
looks an awful lot like our primary bastion host including operating system
version and installed software. It also installs a basic Python 3 version with
some standard libraries and JupyterLab extensions.

If you update the version of JupyterHub in this container you need to make sure
that it matches the version of JupyterHub installed in the main JupyterHub
container.

## using this container

You could actually run this base notebook directly if you wanted. However, you
should really inherit from this and add additional things. The best example of
that is the [datascience-notebook](https://github.com/uwcip/jupyterhub-datascience-notebook)
which is the standard notebook for [the UW CIP's JupyterHub](https://hub.lab.cip.uw.edu).

## deployment

If you update this container you must tag it and push the changes and the tag
to GitHub to force a new build to happen. When the build finishes successfully
then you will need to update any container that references this container to
reference the new version.
