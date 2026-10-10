# clhep (conda-forge feedstock change)

The clhep feedstock's recipe (`conda-forge/clhep-feedstock`, `recipe/`), at the version Athena
25.0.73 uses (2.4.7.1, the global pinning's), with one change in `build.sh`: CLHEP is built
without conda-forge's `-fvisibility-inlines-hidden`.

GenericFunctions declares `clone()` in its function classes (`FUNCTION_OBJECT_DEF`) and defines
it `inline` in its `.cc` files (`FUNCTION_OBJECT_IMP`). The library exports them through the
vtables only when inline functions are visible; otherwise code outside the library that calls
`clone()` (Athena's LArG4Validation, through the operators that compose functions) fails to
link with undefined references to `Genfun::FunctionComposition::clone() const` and the like.
LCG's CLHEP, which ATLAS uses, exports them.

To be proposed to the feedstock (for 2.4.7.2 too), and upstream to CLHEP (define `clone()`
non-inline, or in the headers).
