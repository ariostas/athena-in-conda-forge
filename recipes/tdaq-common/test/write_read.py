"""Write an EventStorage file of random events with eformat's python bindings, read it back."""

import sys

import eformat

N = 5
filename = sys.argv[1]
eformat.dummy.make_file(filename, N)
events = list(eformat.istream(filename))
assert len(events) == N, len(events)
for event in events:
    event.check_tree()
print(f"python: {len(events)} events, {sum(e.nchildren() for e in events)} ROBs")
