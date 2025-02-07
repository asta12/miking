include "tuning/tune-options.mc"

-- Options type
type Options = {
  toJVM : Bool,
  debugParse : Bool,
  debugGenerate : Bool,
  debugTypeAnnot : Bool,
  debugTypeCheck : Bool,
  debugProfile : Bool,
  debugShallow : Bool,
  debugPhases : Bool,
  exitBefore : Bool,
  disablePruneExternalUtests : Bool,
  disablePruneExternalUtestsWarning : Bool,
  runTests : Bool,
  runtimeChecks : Bool,
  disableOptimizations : Bool,
  useTuned : Bool,
  compileAfterTune : Bool,
  accelerate : Bool,
  accelerateTensorMaxRank : Int,
  debugAccelerate : Bool,
  cpuOnly : Bool,
  use32BitIntegers : Bool,
  use32BitFloats : Bool,
  keepDeadCode : Bool,
  printHelp : Bool,
  toJavaScript : Bool,
  jsTarget : String,
  disableJsGeneralOptimizations : Bool,
  disableJsTCO : Bool,
  output : Option String,
  tuneOptions : TuneOptions
}
