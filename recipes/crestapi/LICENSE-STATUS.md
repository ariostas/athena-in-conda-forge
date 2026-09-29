# CrestApi licensing status: unresolved

CrestApi (https://gitlab.cern.ch/crest-db/CrestApi) has no LICENSE file. Its sources carry
the usual ATLAS header, "Copyright (C) 2002-2026 CERN for the benefit of the ATLAS
collaboration", without naming a licence. Athena itself, which carries the same header, is
Apache-2.0, and chai, CrestApi's companion library from the same group, ships an Apache-2.0
LICENSE, so Apache-2.0 is the likely answer, but it has to be confirmed by the CREST
developers.

This recipe therefore cannot be submitted to conda-forge yet. Until then it is only built
locally.
