# clhep (conda-forge feedstock change)

The clhep feedstock's recipe (`conda-forge/clhep-feedstock`, `recipe/`), at the version Athena
25.0.73 uses (2.4.7.1, the global pinning's), with two changes:

- `build.sh`: CLHEP is built without conda-forge's `-fvisibility-inlines-hidden` (build 1);
- `patches/0001`: RandGaussZiggurat draws its uniform random numbers in double precision, as in
  ATLAS's fork of CLHEP (build 2).

GenericFunctions declares `clone()` in its function classes (`FUNCTION_OBJECT_DEF`) and defines
it `inline` in its `.cc` files (`FUNCTION_OBJECT_IMP`). The library exports them through the
vtables only when inline functions are visible; otherwise code outside the library that calls
`clone()` (Athena's LArG4Validation, through the operators that compose functions) fails to
link with undefined references to `Genfun::FunctionComposition::clone() const` and the like.
LCG's CLHEP, which ATLAS uses, exports them.

To be proposed to the feedstock (for 2.4.7.2 too), and upstream to CLHEP (define `clone()`
non-inline, or in the headers).

RandGaussZiggurat's `ziggurat_UNI()` returns the engine's `flat()` as a `float`, which rounds
values just below 1.0 up to 1.0; the tail of the distribution (`ziggurat_nfix()`, in the
library) then computes `log(1.0 - 1.0)`, raising division-by-zero and invalid-operation
exceptions, and draws a different number of random numbers from the engine than it would with
the exact value. ATLAS's fork (`CLHEP_2_4_7_1_atl01`, ATR-26831) returns a `double`. ATLAS's
simulation shares Geant4's engine with code that draws from RandGaussZiggurat (transition
radiation in the TRT), so where this happens the rest of the event follows a different random
sequence from ATLAS's release. (It is not the only difference: with the fix, the simulation of
`athena-sim` still differs from ATLAS's release after a few Geant4 steps and still raises
floating point exceptions; see the main README.) The fork's other
changes (the tables as constants rather than `thread_local` variables, RandBinomial's members
protected) do not change results; Athena's core patch 0001 handles the latter. The fix changes
no interface: the function is only used inside the library. To be proposed upstream to CLHEP
and to the feedstock.
