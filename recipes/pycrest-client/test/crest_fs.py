"""A tag with its metadata written by the file-system flavour of the CREST API and read back.

The models (generated with pydantic) take their fields by their JSON names.
"""

import json
import tempfile

from hep.crest.client.models import TagDto, TagMetaDto
from pycrest.api.crest_fs_api import CrestApiFs

api = CrestApiFs(tempfile.mkdtemp())
tag = TagDto(
    name="TEST-TAG-01",
    timeType="time",
    payloadSpec="JSON",
    synchronization="ALL",
    description="a test tag",
    lastValidatedTime=0,
    endOfValidity=0,
)
api.create_tag(tag)
meta = TagMetaDto(
    tagName="TEST-TAG-01",
    description="its metadata",
    chansize=1,
    colsize=1,
    tagInfo=json.dumps({"channel_list": [{"0": "channel"}]}),
)
api.create_tag_meta(meta)

back = api.find_tag("TEST-TAG-01")
assert back.name == "TEST-TAG-01" and back.description == "a test tag", back
back_meta = api.find_tag_meta("TEST-TAG-01")
assert json.loads(back_meta.tag_info) == {"channel_list": [{"0": "channel"}]}, back_meta
print("tag and metadata read back:", back.name, back_meta.description)
