#!/bin/bash
# Raw data (ByteStream): an EventStorage file of random events written with tdaq-common's
# eformat, listed and copied with Athena's ByteStream tools.
set -euo pipefail
python -c "import eformat; eformat.dummy.make_file('events.data', 3)"
AtlListBSEvents -s -c -l events.data | tee list.log
AtlCopyBSEvent -e all -o copy.data events.data | tee copy.log
AtlListBSEvents -c -l copy.data | tee list_copy.log
# the same three events, with the same sizes, in both files
grep "Copied all events to file copy.data" copy.log
test "$(grep -c "^Index=" list.log)" = 3
diff <(grep "^Index=" list.log | sed "s/ Offset=.*//") <(grep "^Index=" list_copy.log | sed "s/ Offset=.*//")
