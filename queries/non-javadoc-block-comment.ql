/**
 * Finds regular block comments (`/* ... */`) which appear to be meant to
 * be javadoc comments (`/** ... */`).
 *
 * Note that this (on purpose) matches comments which start with `/* (non-Javadoc)`.
 * These comments are generated by some IDEs and add little value since IDEs usually
 * offer functionality for displaying the type hierarchy, an outline of a class or
 * methods which are overridden by a method, rendering the comment redundant.
 */

import java

bindingset[javadoc]
predicate containsJavadocTag(string javadoc) {
    exists (string tag |
        tag in [
            "author",
            "version",
            "param",
            "return",
            "exception",
            "throws",
            "see",
            "since",
            "serial",
            "serialField",
            "serialData",
            "deprecated"
        ]
        and exists (javadoc.indexOf("@" + tag))
    )
}

// Javadoc matches regular comments as well, see https://github.com/github/codeql/issues/3695
from Javadoc javadoc
where
    not exists (javadoc.getCommentedElement())
    // Ignore `//` comments, likely javadoc which was commented out
    // Note: This predicate might be an implementation detail, see https://github.com/github/codeql/issues/3695
    and not isEolComment(javadoc)
    and exists (JavadocText javadocText |
        javadocText = javadoc.getAChild()
        and containsJavadocTag(javadocText.getText())
    )
select javadoc
