# pycrest-client licensing status: licence text missing

pycrest-client (https://gitlab.cern.ch/crest-db/crest-client) declares "Apache 2.0" in its
package metadata (pyproject.toml), but the repository has no LICENSE file and the
sources carry no licence headers. conda-forge needs the licence text: the CREST developers have
to add it, as for CrestApi (recipes/crestapi/LICENSE-STATUS.md) and hep-crest-client.

This recipe therefore cannot be submitted to conda-forge yet. Until then it is only built
locally.
