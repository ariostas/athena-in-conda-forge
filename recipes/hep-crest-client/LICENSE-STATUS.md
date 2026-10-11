# hep-crest-client licensing status: licence text missing

hep-crest-client (https://gitlab.cern.ch/crest-db/pycrest-openapi) declares "Apache 2.0" in its
package metadata (setup.py and pyproject.toml), but the repository has no LICENSE file and the
sources carry no licence headers. conda-forge needs the licence text: the CREST developers have
to add it, as for CrestApi (recipes/crestapi/LICENSE-STATUS.md) and pycrest-client.

This recipe therefore cannot be submitted to conda-forge yet. Until then it is only built
locally.
