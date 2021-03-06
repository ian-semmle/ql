/**
 * INTERNAL: Do not use.
 *
 * Provides classes for resolving delegate calls.
 */

import csharp
private import semmle.code.csharp.dataflow.CallContext
private import semmle.code.csharp.dataflow.DataFlow::DataFlow::Internal
private import semmle.code.csharp.dispatch.Dispatch
private import semmle.code.csharp.frameworks.system.linq.Expressions

/** A source of flow for a delegate expression. */
private class DelegateFlowSource extends DataFlow::ExprNode {
  Callable c;

  DelegateFlowSource() {
    this.getExpr() = any(Expr e |
      c = e.(AnonymousFunctionExpr) or
      c = e.(CallableAccess).getTarget().getSourceDeclaration()
    )
  }

  /** Gets the callable that is referenced in this delegate flow source. */
  Callable getCallable() {
    result = c
  }
}

/** A sink of flow for a delegate expression. */
private abstract class DelegateFlowSink extends DataFlow::ExprNode {
  /**
   * Gets an actual run-time target of this delegate call in the given call
   * context, if any. The call context records the *last* call required to
   * resolve the target, if any. Example:
   *
   * ```
   * public int M(Func<string, int> f, string x) {
   *   return f(x);
   * }
   *
   * void M2() {
   *   M(x => x.Length, y);
   *
   *   M(_ => 42, z);
   *
   *   Func<int, bool> isZero = x => x == 0;
   *   isZero(10);
   * }
   * ```
   *
   * - The call on line 2 can be resolved to either `x => x.Length` (line 6)
   *   or `_ => 42` (line 8) in the call contexts from lines 7 and 8,
   *   respectively.
   * - The call on line 11 can be resolved to `x => x == 0` (line 10) in an
   *   empty call context (the call is locally resolvable).
   *
   * Note that only the *last* call required is taken into account, hence if
   * `M` above is redefined as follows:
   *
   * ```
   * public int M(Func<string, int> f, string x) {
   *   return M2(f, x);
   * }
   *
   * public int M2(Func<string, int> f, string x) {
   *   return f(x);
   * }
   *
   * void M2() {
   *   M(x => x.Length, y);
   *
   *   M(_ => 42, z);
   *
   *   Func<int, bool> isZero = x => x == 0;
   *   isZero(10);
   * }
   * ```
   *
   * then the call context from line 2 is the call context for all
   * possible delegates resolved on line 6.
   */
  cached
  Callable getARuntimeTarget(CallContext context) {
    exists(DelegateFlowSource dfs |
      flowsFrom(this, dfs, _, context) and
      result = dfs.getCallable()
    )
  }
}

/** A delegate call expression. */
library class DelegateCallExpr extends DelegateFlowSink {
  DelegateCall dc;

  DelegateCallExpr() {
    this.getExpr() = dc.getDelegateExpr()
  }

  /** Gets the delegate call that this expression belongs to. */
  DelegateCall getDelegateCall() {
    result = dc
  }
}

/** A delegate expression that is passed as the argument to a library callable. */
library class DelegateArgumentToLibraryCallable extends Expr {
  DelegateType dt;
  Call call;

  DelegateArgumentToLibraryCallable() {
    exists(Callable callable, Parameter p |
      this = call.getArgumentForParameter(p) and
      callable = call.getTarget() and
      callable.fromLibrary() and
      dt = p.getType().(SystemLinqExpressions::DelegateExtType).getDelegateType()
    )
  }

  /** Gets the call that this argument belongs to. */
  Call getCall() {
    result = call
  }

  /** Gets the delegate type of this argument. */
  DelegateType getDelegateType() {
    result = dt
  }

  /**
   * Gets an actual run-time target of this delegate call in the given call
   * context, if any. The call context records the *last* call required to
   * resolve the target, if any. Example:
   */
  Callable getARuntimeTarget(CallContext context) {
    exists(DelegateArgumentToLibraryCallableSink sink |
      sink.getExpr() = this |
      result = sink.getARuntimeTarget(context)
    )
  }
}

/** A delegate expression that is passed as the argument to a library callable. */
private class DelegateArgumentToLibraryCallableSink extends DelegateFlowSink {
  DelegateArgumentToLibraryCallableSink() {
    this.getExpr() instanceof DelegateArgumentToLibraryCallable
  }
}

/** A delegate expression that is added to an event. */
library class AddEventSource extends DelegateFlowSink {
  AddEventExpr ae;

  AddEventSource() {
    this.getExpr() = ae.getRValue()
  }

  /** Gets the event that this delegate is added to. */
  Event getEvent() {
    result = ae.getTarget()
  }
}

/**
 * Holds if data can flow (inter-procedurally) to delegate `sink` from
 * `node`. This predicate searches backwards from `sink` to `node`.
 *
 * The parameter `isReturned` indicates whether the path from `sink` to
 * `node` goes through a returned expression. The call context `lastCall`
 * records the last call on the path from `node` to `sink`, if any.
 */
private predicate flowsFrom(DelegateFlowSink sink, DataFlow::Node node, boolean isReturned, CallContext lastCall) {
  // Base case
  sink = node and
  isReturned = false and
  lastCall instanceof EmptyCallContext
  or
  // Local flow
  exists(DataFlow::Node mid |
    flowsFrom(sink, mid, isReturned, lastCall) |
    DataFlow::localFlowStep(node, mid) or
    node.asExpr() = mid.asExpr().(DelegateCreation).getArgument()
  )
  or
  // Flow through static field or property
  exists(DataFlow::Node mid |
    flowsFrom(sink, mid, _, _) and
    Cached::jumpStep(node, mid) and
    isReturned = false and
    lastCall instanceof EmptyCallContext
  )
  or
  // Flow into a callable (non-delegate call)
  exists(DataFlow::Internal::ExplicitParameterNode mid, CallContext prevLastCall, Expr call, Parameter p |
    flowsFrom(sink, mid, isReturned, prevLastCall) and
    isReturned = false and
    p = mid.getParameter() and
    flowIntoCallableNonDelegateCall(call, node.asExpr(), p) and
    lastCall = getLastCall(prevLastCall, call, p.getPosition())
  )
  or
  // Flow into a callable (delegate call)
  exists(DataFlow::Internal::ExplicitParameterNode mid, CallContext prevLastCall, DelegateCall dc, Callable c, Parameter p, int i |
    flowsFrom(sink, mid, isReturned, prevLastCall) and
    isReturned = false and
    flowIntoDelegateCall(dc, c, node.asExpr(), i) and
    c.getParameter(i) = p and
    p = mid.getParameter() and
    lastCall = getLastCall(prevLastCall, dc, i)
  )
  or
  // Flow out of a callable (non-delegate call).
  exists(DataFlow::Node mid |
    flowsFrom(sink, mid, _, lastCall) and
    isReturned = true and
    flowOutOfCallableNonDelegateCall(_, node.asExpr(), mid)
  )
  or
  // Flow out of a callable (delegate call).
  exists(DataFlow::ExprNode mid |
    flowsFrom(sink, mid, _, _) and
    isReturned = true and
    flowOutOfDelegateCall(mid.getExpr(), node.asExpr(), lastCall)
  )
}

/**
 * Gets the last call when tracking flow into `call`. The context
 * `prevLastCall` is the previous last call, so the result is the
 * previous call if it exists, otherwise `call` is the last call.
 */
bindingset [call, i]
private CallContext getLastCall(CallContext prevLastCall, Expr call, int i) {
  prevLastCall instanceof EmptyCallContext and
  result.(ArgumentCallContext).isArgument(call, i)
  or
  prevLastCall instanceof ArgumentCallContext and
  result = prevLastCall
}

// Predicate folding to get proper join-order
private predicate flowIntoDelegateCall(DelegateCall dc, Callable c, Expr e, int i) {
  exists(DelegateFlowSource dfs, DelegateCallExpr dce |
    // the call context is irrelevant because the delegate call
    // itself will be the context
    flowsFrom(dce, dfs, _, _) and
    e = dc.getArgument(i) and
    c = dfs.getCallable() and
    dc = dce.getDelegateCall()
  )
}

// Predicate folding to get proper join-order
private predicate flowOutOfDelegateCall(DelegateCall dc, Expr e, CallContext lastCall) {
  exists(DelegateFlowSource dfs, DelegateCallExpr dce, Callable c |
    flowsFrom(dce, dfs, _, lastCall) and
    c.canReturn(e) and
    c = dfs.getCallable() and
    dc = dce.getDelegateCall()
  )
}
