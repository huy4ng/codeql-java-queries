/**
 * Finds assignment expressions which can be simplified by replacing them
 * with a compound assignment expression or with a unary increment or
 * decrement expression.
 * E.g.:
 * ```
 * // Could be replaced with `s += "suffix"`
 * s = s + "suffix";
 * ```
 */

import java

private predicate accessSameField(FieldAccess a, FieldAccess b) {
    a.isOwnFieldAccess() and b.isOwnFieldAccess()
    or exists (RefType enclosing |
        a.isEnclosingFieldAccess(enclosing)
        and b.isEnclosingFieldAccess(enclosing)
    )
    or accessSameVariable(a.getQualifier(), b.getQualifier())
}

// TODO: Reduce code duplication; already declared in redundant-value-or-type-check.ql
predicate accessSameVariable(VarAccess a, VarAccess b) {
    exists (Variable var | var = a.getVariable() |
        var = b.getVariable()
        and (
            var instanceof LocalScopeVariable
            or var.(Field).isStatic()
            or accessSameField(a, b)
        )
    )
}

private predicate isCommutative(BinaryExpr e) {
    e instanceof AddExpr
    // String concatenation is not commutative
    and not e.(AddExpr).getType() instanceof TypeString
    or e instanceof AndBitwiseExpr
    or e instanceof EqualityTest
    or e instanceof MulExpr
    or e instanceof OrBitwiseExpr
    or e instanceof XorBitwiseExpr
}

/**
 * Gets the binary expression which is part of the `assignExpr` which can
 * be simplified, and binds `otherOperand` to the operand of the result
 * binary expression which remains after simplification.
 */
private BinaryExpr getSimplifiableAssignOperation(AssignExpr assignExpr, Expr otherOperand) {
    exists(Variable var, VarAccess assignVarAccess, VarAccess updateVarAccess |
        assignVarAccess = var.getAnAccess()
        and updateVarAccess = var.getAnAccess()
        // Verify that both access same variable; ignore something like `var = other.var + ...`
        and accessSameVariable(assignVarAccess, updateVarAccess)
        and assignExpr.getRhs() = result
        and otherOperand = result.getAnOperand()
        and exists(Expr assignDest, Expr varReadOperand |
            assignDest = assignExpr.getDest()
            and if isCommutative(result) then varReadOperand = result.getAnOperand()
            // If not commutative only allow var read as left operand
            else varReadOperand = result.getLeftOperand()
            and varReadOperand != otherOperand
        |
            // Assignment of variable
            (
                assignDest = assignVarAccess
                and varReadOperand = updateVarAccess
            )
            // Or assignment of array element, where same variable is used as index expression
            or exists(Variable indexVar, VarAccess indexReadAssign, VarAccess indexReadOperand |
                indexReadAssign = indexVar.getAnAccess()
                and indexReadOperand = indexVar.getAnAccess()
                and accessSameVariable(indexReadAssign, indexReadOperand)
            |
                assignDest.(ArrayAccess).getArray() = assignVarAccess
                and assignDest.(ArrayAccess).getIndexExpr() = indexReadAssign
                and varReadOperand.(ArrayAccess).getArray() = updateVarAccess
                and varReadOperand.(ArrayAccess).getIndexExpr() = indexReadOperand
            )
        )
    )
}

private predicate hasValue1(Literal literal) {
    literal.(IntegerLiteral).getIntValue() = 1
    or literal.(LongLiteral).getValue().toInt() = 1
    or literal.(FloatingPointLiteral).getValue().toFloat() = 1
    or literal.(DoubleLiteral).getValue().toFloat() = 1
}

private string getUnaryIncrementOrDecrementMessage(AssignExpr assignExpr, BinaryExpr binaryExpr, Literal literal) {
    hasValue1(literal)
    and binaryExpr.getType() instanceof NumericType
    and exists(string operator |
        binaryExpr instanceof AddExpr and operator = "increment ++"
        or binaryExpr instanceof SubExpr and operator = "decrement --"
    |
        // If result of assignment is used (e.g. `doSomething(a = a + 1)`), then must use pre unary
        if assignExpr.getParent() instanceof Expr then result = "pre " + operator
        else result = "post " + operator
    )
}

private string getCompoundAssignOp(string op) {
    op = ["+", "-", "*", "/", "%", "&", "^", "|", "<<", ">>", ">>>"]
    and result = op + "="
}

from AssignExpr assignExpr, BinaryExpr binaryExpr, Expr otherOperand, string alternative
where
    binaryExpr = getSimplifiableAssignOperation(assignExpr, otherOperand)
    and(
        // Use `if-else` to prevent duplicate message for unary increment / decrement
        if (alternative = getUnaryIncrementOrDecrementMessage(assignExpr, binaryExpr, otherOperand)) then (
            any() // alternative is already bound
        ) else (
            // Get compound op; some operators (&& and ||) do not have one
            // Use getOp().trim() because it had leading and trailing spaces
            alternative = getCompoundAssignOp(binaryExpr.getOp().trim())
        )
    )
select assignExpr, "Should use " + alternative
