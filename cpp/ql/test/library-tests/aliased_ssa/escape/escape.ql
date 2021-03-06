import default
import semmle.code.cpp.ssa.internal.ssa.AliasAnalysis
import semmle.code.cpp.ir.IR

predicate shouldEscape(IRAutomaticUserVariable var) {
  exists(string name |
    name = var.getVariable().getName() and
    name.matches("no_%") and
    not name.matches("no_ssa_%")
  )
}

from IRAutomaticUserVariable var
where
  exists(FunctionIR funcIR |
    funcIR = var.getFunctionIR() and
    (
      (shouldEscape(var) and variableAddressEscapes(var)) or
      (not shouldEscape(var) and not variableAddressEscapes(var))
    )
  )
select var
