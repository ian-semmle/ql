void enabled(void) {
   int a = 1;
   int *p = &a;
   p = &(int)a;
}

// codeql-extractor-compiler: cl
// codeql-extractor-compiler-options: /Zc:rvalueCast -dsemmle--expect_errors
